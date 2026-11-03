#!/usr/bin/env python3
"""Notchcast CI helper, run by .github/workflows/sync.yml.

    ci.py plan                    decide what this run builds; writes job outputs
    ci.py replay <tree> <onto>    in <tree> (a checkout of our main with upstream fetched), replay our commits onto <onto>
    ci.py app-info <tag> <dir>    name, bundle id, version and build of upstream's release zip

Our commits are merge-base(main, upstream main)..main. Replaying cherry-picks them in order, except the commit
"Notchcast: remove upstream workflows", which is made afresh (git rm -r .github/workflows) so an upstream workflow
edit never conflicts and a new upstream workflow never lands. A conflict in the generated project alone is resolved by
regenerating it with $XCODEGEN. Any other conflict fails the run; nothing is pushed.
Failures are remembered as refs/notchcast-failed/<main|release-<tag>>-<upstream or tag>-<our main>, so the same
input is retried only when upstream or our main changes.
"""
import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REMOVE_WORKFLOWS = "Notchcast: remove upstream workflows"
PBXPROJ = "Tinycast.xcodeproj/project.pbxproj"
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
    if not rebase:
        print(f"main: contains upstream {upstream_main[:10]}")
    elif main_key in failed:
        print(f"main: {main_key} already failed; waiting for upstream or main to change")
    else:
        print(f"main: rebase {main[:10]} onto upstream {upstream_main[:10]}")

    ours = {r["tagName"] for r in json.loads(run(
        "gh", "release", "list", "-R", cfg["FORK_REPO"], "-L", "100", "--json", "tagName"))}
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
    tested = any(s["context"] == "notchcast/tested" and s["state"] == "success" for s in statuses)
    print(f"main {main[:10]}: {'tested' if tested else 'not tested yet'}")
    output(rebase="true" if rebase and main_key not in failed else "false", tested=str(tested).lower(), main=main,
           upstream_main=upstream_main, main_key=main_key, releases=json.dumps(releases, separators=(",", ":")))


def replay(tree, onto):
    """Replay merge-base(HEAD, upstream main)..HEAD onto `onto` in tree; leaves tree detached at the result."""
    main = run("git", "rev-parse", "HEAD", cwd=tree)
    upstream_main = run("git", "rev-parse", "refs/remotes/upstream/main", cwd=tree)
    base = run("git", "merge-base", main, upstream_main, cwd=tree)
    commits = run("git", "rev-list", "--reverse", "--topo-order", f"{base}..{main}", cwd=tree).split()
    merges = run("git", "rev-list", "--merges", f"{base}..{main}", cwd=tree)
    if merges:
        sys.exit(f"main has merge commits ({merges.split()[0][:10]}…); keep main linear")
    run("git", "checkout", "-q", "--detach", onto, cwd=tree)
    for sha in commits:
        subject = run("git", "show", "-s", "--format=%s", sha, cwd=tree)
        print(f"replay {sha[:10]} {subject}", flush=True)
        if subject == REMOVE_WORKFLOWS:
            run("git", "rm", "-r", "-q", "--ignore-unmatch", ".github/workflows", cwd=tree)
            run("git", "commit", "-q", "--allow-empty", "-C", sha, cwd=tree, env=BOT)
            continue
        picked = subprocess.run(["git", "cherry-pick", "--allow-empty", "--keep-redundant-commits", sha],
                                cwd=tree, env=dict(os.environ, **BOT), text=True, capture_output=True)
        if picked.returncode:
            conflicts = run("git", "diff", "--name-only", "--diff-filter=U", cwd=tree).split()
            if conflicts == [PBXPROJ] and os.environ.get("XCODEGEN"):
                # The project is generated from project.yml: regenerate it rather than merge it.
                print(f"  {PBXPROJ} conflicts; regenerating it from project.yml", flush=True)
                run(os.environ["XCODEGEN"], "generate", "--quiet", cwd=tree)
                run("git", "add", PBXPROJ, cwd=tree)
                run("git", "-c", "core.editor=true", "cherry-pick", "--continue", cwd=tree, env=BOT)
                continue
            subprocess.run(["git", "cherry-pick", "--abort"], cwd=tree, capture_output=True)
            sys.exit(f"{sha[:10]} {subject!r} does not apply on {onto[:10]}:\n"
                     f"{' '.join(conflicts) or picked.stdout + picked.stderr}")
    print(run("git", "log", "--format=%h %an | %cn | %s", f"{onto}..HEAD", cwd=tree))


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
    {"plan": plan, "replay": replay, "app-info": app_info}[command](*args)
