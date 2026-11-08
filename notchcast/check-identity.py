#!/usr/bin/env python3
"""Inspect added lines, metadata and bundle strings; never print matched content."""
import argparse
import ast
import os
import re
import runpy
import subprocess
from pathlib import Path

PATTERNS = {
    "forbidden-name": re.compile(r"gains ?geek|gains?[ ._-]?geek|gainsgeek|gg-app|gg-kb|privatehq", re.I),
    "todoist-id": re.compile(r"(?<![a-z0-9])id:[a-z0-9]{16}(?![a-z0-9])|(?<![a-z0-9])6[a-z0-9]{15}(?![a-z0-9])", re.I),
    "t3-id": re.compile(r"mcp:launch:[a-f0-9]+|t3-thread://|run:thread:|(?<![a-z0-9-])t3-[a-f0-9]{8}(?![a-z0-9])", re.I),
}
ALLOW_FILES = {"notchcast/check-identity.py": "guard pattern definitions"}
HEAD = "HEAD"
EMAIL_POLICY = runpy.run_path(str(Path(__file__).with_name("check-commit-emails.py")))
ALLOWED = EMAIL_POLICY["ALLOWED"]


def git(*args):
    return subprocess.check_output(["git", *args]).decode("utf-8", errors="replace")


def redact(text):
    for kind, pattern in PATTERNS.items():
        text = pattern.sub(f"<{kind}>", text)
    return text


def inspect(text, location):
    failed = False
    for kind, pattern in PATTERNS.items():
        for match in pattern.finditer(text):
            token = match.group()
            if kind == "todoist-id" and not token.lower().startswith("id:"):
                if not (any(c.isupper() for c in token) and any(c.islower() for c in token)):
                    continue
            print(f"check-identity: {redact(location)}: <{kind}>")
            failed = True
            break
    return failed


def diff(base, staged=False):
    args = ["diff", "--no-ext-diff", "--no-textconv", "--unified=0", "--no-renames"]
    args += ["--cached"] if staged else [f"{base}..{HEAD}"]
    failed = False
    for path in filter(None, git(*args, "--name-only", "-z").split("\0")):
        if path in ALLOW_FILES:
            print(f"check-identity: allowed {path}: {ALLOW_FILES[path]}")
            continue
        failed |= inspect(path, "file name")
        line = None
        for text in git(*args, "--", path).split("\n"):
            if text.startswith("@@"):
                line = int(re.search(r"\+(\d+)", text)[1])
            elif line is not None and text.startswith("+"):
                failed |= inspect(text[1:], f"{path}:{line}")
                line += 1
            elif line is not None and text.startswith(" "):
                line += 1
    return failed


def metadata(base):
    failed = False
    for sha in git("rev-list", f"{base}..{HEAD}").splitlines():
        failed |= inspect(git("show", "-s", "--format=%an%n%ae%n%cn%n%ce%n%B", sha), sha[:12])
    return failed


def added_lines(base):
    failed = False
    path = None
    line = None
    patch = git("log", "-p", "--cherry-pick", "--right-only", "--format=", "--no-ext-diff", "--no-textconv",
                "--no-renames", "--unified=0", "--diff-merges=first-parent", f"{base}...{HEAD}")
    for text in patch.splitlines():
        if text.startswith("diff --git "):
            path = None
            line = None
        elif text.startswith("+++ b/") or text.startswith('+++ "b/'):
            path = text[4:]
            if path.startswith('"'):
                path = ast.literal_eval(path)
            path = path[2:]
            if path in ALLOW_FILES:
                path = None
        elif path is not None and text.startswith("@@"):
            line = int(re.search(r"\+(\d+)", text)[1])
        elif path is not None and line is not None and text.startswith("+"):
            failed |= inspect(text[1:], f"{path}:{line} (commit addition)")
            line += 1
    return failed


def annotated_tag(sha):
    content = git("cat-file", "-p", sha)
    failed = inspect(content, f"tag {sha[:12]}")
    tagger = re.search(r"^tagger .*<(.*)>", content, re.M)
    if tagger and tagger.group(1) not in ALLOWED:
        print(f"check-identity: tag {sha[:12]}: non-allowed tagger email")
        failed = True
    return failed


def app(bundle):
    root = Path(bundle)
    if not root.is_dir():
        raise ValueError("missing bundle")
    failed = False
    for path in sorted(root.rglob("*")):
        failed |= inspect(str(path.relative_to(root)), "file name")
        # CodeResources is base64 hashes, whose random runs match the id shapes.
        if path.is_file() and "_CodeSignature" not in path.parts:
            content = subprocess.check_output(["strings", "-a", str(path)]).decode("utf-8", errors="replace")
            failed |= inspect(content, str(path.relative_to(root)))
    return failed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["staged", "message", "history", "diff", "metadata", "app", "tag"])
    parser.add_argument("target", nargs="?")
    parser.add_argument("head", nargs="?", default="HEAD")
    args = parser.parse_args()
    if args.head != "HEAD":
        # Resolve the pushed ref without changing the caller's checkout.
        global HEAD
        HEAD = git("rev-parse", "--verify", args.head + "^{commit}").strip()
    base = args.target or "refs/remotes/upstream/main"
    if args.mode == "app":
        return app(base)
    if args.mode == "tag":
        return annotated_tag(base)
    if args.mode == "message":
        return inspect(Path(base).read_text(), "commit message")
    if args.mode == "staged":
        failed = diff(base, staged=True)
        for role in ("AUTHOR", "COMMITTER"):
            identity = git("var", f"GIT_{role}_IDENT")
            email = identity.rsplit("<", 1)[1].split(">", 1)[0]
            if email not in ALLOWED:
                print(f"check-identity: {role.lower()}: non-allowed email; "
                      "fix with git config user.email "
                      f"{EMAIL_POLICY['CONFIG']['MAINTAINER_EMAIL']}")
                failed = True
            failed |= inspect(identity, role.lower())
        return failed
    failed = False
    if args.mode in ("history", "diff"):
        failed |= diff(base)
        additions_base = "refs/remotes/origin/main"
        if pr_base := os.environ.get("GITHUB_BASE_REF"):
            additions_base = f"refs/remotes/origin/{pr_base}"
        failed |= added_lines(additions_base)
    if args.mode in ("history", "metadata"):
        failed |= metadata(base)
    return failed


if __name__ == "__main__":
    try:
        raise SystemExit(int(main()))
    except (OSError, ValueError, subprocess.CalledProcessError):
        print("check-identity: unable to complete scan")
        raise SystemExit(2)
