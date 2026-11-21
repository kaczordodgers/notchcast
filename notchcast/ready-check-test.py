#!/usr/bin/env python3
"""Verify ready-check.sh covers every pr.yml step and reports PASS or the first failing gate."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from textwrap import dedent
import unittest
from unittest import mock

from ci import config


ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / ".github/workflows/pr.yml"
MAIN_HARNESSES = ROOT / ".github/workflows/main-harnesses.yml"
SCRIPT = ROOT / "notchcast/ready-check.sh"
# Every step of pr.yml and of the local actions it uses, and how ready-check.sh covers it.
COVERED = {
    ("pr.yml:route", "A harness-only run is never a train's"): "dispatched harness-only runs only",
    ("pr.yml:route", "actions/checkout"): "lane planning; no gate",
    ("pr.yml:route", "Lanes the diff needs"): "picks the jobs below; ready-check.sh runs them all",
    ("pr.yml:route", "Harnesses the diff needs"): "picks what a PR run's mac job runs; ready-check.sh runs the whole suite",
    ("pr.yml:mac", "actions/checkout"): "the shared clone at HEAD",
    ("pr.yml:mac", "./tools/notchcast/actions/xcode"): "ci-build.sh's xcode step",
    ("pr.yml:mac", "The harness runner's own Xcode"): "dispatched harness-only runs only",
    ("pr.yml:mac", "Runner kind"): "names a self-hosted run; no gate",
    ("pr.yml:mac", "Script tests that need macOS"): "ci-build.sh's script-tests step",
    ("pr.yml:mac", "Result of the script tests that need macOS"): "ci-build.sh's script-tests step",
    ("pr.yml:mac", "Shared PR build lane"): "ci-build.sh, unsharded",
    ("pr.yml:mac", "./tools/notchcast/actions/tests"): "ci-build.sh's harnesses step",
    ("pr.yml:mac", "Failures outside the harness selection"): "shadow selection; reports, gates nothing",
    ("pr.yml:mac", "Runner load at start"): "off a hosted runner: the job's own temp folder and load figures; no gate",
    ("pr.yml:mac", "Runner load at end"): "off a hosted runner: load figures; no gate",
    ("pr.yml:mac", "What the isolated runner proved"): "the isolated runner's stamp for its tested-tree record; no gate",
    ("pr.yml:linux-checks", "actions/checkout"): "the shared clone at HEAD",
    ("pr.yml:linux-checks", "Checks that need no Mac"): "ci-build.sh sources ci-checks.sh",
    ("pr.yml:linux-harnesses", "actions/cache"): "Linux Swift archive cache; no local step",
    ("pr.yml:linux-harnesses", "Install the pinned Swift toolchain"): "GitHub's Linux toolchain setup; ready-check.sh uses Xcode",
    ("pr.yml:linux-harnesses", "actions/checkout"): "the shared clone at HEAD",
    ("pr.yml:linux-harnesses", "Linux-ok harnesses the diff needs"): "ci-build.sh's harnesses step runs them all on the Mac",
    ("pr.yml:script-tests", "actions/checkout"): "the shared clone at HEAD",
    ("pr.yml:script-tests", "Script tests"): "ci-build.sh's script-tests step",
    ("pr.yml:build", "A train run names its base"): "train branches only",
    ("pr.yml:build", "A train's Mac job proves its tree"): "train branches only",
    ("pr.yml:build", "Every lane the diff needs passed, and only those were skipped"): "aggregate of the jobs above",
    ("pr.yml:build", "Config literals"): "ci-build.sh's config step",
    ("pr.yml:build", "actions/checkout"): "records the tree; no gate",
    ("pr.yml:build", "Record the tested tree"): "records the tree; no gate",
    ("pr.yml:build", "actions/upload-artifact"): "records the tree; no gate",
    ("xcode", 'source "$GITHUB_ACTION_PATH/../../ci-xcode.sh"'): "ci-build.sh sources ci-xcode.sh",
    ("tests", "actions/cache/restore"): "harness binary cache; no gate",
    ("tests", 'bash "$GITHUB_ACTION_PATH/../../ci-tests.sh"'): "ci-build.sh runs ci-tests.sh",
    ("tests", "Failed harness logs"): "logs only; ready-check keeps the whole log",
    ("tests", "Compiled harness cache"): "harness binary cache; no gate",
    ("tests", "actions/cache/save"): "harness binary cache; no gate",
}


def steps(path, step_indent):
    """(job, step text) for each step; a composite action has one job, its own."""
    job, found, current = None, [], None
    for line in path.read_text().splitlines():
        if match := re.fullmatch(r"  ([\w-]+):", line):
            job, current = match[1], None
        elif line.startswith(" " * step_indent + "- "):
            current = [line[step_indent + 2:]]
            found.append((job, current))
        elif current is not None and line.startswith(" " * (step_indent + 2)):
            current.append(line[step_indent + 2:])
        elif line.strip() and not line.startswith(" " * (step_indent + 2)):
            current = None
    return [(job, "\n".join(text)) for job, text in found]


def field(text, key):
    match = re.search(rf"^{key}: (.+)$", text, re.M)
    return match[1].strip() if match else None


def signature(text):
    if uses := field(text, "uses"):
        return uses.split("@")[0].split(" #")[0]
    return field(text, "name") or field(text, "id") or field(text, "run")


def env(text):
    block = re.search(r"^env:\n((?:  .+\n?)+)", text, re.M)
    return dict(re.findall(r"^  (\w+): (.+)$", block[1], re.M)) if block else {}


class CoverageTest(unittest.TestCase):
    def all_steps(self):
        found = [(f"pr.yml:{job}", text) for job, text in steps(WORKFLOW, 6)]
        for action in ("xcode", "tests"):
            found += [(action, text) for _, text in steps(ROOT / f"notchcast/actions/{action}/action.yml", 4)]
        return found

    def test_every_step_is_covered(self):
        found = {(scope, signature(text)) for scope, text in self.all_steps()}
        self.assertEqual(found - COVERED.keys(), set(), "a pr.yml step ready-check.sh does not cover")
        self.assertEqual(COVERED.keys() - found, set(), "COVERED names a step pr.yml no longer has")

    def test_the_build_lane_is_ci_build(self):
        lane = next(text for scope, text in self.all_steps() if signature(text) == "Shared PR build lane")
        self.assertEqual(field(lane, "run"), "bash ../tools/notchcast/ci-build.sh")
        self.assertEqual(set(env(lane)), {"BASE_SHA", "HEAD_SHA", "NOTCHCAST_HARNESSES_SHARDED"})
        script = SCRIPT.read_text()
        self.assertIn("export BASE_SHA HEAD_SHA", script)
        self.assertIn("unset NOTCHCAST_HARNESSES_SHARDED", script)
        self.assertIn("bash notchcast/ci-build.sh", script)

    def test_the_linux_toolchain_is_verified_before_use_even_from_the_cache(self):
        install = next(text for scope, text in self.all_steps() if signature(text) == "Install the pinned Swift toolchain")
        script = install
        check = script.index('printf \'%s  %s\\n\' "$SWIFT_SHA256" "$archive" | sha256sum --check')
        self.assertLess(script.index("fi"), check, "the check must run on a cache hit too")
        self.assertLess(check, script.index("tar "), "the archive must be verified before it is unpacked")
        self.assertRegex(WORKFLOW.read_text(), r"key: swift-.*\$\{\{ env\.SWIFT_VERSION \}\}-\$\{\{ env\.SWIFT_SHA256 \}\}")

    def test_the_harness_step_matches_ci_build(self):
        ci_build = (ROOT / "notchcast/ci-build.sh").read_text()
        self.assertIn('source "$TOOLS/notchcast/ci-xcode.sh"', ci_build)
        self.assertRegex(ci_build, r'NOTCHCAST_HARNESSES_SHARDED.*\n.*\n\s*bash "\$TOOLS/notchcast/ci-tests.sh"')
        run = next(text for scope, text in self.all_steps() if scope == "tests" and "ci-tests.sh" in text)
        ci_tests = (ROOT / "notchcast/ci-tests.sh").read_text()
        # Input-driven variables default to the whole suite; a fixed value must be one ci-tests.sh sets itself.
        for name, value in env(run).items():
            if "${{" not in value:
                self.assertRegex(ci_tests, rf"export .*\b{name}={value.strip(chr(39))}\b")


class SelectionTest(unittest.TestCase):
    def test_only_a_pull_request_runs_a_selection_and_it_keeps_its_own_cache(self):
        text = WORKFLOW.read_text()
        self.assertIn("  NOTCHCAST_HARNESS_SELECT: ${{ github.event_name == 'pull_request' && 'on' || 'shadow' }}\n", text)
        self.assertIn("      harness-only: ${{ steps.select.outputs.only }}\n", text)
        tests = next(text for job, text in steps(WORKFLOW, 6) if signature(text) == "./tools/notchcast/actions/tests")
        self.assertIn("  only: ${{ needs.route.outputs.harness-only }}\n", tests)
        self.assertIn("  cache: ${{ inputs.harness_runner == '' && (needs.route.outputs.harness-only == '' && 'pr-0of1' || 'pr-select') || '' }}", tests)


# The one way to a self-hosted Mac (README Runners): a dispatch, which no fork can start; unset, it is xcode-27.
GATED_MAC = ("${{ github.event_name == 'workflow_dispatch' && !inputs.hosted && vars.NOTCHCAST_MAC_RUNNER "
             "|| 'xcode-27' }}")
# pr.yml's mac job also takes the runner label a dispatch names for a harness-only run (README Runners).
HARNESS_MAC = ("${{ github.event_name == 'workflow_dispatch' && (inputs.harness_runner || !inputs.hosted "
               "&& vars.NOTCHCAST_MAC_RUNNER) || 'xcode-27' }}")
POOL_MAC = ("${{ needs.mac-route.result == 'success' && needs.mac-route.outputs.mac-runner == 'notchcast-mbp' "
            "&& 'notchcast-mbp' || 'xcode-27' }}")
HARNESS_ONLY, FULL_RUN = "inputs.harness_runner != ''", "inputs.harness_runner == ''"
# Labels a dispatch may name for a harness-only run (README Runners); free text names any runner.
HARNESS_RUNNERS = ["", "notchcast-mba", "notchcast-mbp"]
# Only jobs that hold no secret, sign with no identity and push nothing; a workflow outside this map is hosted-only.
GATED_JOBS = {"pr.yml": 1, "main-harnesses.yml": 1, "proof.yml": 1}
# Every macOS job (README Runners): it runs xcodebuild, compiles harnesses, signs or launches the app. Anything else is Linux.
MAC_JOBS = {"pr.yml": 1, "main-harnesses.yml": 1, "delete-check.yml": 1, "proof.yml": 1, "snapshot.yml": 2, "sync.yml": 1,
            "sync-release.yml": 2, "test-build.yml": 2, "tester.yml": 1}


class RunnerTest(unittest.TestCase):
    def test_every_job_runs_on_a_hosted_image(self):
        allowed = {"ubuntu-24.04", "ubuntu-latest", "xcode-27"}
        gated, mac = {}, {}
        for workflow in sorted((ROOT / ".github/workflows").glob("*.y*ml")):
            lines = workflow.read_text().splitlines()
            for i, line in enumerate(lines):
                match = re.match(r"(\s*)runs-on:(.*)", line)
                if not match:
                    continue
                gate = HARNESS_MAC if workflow.name == "pr.yml" else GATED_MAC
                if workflow == MAIN_HARNESSES:
                    gate = POOL_MAC
                if match[2].strip() == gate or match[2].strip() == "xcode-27":
                    mac[workflow.name] = mac.get(workflow.name, 0) + 1
                if match[2].strip() == gate:
                    gated[workflow.name] = gated.get(workflow.name, 0) + 1
                    continue
                value = [match[2].split("#")[0]]
                for more in lines[i + 1:]:
                    if more.strip() and len(more) - len(more.lstrip()) <= len(match[1]):
                        break
                    value.append(more.split("#")[0])
                labels = re.findall(r"[^\s\[\],'\"-][^\s\[\],'\"]*", " ".join(value))
                with self.subTest(f"{workflow.name}:{i + 1}"):
                    self.assertTrue(labels, "runs-on has no label")
                    self.assertEqual(set(labels) - allowed, set(), "runs-on names a runner README Runners does not")
        self.assertEqual(gated, GATED_JOBS, "only these jobs may leave the hosted images, behind the fork gate")
        self.assertEqual(mac, MAC_JOBS, "a new macOS job needs a reason a Linux job cannot meet")

    def test_a_train_passes_its_lane_to_every_workflow_that_can_leave_the_hosted_images(self):
        for name in GATED_JOBS:
            self.assertRegex((ROOT / ".github/workflows" / name).read_text(),
                             r"\n      hosted:\n        description: .*\n        type: boolean\n        default: false\n", name)
        train = (ROOT / "notchcast/train.sh").read_text()
        dispatched = re.search(r"^workflows='(.*)'$", train, re.M)[1].split()
        self.assertEqual(re.search(r"^mac_workflows='(.*)'$", train, re.M)[1].split(), [name for name in dispatched if name in GATED_JOBS])

    def test_proof_refuses_a_working_mac_before_anything_else(self):
        first = next(text for job, text in steps(ROOT / ".github/workflows/proof.yml", 6) if job == "proof")
        self.assertEqual(signature(first), "Refuse a working Mac")
        self.assertEqual(field(first, "if"), "runner.environment != 'github-hosted'")
        self.assertIsNone(field(first, "continue-on-error"), "a guard that may fail lets a working Mac through")
        self.assertIn('[ "${NOTCHCAST_ISOLATED_RUNNER:-}" = 1 ] && exit 0\n'
                      '  echo "::error::Proof launches the app: hosted or isolated runner only"\n  exit 1', first)

    def test_a_working_mac_proves_no_tree_and_an_isolated_one_records_under_its_own_name(self):
        found = {(job, signature(text)): text for job, text in steps(WORKFLOW, 6)}
        proves = ("needs.route.outputs.build == 'true' && needs.mac.outputs.kind != 'working'"
                  " && needs.route.outputs.harness-only == ''")
        for step in ("Record the tested tree", "actions/upload-artifact"):
            self.assertEqual(field(found["build", step], "if"), proves, step)
        text = WORKFLOW.read_text()
        self.assertIn("      kind: ${{ steps.runner.outputs.kind }}\n", text)
        self.assertIn("name: tested-tree-${{ needs.mac.outputs.kind == 'isolated' && 'isolated-' || '' }}${{ steps.tree.outputs.key }}\n", text)
        self.assertEqual(env(found["mac", "Runner kind"]), {"HOSTED": "${{ runner.environment == 'github-hosted' }}",
                                                            "HARNESS_ONLY": "${{ inputs.harness_runner != '' }}"})
        self.assertIn('if [ "$HOSTED" = true ]; then kind=hosted; elif [ "${NOTCHCAST_ISOLATED_RUNNER:-}" = 1 ]; then kind=isolated; fi',
                      found["mac", "Runner kind"])
        self.assertEqual(field(found["mac", "Script tests that need macOS"], "if"), "steps.runner.outputs.kind != 'working'")
        self.assertEqual(field(found["build", "A train's Mac job proves its tree"], "if"),
                         "startsWith(github.ref, 'refs/heads/train/') && needs.mac.outputs.kind == 'working'")
        # Only Sync's hosted job sets the tested status; a job that may run self-hosted has no way to.
        for name in GATED_JOBS:
            self.assertNotIn("statuses: write", (ROOT / ".github/workflows" / name).read_text(), name)

    def test_only_a_dispatch_reaches_a_named_runner(self):
        # GitHub's && and || return an operand, as Python's and/or do; an unset input or variable is ''.
        def runs_on(expression, **values):
            code = expression[4:-3].replace("&&", "and").replace("||", "or").replace("!", "not ")
            return eval(re.sub(r"\b(?:github|inputs|vars)\.(\w+)", r"v['\1']", code), {"v": values})
        for event in ("pull_request", "pull_request_target", "push", "workflow_dispatch"):
            for label in HARNESS_RUNNERS:
                for hosted in (False, True):
                    for variable in ("", "notchcast-mbp"):
                        values = {"event_name": event, "harness_runner": label, "hosted": hosted, "NOTCHCAST_MAC_RUNNER": variable}
                        runner = runs_on(HARNESS_MAC, **values)
                        with self.subTest(values):
                            if event != "workflow_dispatch":
                                self.assertEqual(runner, "xcode-27")
                            elif label:
                                self.assertEqual(runner, label)
                            else:
                                self.assertEqual(runner, runs_on(GATED_MAC, **values), "an empty input changes nothing")

    def test_draft_prs_build_and_ready_status_does_not_restart_ci(self):
        text = WORKFLOW.read_text()
        self.assertIn("    types: [opened, synchronize, reopened]\n", text)
        self.assertNotIn("github.event.pull_request.draft", text)
        self.assertRegex(text, r"(?m)^  group: .*github\.event\.pull_request\.head\.label")
        self.assertIn("  cancel-in-progress: ${{ github.ref_name != github.event.repository.default_branch }}", text)

    def test_a_harness_runner_is_one_of_the_known_labels(self):
        self.assertIn("      harness_runner:\n        description: Runner label for a harness-only macOS job (notchcast-mba, notchcast-mbp); "
                      "no build, no proof of any tree (README, Runners)\n        type: choice\n"
                      f"        options: [{', '.join(repr(label) if not label else label for label in HARNESS_RUNNERS)}]\n"
                      "        default: ''\n", WORKFLOW.read_text())

    def test_a_harness_only_run_builds_nothing_and_proves_no_tree(self):
        found = {(job, signature(text)): text for job, text in steps(WORKFLOW, 6)}
        text = WORKFLOW.read_text()
        self.assertEqual(field(found["mac", "./tools/notchcast/actions/xcode"], "if"), FULL_RUN)
        own = found["mac", "The harness runner's own Xcode"]
        self.assertEqual((field(own, "if"), env(own)), (HARNESS_ONLY, {"NOTCHCAST_XCODE_FROM_RUNNER": "'1'"}))
        self.assertEqual(field(found["mac", "Shared PR build lane"], "if"), f"needs.route.outputs.build == 'true' && {FULL_RUN}")
        # working on any runner: the macOS script tests, the toolchain stamp and the tested-tree record all hang on kind.
        kind = found["mac", "Runner kind"]
        self.assertIn('if [ "$HARNESS_ONLY" = true ]; then kind=working;', kind)
        self.assertLess(kind.index("then kind=working;"), kind.index('echo "kind=$kind"'))
        self.assertEqual(field(found["mac", "What the isolated runner proved"], "if"),
                         "steps.runner.outputs.kind == 'isolated' && needs.route.outputs.build == 'true'")
        tests = found["mac", "./tools/notchcast/actions/tests"]
        self.assertEqual(field(tests, "if"), f"needs.route.outputs.build == 'true' || {HARNESS_ONLY}")
        self.assertIn("cache: ${{ inputs.harness_runner == '' && (needs.route.outputs.harness-only == '' && 'pr-0of1' || 'pr-select') || '' }}", tests)
        self.assertEqual((ROOT / "notchcast/actions/tests/action.yml").read_text().count("inputs.cache != ''"), 3,
                         "no cache: the restore, the cache folder and the finish step")
        # No other job runs, the build check least of all: land.sh reads it, and train.sh a train run's conclusion.
        for job, lane in (("linux-checks", "build"), ("script-tests", "scripts"), ("linux-harnesses", "build")):
            self.assertIn(f"  {job}:\n    needs: route\n    if: needs.route.outputs.{lane} == 'true' && {FULL_RUN}\n", text)
        self.assertIn(f"    if: ${{{{ !cancelled() && {FULL_RUN} }}}}\n", text)
        refusal = found["route", "A harness-only run is never a train's"]
        self.assertEqual(field(refusal, "if"), f"{HARNESS_ONLY} && startsWith(github.ref, 'refs/heads/train/')")
        self.assertIn("exit 1", refusal)
        self.assertRegex(text, r"\nconcurrency:\n  group: .*\$\{\{ inputs\.harness_runner && format\('-\{0\}', "
                               r"inputs\.harness_runner\) \|\| '' \}\}\n")


class MacPoolTest(unittest.TestCase):
    def run_route(self, *, pool="1 1800000000", tests="SafeTests", config_change=None,
                  head_files=None, **variables):
        step = next(text for _, text in steps(MAIN_HARNESSES, 6)
                    if signature(text) == "Route the selected Mac harnesses")
        script = dedent(step.split("\nrun: |\n", 1)[1])
        cfg = config()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)

            def git(*args):
                return subprocess.check_output(["git", *args], cwd=root, text=True, env=fixture_env({
                    "GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "test@example.com",
                    "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "test@example.com",
                })).strip()

            git("init", "-q")
            (root / "notchcast").mkdir()
            (root / "Tests").mkdir()
            config_path = root / "notchcast/config.env"
            config_path.write_text((ROOT / "notchcast/config.env").read_text())
            for name in ("ci-tests-test.sh", "ci-xcode.sh", "ci-tests.sh"):
                shutil.copyfile(ROOT / "notchcast" / name, root / "notchcast" / name)
            for name, content in {
                "SafeTests": "// Pure harness fixture",
                "FormInputTests": "// Listed in config.env",
                "ClipboardTextTests": "// Listed in config.env",
                "TaggedTests": "// notchcast-hosted-only",
                "SkippedTests": "// notchcast-ci-skip",
                "RiskyTests": "// NSWindow(",
            }.items():
                (root / f"Tests/{name}.swift").write_text(content + "\n")
            git("add", ".")
            git("commit", "-qm", "Main")
            git("update-ref", "refs/remotes/origin/main", "HEAD")
            if config_change:
                config_path.write_text(config_change(config_path.read_text()))
            for name, content in (head_files or {}).items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content + "\n")
            git("add", ".")
            git("commit", "--allow-empty", "-qm", "Head")

            head = git("rev-parse", "HEAD")
            git("checkout", "-q", "--detach", "origin/main")
            output = root / "output"
            output.touch()
            result = subprocess.run(
                ["bash", "-euo", "pipefail", "-c", "date() { echo 1800000000; }\n" + script],
                cwd=root, capture_output=True, text=True, timeout=10,
                env=fixture_env({"LC_ALL": "C", "GITHUB_OUTPUT": str(output), "GITHUB_SHA": head,
                                 "GITHUB_REPOSITORY": cfg["FORK_REPO"], "GITHUB_REF_TYPE": "branch",
                                 "GITHUB_ACTOR": cfg["MAINTAINER_LOGIN"], "GITHUB_TRIGGERING_ACTOR": cfg["MAINTAINER_LOGIN"],
                                 "POOL_FREE": pool, "TESTS": tests, **variables}),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            return output.read_text()

    def test_only_a_maintainer_dispatch_of_a_branch_selection_can_route(self):
        workflow = MAIN_HARNESSES.read_text()
        route = next(text for job, text in steps(MAIN_HARNESSES, 6)
                     if job == "mac-route" and signature(text) == "Route the selected Mac harnesses")
        self.assertIn("    if: ${{ !inputs.hosted && !inputs.all && vars.POOL_FREE_NOTCHCAST_MAC != '' "
                      "&& needs.plan.outputs.tests != '' }}\n", workflow)
        self.assertEqual(env(route)["POOL_FREE"], "${{ vars.POOL_FREE_NOTCHCAST_MAC }}")
        self.assertIn(f"    runs-on: {POOL_MAC}\n", workflow)
        self.assertNotIn("notchcast-mba", workflow)
        self.assertNotIn("tested-tree", workflow)
        for key, value in (("GITHUB_REPOSITORY", "other/fork"), ("GITHUB_REF_TYPE", "tag"),
                           ("GITHUB_ACTOR", "bot"), ("GITHUB_TRIGGERING_ACTOR", "bot")):
            with self.subTest(key=key):
                self.assertEqual(self.run_route(**{key: value}), "")

    def test_pool_requires_fresh_availability_and_equal_coverage(self):
        for pool, tests, use_pool in (
            ("1 1800000000", "SafeTests ", True),
            ("4\t1799999821", "SafeTests", True),
            ("4 1799999820", "SafeTests", False),
            ("1 1800000001", "SafeTests", False),
            ("0 1800000000", "SafeTests", False),
            ("", "SafeTests", False),
            ("1 1800000000 extra", "SafeTests", False),
            ("1 999999999999999999999999999", "SafeTests", False),
            ("-1 1800000000", "SafeTests", False),
            ("1\n1800000000", "SafeTests", False),
            ("1 1800000000", "", False),
            ("1 1800000000", "SafeTests FormInputTests", False),
            ("1 1800000000", "SafeTests ClipboardTextTests", False),
            ("1 1800000000", "SafeTests MissingTests", False),
        ):
            with self.subTest(pool=pool, tests=tests):
                self.assertEqual(self.run_route(pool=pool, tests=tests),
                                 "runs-on=notchcast-mbp\n" if use_pool else "")

    def test_config_must_match_main_including_the_lists(self):
        def remove_listed(text):
            return text.replace(" FormInputTests", "").replace('CI_SKIP_TESTS="ClipboardTextTests"', 'CI_SKIP_TESTS=""')

        for test in ("FormInputTests", "ClipboardTextTests"):
            with self.subTest(test=test):
                self.assertEqual(self.run_route(tests=test, config_change=remove_listed), "")
        self.assertEqual(self.run_route(config_change=remove_listed), "")
        self.assertEqual(self.run_route(config_change=lambda text: text + '\n: "$GITHUB_OUTPUT"\n'), "")
        self.assertEqual(self.run_route(config_change=lambda text: text.replace(
            'CI_SKIP_TESTS="ClipboardTextTests"', 'CI_SKIP_TESTS="ClipboardTextTests SafeTests"')), "")

    def test_base_and_head_tags_and_risky_apis_keep_the_selection_hosted(self):
        for test, content in (("TaggedTests", "// notchcast-hosted-only"),
                              ("SkippedTests", "// notchcast-ci-skip"),
                              ("RiskyTests", "// NSWindow(")):
            with self.subTest(test=test):
                self.assertEqual(self.run_route(tests=test, head_files={f"Tests/{test}.swift": "// Pure harness fixture"}), "")
                self.assertEqual(self.run_route(head_files={"Tests/SafeTests.swift": content}), "")


    def test_ci_files_must_match_main(self):
        for path in ("notchcast/actions/xcode/action.yml", "notchcast/actions/tests/action.yml",
                     "notchcast/ci-xcode.sh", "notchcast/ci-tests.sh", "notchcast/swiftc-cache.py",
                     "notchcast/test-harnesses.sh", "Scripts/run-tests.sh", "json.py"):
            with self.subTest(path=path):
                self.assertEqual(self.run_route(head_files={path: "# Different on head"}), "")
        self.assertEqual(self.run_route(head_files={
            "Tests/SafeTests.swift": "// Safe test change", "Tinycast/Feature.swift": "// Product change",
        }), "runs-on=notchcast-mbp\n")

    def test_copies_of_listed_or_tagged_harnesses_stay_hosted(self):
        for test, content in (("ClipboardTextTests", "// Listed in config.env"),
                              ("TaggedTests", "// notchcast-hosted-only"),
                              ("SkippedTests", "// notchcast-ci-skip")):
            with self.subTest(test=test):
                self.assertEqual(self.run_route(tests="RenamedTests", head_files={
                    "Tests/RenamedTests.swift": content, f"Tests/{test}.swift": "// Changed on head",
                }), "")
        self.assertEqual(self.run_route(tests="RenamedTests", head_files={
            "Tests/RenamedTests.swift": "// New content in a listed harness",
            "Tests/ClipboardTextTests.swift": "// New content in a listed harness",
        }), "")

    def test_skipped_or_empty_route_keeps_planned_harnesses_hosted(self):
        job = MAIN_HARNESSES.read_text().split("\n  harnesses:\n", 1)[1]
        job = dedent(job)
        self.assertEqual(field(job, "needs"), "[plan, mac-route]")
        self.assertEqual(field(job, "if"),
                         "${{ !cancelled() && needs.plan.result == 'success' && needs.plan.outputs.shards != '[]' }}")
        self.assertEqual(field(job, "runs-on"), POOL_MAC)
        self.assertEqual(self.run_route(pool=""), "")


# Machine git config (init.defaultBranch, signing, url rewrites) never reaches the fixture repos.
GIT_ISOLATED = {"GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull}


# A builder's own NOTCHCAST_READY_BRANCH would judge every fixture as that branch.
def fixture_env(extra):
    return {**{k: v for k, v in os.environ.items() if k != "NOTCHCAST_READY_BRANCH"}, **GIT_ISOLATED, **extra}


# Fails when the judged tree has drift-fail; records its arguments and what origin/main resolves to.
DRIFT_STUB = """import subprocess, sys
from pathlib import Path
root = Path(sys.argv[sys.argv.index('--root') + 1])
main = subprocess.run(['git', '-C', str(root), 'rev-parse', 'refs/remotes/origin/main'],
                      capture_output=True, text=True).stdout.strip()
print('drift', *sys.argv[1:], 'main=' + main)
sys.exit((root / 'drift-fail').exists())
"""


# Fails when the judged tree has delete-fail; prints its arguments as the delete test's verdict line.
DELETE_STUB = """import sys
from pathlib import Path
verdict = 'FAIL' if Path('delete-fail').exists() else 'PASS'
print(verdict, 'delete Stub', *sys.argv[1:])
sys.exit(verdict == 'FAIL')
"""


class BehaviourTest(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix="ready-check-")
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)
        self.repo = self.root / "repo"
        (self.repo / "notchcast").mkdir(parents=True)
        (self.root / "home").mkdir()
        shutil.copy(SCRIPT, self.repo / "notchcast/ready-check.sh")
        (self.repo / "notchcast/config.env").write_text("FORK_REPO=example/fork\nUPSTREAM_REPO=example/upstream\n"
                                                       "MAINTAINER_NAME=t\nMAINTAINER_EMAIL=t@t\n")
        for tool in ("check-identity.sh", "check-identity.py", "check-commit-emails.py", "ci.py"):
            shutil.copy(ROOT / "notchcast" / tool, self.repo / "notchcast" / tool)
        (self.repo / "notchcast/ci-build.sh").write_text(
            'for s in xcode build lint; do echo "$s" > "$RUNNER_TEMP/step"; [ ! -e "fail-$s" ] || exit 1; done\n'
            'echo "base=$BASE_SHA head=$HEAD_SHA sharded=${NOTCHCAST_HARNESSES_SHARDED:-} pwd=$PWD"\n')
        shutil.copy(ROOT / "notchcast/drift-gates.sh", self.repo / "notchcast/drift-gates.sh")
        shutil.copy(ROOT / "notchcast/fork-point.sh", self.repo / "notchcast/fork-point.sh")
        (self.repo / "notchcast/check-addon-delete.py").write_text(DELETE_STUB)
        (self.repo / "notchcast/check-drift.py").write_text(DRIFT_STUB)
        self.git("init", "-q", "-b", "main")
        self.commit("base")
        self.git("tag", "base")
        bare = self.root / "fork.git"
        subprocess.run(["git", "init", "-q", "--bare", "-b", "main", str(bare)], check=True,
                       env={**os.environ, **GIT_ISOLATED})
        self.git("push", "-q", str(bare), "main", "base")
        upstream = self.upstream = self.root / "upstream.git"
        subprocess.run(["git", "clone", "-q", "--bare", str(bare), str(upstream)], check=True,
                       env={**os.environ, **GIT_ISOLATED})
        self.env = fixture_env({"HOME": str(self.root / "home"), "GIT_CONFIG_COUNT": "2",
                                "GIT_CONFIG_KEY_0": f"url.{bare}.insteadOf",
                                "GIT_CONFIG_VALUE_0": "https://github.com/example/fork.git",
                                "GIT_CONFIG_KEY_1": f"url.{upstream}.insteadOf",
                                "GIT_CONFIG_VALUE_1": "https://github.com/example/upstream.git",
                                "NOTCHCAST_HARNESSES_SHARDED": "1"})

    def git(self, *arguments):
        return subprocess.run(["git", "-C", str(self.repo), *arguments], check=True, capture_output=True,
                              text=True, env={**os.environ, **GIT_ISOLATED, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t",
                                              "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}).stdout.strip()

    def commit(self, message, path=None):
        if path:
            (self.repo / path).write_text(message)
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)

    def check(self, *arguments):
        return subprocess.run(["bash", "notchcast/ready-check.sh", *arguments], cwd=self.repo, env=self.env,
                              capture_output=True, text=True)

    def test_pass_builds_head_against_the_base(self):
        self.commit("work", "work.txt")
        result = self.check("base")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        head = self.git("rev-parse", "HEAD")
        self.assertEqual(result.stdout.splitlines()[-1], f"PASS {head[:12]} against base ({self.git('rev-parse', 'base')[:12]})")
        log = (self.root / "home/Library/Caches/notchcast/ready-check" / f"{head[:12]}.log").read_text()
        self.assertIn(f"base={self.git('rev-parse', 'base')} head={head} sharded= ", log)
        self.assertNotIn(str(self.repo), log.split("pwd=")[1], "the build must run in a clone outside the checkout")

    def test_the_default_base_is_origin_main(self):
        self.git("update-ref", "refs/remotes/origin/main", "base")
        self.commit("stack", "stack.txt")
        self.git("update-ref", "refs/remotes/origin/v2/stack", "HEAD")
        self.commit("work", "work.txt")
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.splitlines()[-1],
                         f"PASS {self.git('rev-parse', 'HEAD')[:12]} against origin/main ({self.git('rev-parse', 'base')[:12]})")

    def test_pass_names_ignored_harnesses(self):
        lines = self.check("base").stdout.splitlines()
        self.assertEqual(lines[-2], "ignored (fails upstream too): none")
        (self.repo / "notchcast/ci-build.sh").write_text(
            "echo '::warning::BTests fails on upstream abc1234 too; not ours, ignored'\n"
            "echo '::warning::ATests fails on upstream abc1234 too; not ours, ignored'\n")
        self.commit("ignored")
        result = self.check("base")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        lines = result.stdout.splitlines()
        self.assertEqual(lines[-2], "ignored (fails upstream too): ATests BTests")
        self.assertTrue(lines[-1].startswith("PASS "))

    def test_the_parsed_line_is_the_one_ci_tests_prints(self):
        ci_tests = (ROOT / "notchcast/ci-tests.sh").read_text()
        self.assertIn('echo "::warning::$name fails on upstream ${UPSTREAM:0:7} too; not ours, ignored"', ci_tests)

    def test_fail_names_the_first_failing_gate(self):
        self.commit("break", "fail-build")
        result = self.check("base")
        self.assertEqual(result.returncode, 1)
        self.assertRegex(result.stdout.splitlines()[-1], r"^FAIL build; log: ")

    def test_runs_land_drift_gates_against_the_base(self):
        self.commit("work", "work.txt")
        result = self.check("base")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        base = self.git("rev-parse", "base")
        log = (self.root / "home/Library/Caches/notchcast/ready-check" / f"{self.git('rev-parse', 'HEAD')[:12]}.log").read_text()
        self.assertRegex(log, rf"drift --root \S+ --compare-base {base} main={base}\n")
        self.assertRegex(log, rf"drift --root \S+ main={base}\n")

    def test_drift_fails_with_the_base_tools(self):
        (self.repo / "notchcast/check-drift.py").write_text("import sys; sys.exit(0)\n")
        (self.repo / "drift-fail").write_text("")
        self.commit("drift and a weakened gate")
        result = self.check("base")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertRegex(result.stdout.splitlines()[-1], r"^FAIL drift; log: ")
        self.assertIn("REFUSED: drift", result.stdout)

    def test_private_data_added_by_the_branch_fails(self):
        home = "/" + "Users/" + "someone/notes.txt"
        self.commit(f"path {home}\n", "work.txt")
        result = self.check("base")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("check-identity: work.txt:1: <home-path>\n", result.stdout)
        self.assertRegex(result.stdout.splitlines()[-1], r"^FAIL identity: diff names something private; log: ")
        self.git("reset", "-q", "--hard", "base")
        self.git("commit", "-q", "--allow-empty", "-m", f"moved {home}")
        result = self.check("base")
        self.assertRegex(result.stdout.splitlines()[-1], r"^FAIL identity: metadata names something private; ")
        self.git("reset", "-q", "--hard", "base")
        self.commit("clean", "clean.txt")
        self.assertEqual(self.check("base").returncode, 0)

    def rewritten_main(self):
        """A head cut from old main, which a Sync then rewrote; old main carries a private path."""
        home = "/" + "Users/" + "someone/notes.txt"
        self.commit(f"path {home}\n", "old.txt")
        old = self.git("rev-parse", "HEAD")
        self.commit("work", "work.txt")
        head = self.git("rev-parse", "HEAD")
        self.git("checkout", "-q", "--detach", "base")
        self.commit("rewritten old", "old.txt")
        self.git("tag", "main2")
        self.git("checkout", "-q", "--detach", head)
        return old, head

    def build_base(self, head):
        log = (self.root / "home/Library/Caches/notchcast/ready-check" / f"{head[:12]}.log").read_text()
        return re.search(r"^base=(\w+) ", log, re.M)[1]

    def test_a_branch_from_main_diffs_from_main(self):
        self.commit("work", "work.txt")
        result = self.check("base")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("fork point", result.stdout)
        self.assertEqual(self.build_base(self.git("rev-parse", "HEAD")), self.git("rev-parse", "base"))

    def test_a_head_before_a_rewrite_diffs_from_its_fork_point(self):
        old, head = self.rewritten_main()
        self.git("push", "-q", str(self.root / "fork.git"), f"{old}:refs/notchcast/synced/old")
        result = self.check("main2")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"fork point: {old[:12]}, before a Sync rewrite\n", result.stdout)
        self.assertEqual(self.build_base(head), old)
        self.assertEqual(result.stdout.splitlines()[-1],
                         f"PASS {head[:12]} against main2 ({self.git('rev-parse', 'main2')[:12]})")

    def test_without_a_synced_ref_the_rewrite_counts_as_the_branch(self):
        self.rewritten_main()
        result = self.check("main2")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertRegex(result.stdout.splitlines()[-1], r"^FAIL identity: ")

    def test_a_branch_updated_onto_the_rewrite_diffs_from_main(self):
        old, _ = self.rewritten_main()
        self.git("push", "-q", str(self.root / "fork.git"), f"{old}:refs/notchcast/synced/old")
        self.git("checkout", "-q", "--detach", "main2")
        self.commit("work", "work.txt")
        result = self.check("main2")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("fork point", result.stdout)
        self.assertEqual(self.build_base(self.git("rev-parse", "HEAD")), self.git("rev-parse", "main2"))

    def test_a_disabled_scanner_fails_with_the_base_one(self):
        (self.repo / "notchcast/check-identity.sh").write_text("exit 0\n")
        (self.repo / "notchcast/check-identity.py").write_text("raise SystemExit(0)\n")
        self.commit("path " + "/" + "Users/someone/notes.txt\n", "work.txt")
        result = self.check("base")
        self.assertNotIn("identity: bootstrap", result.stdout)
        self.assertRegex(result.stdout.splitlines()[-1], r"^FAIL identity: diff names something private; ")

    def test_a_head_pythonpath_cannot_run_code_in_the_base_scanner(self):
        config = self.repo / "notchcast/config.env"
        config.write_text(config.read_text() + 'export PYTHONPATH="$PWD/notchcast/injected"\n')
        (self.repo / "notchcast/injected").mkdir()
        (self.repo / "notchcast/injected/sitecustomize.py").write_text("import os\nos._exit(0)\n")
        self.commit("path " + "/" + "Users/someone/notes.txt\n", "work.txt")
        result = self.check("base")
        self.assertRegex(result.stdout.splitlines()[-1], r"^FAIL identity: diff names something private; ")

    def test_a_head_binary_attribute_still_scans_the_text(self):
        (self.repo / ".gitattributes").write_text("work.txt -diff\n")
        self.commit("path " + "/" + "Users/someone/notes.txt\n", "work.txt")
        result = self.check("base")
        self.assertIn("check-identity: work.txt:1: <home-path>\n", result.stdout)
        self.assertIn("check-identity: work.txt:1 (commit addition): <home-path>\n", result.stdout)
        self.assertRegex(result.stdout.splitlines()[-1], r"^FAIL identity: diff names something private; ")

    def test_a_base_scanner_without_text_still_fails_through_heads(self):
        scanner = self.repo / "notchcast/check-identity.py"
        scanner.write_text(scanner.read_text().replace('"--text", ', ""))
        self.commit("old scanner")
        self.git("tag", "-f", "base")
        shutil.copy(ROOT / "notchcast/check-identity.py", scanner)
        (self.repo / ".gitattributes").write_text("work.txt -diff\n")
        (self.repo / "work.txt").write_text("path " + "/" + "Users/someone/notes.txt\n")
        self.commit("binary work")
        result = self.check("base")
        self.assertRegex(result.stdout.splitlines()[-1], r"^FAIL identity: diff names something private; ")

    def test_a_head_path_cannot_replace_the_scanners_python(self):
        config = self.repo / "notchcast/config.env"
        config.write_text(config.read_text() + 'export PATH="$PWD/notchcast/bin:$PATH"\n')
        (self.repo / "notchcast/bin").mkdir()
        (self.repo / "notchcast/bin/python3").write_text(
            f'#!/bin/bash\n[ "$1" != -I ] || exit 0\nexec {shutil.which("python3")} "$@"\n')
        (self.repo / "notchcast/bin/python3").chmod(0o755)
        self.commit("path " + "/" + "Users/someone/notes.txt\n", "work.txt")
        result = self.check("base")
        self.assertRegex(result.stdout.splitlines()[-1], r"^FAIL identity: diff names something private; ")

    def test_a_head_git_config_cannot_drop_the_base_scanner(self):
        config = self.repo / "notchcast/config.env"
        config.write_text(config.read_text() + "export GIT_CONFIG_COUNT=3 GIT_CONFIG_KEY_2=core.attributesFile\n"
                          'export GIT_CONFIG_VALUE_2="$PWD/notchcast/attributes"\n')
        (self.repo / "notchcast/attributes").write_text("check-identity.py export-ignore\n")
        (self.repo / "notchcast/check-identity.py").write_text("raise SystemExit(0)\n")
        self.commit("path " + "/" + "Users/someone/notes.txt\n", "work.txt")
        result = self.check("base")
        self.assertNotIn("identity: bootstrap", result.stdout)
        self.assertRegex(result.stdout.splitlines()[-1], r"^FAIL identity: diff names something private; ")

    def test_a_base_without_a_scanner_bootstraps_from_head(self):
        self.git("rm", "-q", "notchcast/check-identity.py")
        self.commit("no scanner")
        self.git("tag", "bare")
        self.git("checkout", "-q", "base", "--", "notchcast/check-identity.py")
        self.commit("path " + "/" + "Users/someone/notes.txt\n", "work.txt")
        result = self.check("bare")
        self.assertIn("identity: bootstrap, scanner from HEAD\n", result.stdout)
        self.assertRegex(result.stdout.splitlines()[-1], r"^FAIL identity: diff names something private; ")

    def test_an_upstream_line_passes_and_a_fork_added_home_path_fails(self):
        fixture, line = self.repo / "Tests/Fixture.swift", 'let path = "/' + 'Users/x/notes.md"\n'
        fixture.parent.mkdir()
        fixture.write_text(line)
        self.commit("upstream fixture")
        self.git("push", "-q", str(self.upstream), "HEAD:main")
        result = self.check("base")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        fixture.write_text(line + line.replace("x/", "y/"))
        self.commit("fork fixture")
        result = self.check("base")
        self.assertIn("check-identity: Tests/Fixture.swift:2: <home-path>\n", result.stdout)
        self.assertNotIn("Tests/Fixture.swift:1", result.stdout)
        self.assertRegex(result.stdout.splitlines()[-1], r"^FAIL identity: diff names something private; ")

    def test_prints_the_upstream_footprint_and_its_delta(self):
        self.commit("work", "work.txt")
        self.commit("stock edit", "notchcast/ci-build.sh")
        self.git("rm", "-q", "notchcast/drift-gates.sh")
        self.commit("stock delete")
        deleted = 2 + len((ROOT / "notchcast/drift-gates.sh").read_text().splitlines())
        result = self.check("base")
        base = self.git("rev-parse", "base")
        self.assertIn(f"upstream touch: 2 files, +1 −{deleted} (base {base[:12]})\n"
                      f"delta: +2 files, +{deleted + 1} lines\n",
                      result.stdout)

    def test_an_addon_may_not_touch_upstream_paths(self):
        self.commit("own", "addon.txt")
        self.env["NOTCHCAST_READY_BRANCH"] = "v2/addons-zen"
        self.assertEqual(self.check("base").returncode, 0)
        self.commit("stock edit", "notchcast/ci-build.sh")
        result = self.check("base")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout.splitlines()[-2:], ["notchcast/ci-build.sh",
                         "FAIL footprint: v2/addons-zen touches 1 upstream paths"])
        for core in ("v2/addons-core", "v2/addons-core-8"):
            self.env["NOTCHCAST_READY_BRANCH"] = core
            self.assertNotIn("FAIL footprint", self.check("base").stdout, core)
        self.env["NOTCHCAST_READY_BRANCH"] = "v2/addons-core-8-land"
        self.assertIn("FAIL footprint", self.check("base").stdout)

    def test_the_delete_test_runs_only_when_addon_code_changes(self):
        self.commit("work", "work.txt")
        result = self.check("base")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("delete", result.stdout)
        (self.repo / "Tinycast/Features/Notchcast/Stub").mkdir(parents=True)
        self.commit("addon", "Tinycast/Features/Notchcast/Stub/Stub.swift")
        result = self.check("base")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        head = self.git("rev-parse", "HEAD")
        self.assertEqual(result.stdout.splitlines()[-2:],
                         [f"addon-delete: PASS delete Stub --rotate --ref {head}",
                          f"PASS {head[:12]} against base ({self.git('rev-parse', 'base')[:12]})"])

    def test_a_failing_delete_test_fails_the_check(self):
        (self.repo / "Tinycast/Features/Notchcast/Stub").mkdir(parents=True)
        self.commit("addon", "Tinycast/Features/Notchcast/Stub/Stub.swift")
        self.commit("breach", "delete-fail")
        result = self.check("base")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual(result.stdout.splitlines()[-2], f"FAIL delete Stub --rotate --ref {self.git('rev-parse', 'HEAD')}")
        self.assertRegex(result.stdout.splitlines()[-1], r"^FAIL addon-delete; log: ")

    def test_a_builders_branch_never_reaches_the_fixtures(self):
        with open(self.repo / "notchcast/check-drift.py", "a") as stub:
            stub.write("# stock edit\n")
        self.commit("stock edit")
        with mock.patch.dict(os.environ, NOTCHCAST_READY_BRANCH="v2/addons-zen"):
            self.env = fixture_env(self.env)
        result = self.check("base")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("FAIL footprint", result.stdout)

    def test_drift_gates_are_land_sh_own(self):
        script = SCRIPT.read_text()
        self.assertIn('git show "$BASE_SHA:notchcast/drift-gates.sh"', script)
        self.assertIn('run_drift_gates "$BASE_SHA"', script)
        self.assertIn('source "$merge_tools/drift-gates.sh"', (ROOT / "notchcast/merge.sh").read_text())

    def test_refuses_uncommitted_changes_and_unknown_bases(self):
        (self.repo / "notchcast/config.env").write_text("FORK_REPO=example/other\n")
        self.assertIn("FAIL setup: uncommitted", self.check("base").stderr)
        self.git("checkout", "--", ".")
        self.assertIn("FAIL setup: no commit nope", self.check("nope").stderr)


if __name__ == "__main__":
    unittest.main()
