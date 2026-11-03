#!/usr/bin/env python3
"""Check our commit identities without exposing rejected addresses in diagnostics."""
import subprocess
import sys

ALLOWED = {
    "336236323+kaczordodgers@users.noreply.github.com",
    "noreply@github.com",  # GitHub web-flow squash committer.
    "41898282+github-actions[bot]@users.noreply.github.com",  # Sync replay.
}


def main():
    revision = sys.argv[1] if len(sys.argv) > 1 else "refs/remotes/upstream/main..HEAD"
    commits = subprocess.run(
        ["git", "log", "--format=%H %ae %ce", revision],
        text=True, capture_output=True, check=True,
    ).stdout.splitlines()
    failures = 0
    for commit in commits:
        sha, author, committer = commit.split(" ")
        for role, email in (("author", author), ("committer", committer)):
            if email not in ALLOWED:
                print(f"{sha}: non-allowed {role} email")
                failures += 1
    print(f"Checked {len(commits)} commits; {failures} non-allowed identities")
    return bool(failures)


if __name__ == "__main__":
    sys.exit(main())
