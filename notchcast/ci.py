#!/usr/bin/env python3
"""Notchcast CI helper, run by .github/workflows/sync.yml.

    ci.py plan                              decide what this run builds (conflicts are found here, on Linux)
    ci.py replay <tree> <onto>              in <tree> (our main, upstream fetched), replay our commits onto <onto>
    ci.py regenerate <tree> <onto>          rewrite the generated files in <tree> (no commit)
    ci.py app-info <tag> <dir>              name, bundle id, version and build of upstream's release zip
    ci.py issue open <kind> <title> <cause> [<details.md>] | issue close <kind>
    ci.py design-notice <tree> <old upstream> <new upstream>

Our commits are merge-base(main, upstream main)..main. Replaying cherry-picks them in order without the GENERATED
files, so those never conflict and never travel in our diffs. Two commits are made afresh instead of picked:
"Notchcast: remove upstream workflows" (git rm -r .github/workflows), so upstream workflow edits never conflict and
new ones never land, and "Notchcast: generated files", always last, which rewrites GENERATED (`regenerate`).
Catalog conflicts merge by key; other conflicts use per-file diffs from the replay tip in main's
replay-fixes/<lowercase subject, non-alphanumerics hyphenated>[.<base label>].patch (the first that applies) or fail.
Failures are remembered as refs/notchcast-failed/<main|release-<tag>>-<upstream or tag>-<our main>, so the same
input is retried only when upstream or our main changes, and reported as one open issue per kind (label
notchcast-<kind>: sync = replay onto new upstream, main = main tested as it is, release), which a newer failure with
the same cause only retitles; notchcast/update.sh reports each issue and cause once through its notify hook.
"""
import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REMOVE_WORKFLOWS = "Notchcast: remove upstream workflows"
GENERATED_COMMIT = "Notchcast: generated files"
PBXPROJ = "Tinycast.xcodeproj/project.pbxproj"
RUNTIME_JS = "Tinycast/Resources/RaycastRuntime.generated.js"
# Rewritten by `regenerate`, never taken from our commits.
GENERATED = [PBXPROJ, RUNTIME_JS, "README.md"]
# Never pruned (notchcast/prune-paths.txt); docs/*.md is kept too.
KEEP = ["LICENSE", "NOTICE.md", "AGENTS.md", "Tests", "Scripts/raycast-runtime"]
# Upstream changes here mean notchcast/docs/design-system.md may need a refresh.
DESIGN_PATHS = ["Tinycast/DesignSystem/", ":(glob)**/Theme.swift", "docs/ui.md"]
BOT = {
    "GIT_COMMITTER_NAME": "github-actions[bot]",
    "GIT_COMMITTER_EMAIL": "41898282+github-actions[bot]@users.noreply.github.com",
}
TAG_RE = re.compile(r"v(\d+)\.(\d+)\.(\d+)(?:-[a-z]+\.(\d+))?")


def config():
    values = {}
    for line in (HERE / "config.env").read_text().splitlines():
        if line.strip() and not line.startswith("#"):
            key, _, value = line.partition("=")
            values[key] = value.strip().strip('"')
    return values


AUTHOR = "{MAINTAINER_NAME} <{MAINTAINER_EMAIL}>".format(**config())


def run(*cmd, cwd=None, env=None):
    return subprocess.run(cmd, cwd=cwd, env=dict(os.environ, **(env or {})), text=True,
                          check=True, capture_output=True).stdout.strip()


def ls_remote(url, *patterns):
    refs = {}
    for line in run("git", "ls-remote", url, *patterns).splitlines():
        sha, ref = line.split("\t")
        refs[ref] = sha
    return refs


def version_key(tag):
    """v0.12.6-beta.130 -> ((0, 12, 6), 0, 130); a stable release sorts after its betas; None if unparsable."""
    m = TAG_RE.fullmatch(tag)
    if not m:
        return None
    nums = tuple(int(x) for x in m.group(1, 2, 3))
    return (nums, 1, 0) if m.group(4) is None else (nums, 0, int(m.group(4)))


def output(**values):
    with open(os.environ["GITHUB_OUTPUT"], "a") as out:
        for key, value in values.items():
            out.write(f"{key}={value}\n")
            print(f"{key}={value}")


def release_tags(repo):
    pages = json.loads(run("gh", "api", "--paginate", "--slurp", f"repos/{repo}/releases?per_page=100"))
    return {r["tag_name"] for page in pages for r in page}


def rebase_hold(prs, moved_at, now):
    numbers = sorted(pr["number"] for pr in prs if not pr["isDraft"] and not pr["isCrossRepository"])
    if not numbers:
        return False, ""
    names = ", ".join(f"#{number}" for number in numbers)
    left = 12 - (now - moved_at) / 3600
    if left > 0:
        return True, f"open PRs {names}; {left:.1f} h of 12 left"
    return False, f"::warning::main: 12-hour hold expired with PRs {names} still open"


def plan():
    """Run in a checkout of our main with history (fetch-depth 0)."""
    cfg = config()
    upstream = f"https://github.com/{cfg['UPSTREAM_REPO']}.git"
    main = run("git", "rev-parse", "HEAD")
    run("git", "fetch", "-q", upstream, "refs/heads/main")
    upstream_main = run("git", "rev-parse", "FETCH_HEAD")
    base = run("git", "merge-base", main, upstream_main)
    upstream_tags = {r.removeprefix("refs/tags/") for r in ls_remote(upstream, "refs/tags/*") if not r.endswith("^{}")}
    failed = {r.removeprefix("refs/notchcast-failed/")
              for r in ls_remote(f"https://github.com/{cfg['FORK_REPO']}.git", "refs/notchcast-failed/*")}

    main_key = f"main-{upstream_main}-{main}"
    rebase = base != upstream_main
    held = False
    if rebase:
        prs = json.loads(run("gh", "pr", "list", "-R", cfg["FORK_REPO"], "--base", "main", "--state", "open", "--limit", "1000",
                             "--json", "number,isDraft,isCrossRepository"))
        moved_at = int(run("git", "log", "--first-parent", "--reverse", "--format=%ct", f"{base}..{upstream_main}").splitlines()[0])
        held, message = rebase_hold(prs, moved_at, time.time())
        if message:
            print(f"main: hold rebase onto upstream {upstream_main[:10]}: {message}" if held else message)
    if not rebase:
        print(f"main: contains upstream {upstream_main[:10]}")
    elif held:
        rebase = False
    elif main_key in failed:
        print(f"main: {main_key} already failed; waiting for upstream or main to change")
        rebase = False
    else:
        print(f"main: rebase {main[:10]} onto upstream {upstream_main[:10]}")
        # The replay alone, here on Linux, before a macOS runner is spent on it.
        run("git", "update-ref", "refs/remotes/upstream/main", upstream_main)
        with tempfile.TemporaryDirectory() as tree:
            run("git", "worktree", "add", "-q", "--detach", tree, main)
            try:
                replay(tree, upstream_main, check=True)
            except Conflict as conflict:
                rebase = False
                details = Path(tempfile.mkstemp(suffix=".md")[1])
                details.write_text(conflict.report(tree, base, upstream_main, cfg["UPSTREAM_REPO"]))
                issue_open("sync", f"Sync blocked: upstream {upstream_main[:7]} + main {main[:7]}", conflict.cause,
                           details)
                print(f"::warning::{conflict.cause} (see the notchcast-sync issue)")
            finally:
                run("git", "worktree", "remove", "--force", tree)

    ours = release_tags(cfg["FORK_REPO"])
    theirs = json.loads(run("gh", "release", "list", "-R", cfg["UPSTREAM_REPO"], "-L", "30",
                            "--json", "tagName,name,isDraft,isPrerelease"))
    baseline = version_key(cfg["BASELINE_TAG"])
    releases = []
    for r in sorted((r for r in theirs if version_key(r["tagName"])), key=lambda r: version_key(r["tagName"])):
        tag = r["tagName"]
        if r["isDraft"] or tag in ours or tag not in upstream_tags or version_key(tag) < baseline:
            continue
        if f"release-{tag}-{main}" in failed:
            print(f"release {tag}: already failed with this main; skipped")
            continue
        print(f"release {tag}: mirror")
        releases.append({"tag": tag, "title": r["name"], "prerelease": r["isPrerelease"]})

    statuses = json.loads(run("gh", "api", f"repos/{cfg['FORK_REPO']}/commits/{main}/status"))["statuses"]
    tested = any(s["context"] == cfg["TESTED_CONTEXT"] and s["state"] == "success" for s in statuses)
    # Without a rebase, a main commit is tested as it is, once: a red one waits for a new main.
    test_main = not rebase and not tested and f"test-{main}" not in failed
    print(f"main {main[:10]}: {'tested' if tested else 'failed before' if not test_main and not rebase else 'not tested yet'}")
    output(rebase=str(rebase).lower(), test_main=str(test_main).lower(), main=main, base=base,
           upstream_main=upstream_main, main_key=main_key, releases=json.dumps(releases, separators=(",", ":")))


class Conflict(Exception):
    def __init__(self, subject, files):
        super().__init__(f"{subject}: {' '.join(files)}")
        self.subject, self.files = subject, files
        # Stable across upstream commits, so a newer upstream stopping on the same thing only retitles the issue.
        self.cause = f"{subject}: {' '.join(files)}"

    def report(self, tree, base, upstream, upstream_repo):
        """The upstream commits since our base that touched the conflicting files: usually the one to look at."""
        url = f"https://github.com/{upstream_repo}/commit"
        touched = run("git", "log", f"--format=- [`%h`]({url}/%H) %s", f"{base}..{upstream}", "--", *self.files,
                      cwd=tree)
        files = ", ".join(f"`{f}`" for f in self.files)
        return (f"**{self.subject}** no longer applies to upstream [`{upstream[:7]}`]({url}/{upstream}): {files}.\n\n"
                + (f"Upstream commits since [`{base[:7]}`]({url}/{base}) that touch them:\n\n{touched}\n\n"
                   "If one of them ships what our commit does, drop our commit; otherwise redo it on top.\n"
                   if touched else "No upstream commit touched them, so an earlier commit of ours moved the lines.\n"))


def replay_fixes(tree, main, name):
    """main's stored fixes for one commit: <name>.patch, then <name>.<base label>.patch for older release bases."""
    listed = run("git", "ls-tree", "--name-only", main, "notchcast/replay-fixes/", cwd=tree).splitlines()
    bare = f"notchcast/replay-fixes/{name}.patch"
    return ([bare] if bare in listed else []) + sorted(
        path for path in listed
        if path.startswith(bare.removesuffix("patch")) and path.endswith(".patch") and path != bare)


def replay(tree, onto, check=False):
    """Replay merge-base(HEAD, upstream main)..HEAD onto `onto` in tree; leaves tree detached at the result.
    With check=True (plan, on Linux) the generated files are not regenerated. Raises Conflict."""
    main = run("git", "rev-parse", "HEAD", cwd=tree)
    upstream_main = run("git", "rev-parse", "refs/remotes/upstream/main", cwd=tree)
    base = run("git", "merge-base", main, upstream_main, cwd=tree)
    commits = run("git", "rev-list", "--reverse", "--topo-order", f"{base}..{main}", cwd=tree).split()
    merges = run("git", "rev-list", "--merges", f"{base}..{main}", cwd=tree)
    if merges:
        sys.exit(f"main has merge commits ({merges.split()[0][:10]}…); keep main linear")
    run("git", "checkout", "-q", "--detach", onto, cwd=tree)
    generated_commit = None
    for sha in commits:
        subject = run("git", "show", "-s", "--format=%s", sha, cwd=tree)
        print(f"replay {sha[:10]} {subject}", flush=True)
        if subject == GENERATED_COMMIT:
            generated_commit = sha
            continue
        if subject == REMOVE_WORKFLOWS:
            run("git", "rm", "-r", "-q", "--ignore-unmatch", ".github/workflows", cwd=tree)
        else:
            picked = subprocess.run(["git", "cherry-pick", "--no-commit", sha], cwd=tree, text=True,
                                    capture_output=True)
            conflicts = run("git", "diff", "--name-only", "--diff-filter=U", cwd=tree).split()
            catalog = "Tinycast/Resources/Localizable.xcstrings"
            resolved_catalog = False
            catalog_refs = (sha + "^", "HEAD", sha)
            if catalog in conflicts and all(
                    subprocess.run(["git", "cat-file", "-e", f"{ref}:{catalog}"], cwd=tree,
                                   stderr=subprocess.DEVNULL).returncode == 0 for ref in catalog_refs):
                with tempfile.TemporaryDirectory() as directory:
                    inputs = []
                    for index, ref in enumerate(catalog_refs):
                        path = Path(directory) / str(index)
                        path.write_text(run("git", "show", f"{ref}:{catalog}", cwd=tree) + "\n")
                        inputs.append(str(path))
                    merged = subprocess.run(
                        [sys.executable, str(HERE / "xcstrings-union.py"), *inputs,
                         str(Path(tree).resolve() / catalog)], text=True, capture_output=True)
                if merged.returncode == 0:
                    run("git", "add", "--", catalog, cwd=tree)
                    conflicts.remove(catalog)
                    resolved_catalog = True
            if (picked.returncode and not conflicts and not resolved_catalog
                    or set(conflicts) - set(GENERATED)):
                name = re.sub(r"[^a-z0-9]+", "-", subject.lower()).strip("-")
                applied = None
                expected = set(conflicts) - set(GENERATED) - {catalog}
                for fix in replay_fixes(tree, main, name):
                    patch = subprocess.run(["git", "show", f"{main}:{fix}"], cwd=tree, text=True,
                                           capture_output=True, check=True).stdout
                    paths = subprocess.run(["git", "apply", "--numstat", "-z", "-"], input=patch,
                                           cwd=tree, text=True, capture_output=True)
                    covered = {entry.split("\t", 2)[2] for entry in paths.stdout.split("\0") if entry}
                    if not expected or paths.returncode or covered != expected:
                        continue
                    for path in expected:
                        if subprocess.run(["git", "cat-file", "-e", f"HEAD:{path}"], cwd=tree,
                                          stderr=subprocess.DEVNULL).returncode == 0:
                            run("git", "checkout", "HEAD", "--", path, cwd=tree)
                        else:
                            run("git", "rm", "-q", "-f", "--ignore-unmatch", "--", path, cwd=tree)
                    # git apply is all-or-nothing, so a fix for another base leaves the tree for the next one.
                    applied = subprocess.run(["git", "apply", "--index", "-"], input=patch,
                                             cwd=tree, text=True, capture_output=True)
                    if applied.returncode == 0:
                        break
                remaining = run("git", "diff", "--name-only", "--diff-filter=U", cwd=tree).split()
                if applied is None or applied.returncode or set(remaining) - set(GENERATED):
                    run("git", "reset", "-q", "--hard", cwd=tree)
                    raise Conflict(subject, [f for f in conflicts if f not in GENERATED]
                                   or [(picked.stderr.strip().splitlines() or ["cherry-pick failed"])[0]])
            # Generated files stay as they were; the generated-files commit rewrites them.
            for path in GENERATED:
                if subprocess.run(["git", "cat-file", "-e", f"HEAD:{path}"], cwd=tree, stderr=subprocess.DEVNULL).returncode == 0:
                    run("git", "checkout", "HEAD", "--", path, cwd=tree)
                else:
                    run("git", "rm", "-q", "-f", "--ignore-unmatch", "--", path, cwd=tree)
        run("git", "commit", "-q", "--no-verify", "--allow-empty", "-C", sha, "--author", AUTHOR, cwd=tree, env=BOT)
    if not check:
        regenerate(tree, onto)
        run("git", "add", "-A", "--", *GENERATED, cwd=tree)
        message = ["-C", generated_commit] if generated_commit else ["-m", GENERATED_COMMIT]
        run("git", "commit", "-q", "--no-verify", "--allow-empty", *message, "--author", AUTHOR, cwd=tree, env=BOT)
    print(run("git", "log", "--format=%h %an | %cn | %s", f"{onto}..HEAD", cwd=tree))


def pruned(tree):
    """Paths in notchcast/prune-paths.txt. None may cover a kept path (license notices, agent and feature docs,
    harnesses, the extension runtime sources)."""
    prune = Path(tree) / "notchcast/prune-paths.txt"
    paths = [line.strip() for line in prune.read_text().splitlines()] if prune.exists() else []
    paths = [path for path in paths if path and not path.startswith("#")]
    for path in paths:
        bare = path.rstrip("/")
        if any(keep == bare or keep.startswith(bare + "/") or bare.startswith(keep + "/") for keep in KEEP) \
                or bare in ("", ".", "docs") or bare.startswith("docs/") and (
                    bare.endswith(".md") or path.endswith("/") or (Path(tree) / bare).is_dir()):
            sys.exit(f"notchcast/prune-paths.txt: {path} covers a path Notchcast keeps")
    return paths


def regenerate(tree, onto):
    """Write GENERATED in tree: notchcast/README.public.md as README.md, the Xcode project from project.yml ($XCODEGEN), and the
    extension runtime bundle when our commits change its sources. Also stage the removal of every path in
    notchcast/prune-paths.txt (upstream files the app does not need), so the removal rides in the generated-files
    commit, which a replay never picks and so never conflicts."""
    tree = Path(tree)
    paths = pruned(tree)
    if paths:
        run("git", "rm", "-r", "-q", "--ignore-unmatch", "--", *paths, cwd=tree)
    (tree / "README.md").write_text((tree / "notchcast/README.public.md").read_text())
    if os.environ.get("XCODEGEN"):
        run(os.environ["XCODEGEN"], "generate", "--quiet", cwd=tree)
    elif subprocess.run(["git", "diff", "--quiet", onto, "HEAD", "--", "project.yml"], cwd=tree).returncode:
        sys.exit("our commits change project.yml; set XCODEGEN to regenerate the project")
    runtime = tree / "Scripts/raycast-runtime"
    if subprocess.run(["git", "diff", "--quiet", onto, "HEAD", "--", str(runtime)], cwd=tree).returncode:
        run("npm", "ci", "--no-audit", "--no-fund", cwd=runtime)
        run("node", "build.mjs", cwd=runtime)


def issue_open(kind, title, cause, details=None):
    """One open issue per kind. The same cause on a newer input only retitles it, so it notifies once."""
    repo, label = os.environ["GITHUB_REPOSITORY"], f"notchcast-{kind}"
    run_url = f"{os.environ['GITHUB_SERVER_URL']}/{repo}/actions/runs/{os.environ['GITHUB_RUN_ID']}"
    marker = f"<!-- cause: {cause} -->"
    body = (f"{title}: see [the run]({run_url}). Nothing was pushed or published; it is retried when upstream or "
            f"`main` changes.\n\n" + (Path(details).read_text() + "\n" if details else "") + marker)
    run("gh", "label", "create", label, "-R", repo, "--color", "d93f0b", "--force")
    found = json.loads(run("gh", "issue", "list", "-R", repo, "--label", label, "--state", "open",
                           "--json", "number,title,body"))
    if not found:
        print(run("gh", "issue", "create", "-R", repo, "--label", label, "--title", title, "--body", body))
    elif marker in found[0]["body"]:
        if found[0]["title"] != title:
            run("gh", "issue", "edit", str(found[0]["number"]), "-R", repo, "--title", title)
    else:
        run("gh", "issue", "edit", str(found[0]["number"]), "-R", repo, "--title", title, "--body", body)
        run("gh", "issue", "comment", str(found[0]["number"]), "-R", repo, "--body", body)


def issue_close(kind, cause=None):
    """Close the open issue of kind; with a cause, only if it is that cause's."""
    repo = os.environ["GITHUB_REPOSITORY"]
    run_url = f"{os.environ['GITHUB_SERVER_URL']}/{repo}/actions/runs/{os.environ['GITHUB_RUN_ID']}"
    for found in json.loads(run("gh", "issue", "list", "-R", repo, "--label", f"notchcast-{kind}", "--state", "open",
                                "--json", "number,body")):
        if cause is None or f"<!-- cause: {cause} -->" in found["body"]:
            run("gh", "issue", "close", str(found["number"]), "-R", repo, "--comment",
                f"Went through in [this run]({run_url}).")


def issue(action, kind, *args):
    issue_open(kind, *args) if action == "open" else issue_close(kind, *args)


def design_notice(tree, old, new):
    """One notchcast-design issue per sync that brings upstream design-system changes; update.sh turns it into a
    private task and closes it."""
    cfg = config()
    url = f"https://github.com/{cfg['UPSTREAM_REPO']}/commit"
    commits = run("git", "log", f"--format=- [`%h`]({url}/%H) %s", f"{old}..{new}", "--", *DESIGN_PATHS, cwd=tree)
    if not commits:
        return
    repo = os.environ["GITHUB_REPOSITORY"]
    run("gh", "label", "create", "notchcast-design", "-R", repo, "--color", "1d76db", "--force")
    print(run("gh", "issue", "create", "-R", repo, "--label", "notchcast-design",
              "--title", f"Refresh notchcast/docs/design-system.md (upstream {new[:7]})",
              "--body", f"Upstream commits from `{old[:7]}` to `{new[:7]}` that touch the design system:\n\n{commits}\n"))


def app_info(tag, out_dir):
    """Name, bundle id, version and build from upstream's own thin zip, so our build matches it."""
    cfg = config()
    with tempfile.TemporaryDirectory() as tmp:
        run("gh", "release", "download", tag, "-R", cfg["UPSTREAM_REPO"], "-D", tmp, "-p", "Tinycast-[0-9]*.zip")
        zips = [z for z in Path(tmp).glob("Tinycast-*.zip") if "-Universal-" not in z.name]
        if len(zips) != 1:
            sys.exit(f"expected one thin zip in upstream {tag}, found {[z.name for z in zips]}")
        listing = run("zipinfo", "-1", str(zips[0])).splitlines()
        plist_path = next(l for l in listing if l.count("/") == 2 and l.endswith(".app/Contents/Info.plist"))
        info = plistlib.loads(subprocess.run(["unzip", "-p", str(zips[0]), plist_path],
                                             capture_output=True, check=True).stdout)
    version = info["CFBundleShortVersionString"]
    if f"v{version}" != tag:
        sys.exit(f"upstream zip says version {version}, tag is {tag}")
    body = json.loads(run("gh", "release", "view", tag, "-R", cfg["UPSTREAM_REPO"], "--json", "body"))["body"]
    Path(out_dir, "upstream-notes.md").write_text(body)
    output(name=info["CFBundleName"], bundle_id=info["CFBundleIdentifier"], version=version,
           build=info["CFBundleVersion"])


if __name__ == "__main__":
    command, args = sys.argv[1], sys.argv[2:]
    {"plan": plan, "replay": replay, "regenerate": regenerate, "app-info": app_info, "issue": issue,
     "design-notice": design_notice}[command](*args)
