#!/usr/bin/env python3
"""Check our commit identities without exposing rejected addresses in diagnostics."""
import subprocess
import sys

ALLOWED = {
    "336236323+kaczordodgers@users.noreply.github.com",
    "noreply@github.com",  # GitHub web-flow squash committer.
    "41898282+github-actions[bot]@users.noreply.github.com",  # Sync replay.
}


# Old commits with a non-allowed author email, already public; rewriting history is the repo owner's decision. Do not add to this list.
OLD_COMMITS = {
    "4f199aad279ca9e68cb941a9788c81aefed50726",
    "1f17b82e60180905a66a099f1f6959ead5f30f74",
    "cd27a89bf8e7e0b76fdb4608093176b0a2539946",
    "7988d87c196c5a5e9e2b8bd38873b00a1dee2c6a",
    "0c3fe110e25e39a79994c46b2c7fd498174de044",
    "6b5dea3ee21a317ed9426a07c7e9c4644b35aca3",
    "283fd6eb8d0ccf2ebd4339409668f9aae1e28b7a",
    "a5eb9027251895bc09b8307192703f385e2051b6",
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
            if email not in ALLOWED and not (role == "author" and sha in OLD_COMMITS):
                print(f"{sha}: non-allowed {role} email")
                failures += 1
    print(f"Checked {len(commits)} commits; {failures} non-allowed identities")
    return bool(failures)


if __name__ == "__main__":
    sys.exit(main())
