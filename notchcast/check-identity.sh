#!/bin/bash
# Fail when a tracked file, a commit message or an author/committer identity names the employer domain this fork must
# never mention. Usage: check-identity.sh staged (pre-commit: index + the identity about to commit)
#   | message <file> (commit-msg) | history [<base>] (CI: HEAD's tree, and identities and messages of <base>..HEAD, default all)
set -uo pipefail
PATTERN='gain[s][ ._-]?geek'
status=0
hit() { echo "check-identity: $1" >&2; status=1; }

case "${1:-}" in
    staged)
        git grep --cached -n -I -i -E "$PATTERN" -- . && hit "staged files above"
        git var GIT_AUTHOR_IDENT | grep -i -q -E "$PATTERN" && hit "author identity; set: git config user.email <noreply address>"
        git var GIT_COMMITTER_IDENT | grep -i -q -E "$PATTERN" && hit "committer identity; set: git config user.email <noreply address>"
        ;;
    message)
        grep -n -i -E "$PATTERN" "$2" && hit "commit message above"
        ;;
    history)
        range="${2:+$2..}HEAD"
        git grep -n -I -i -E "$PATTERN" HEAD -- . && hit "tracked files above"
        git log --format='%h %an <%ae> %cn <%ce>' "$range" | grep -i -E "$PATTERN" && hit "commit identities above"
        git log --format='%h %B' "$range" | grep -i -E "$PATTERN" && hit "commit messages above"
        ;;
    *) echo "usage: $0 staged | message <file> | history [<base>]" >&2; exit 2 ;;
esac
exit $status
