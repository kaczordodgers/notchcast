#!/bin/bash
# publish-snapshot.sh against a local bare remote, with git and gh stubs that fail on cue.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
real_git=$(command -v git)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

# FAIL_PUSH=n: the first n pushes fail like a rejected deploy key (exit 128).
# LOST_PUSH=1: the first push lands on the remote but still reports exit 128.
# FAIL_CREATE=n: the first n release creates return 502; HALF_CREATE=1 leaves a draft with one asset behind,
# SILENT_CREATE=1 a published release. FAIL_VIEW_FROM=n: every release view after the first n returns 502.
mkdir "$work/bin"
cat > "$work/bin/git" <<EOF
#!/bin/bash
state=\$STUB_STATE
if [ "\$1" = push ]; then
    n=\$(cat "\$state/pushes" 2>/dev/null || echo 0); echo \$((n + 1)) > "\$state/pushes"
    if [ "\$n" -lt "\${FAIL_PUSH:-0}" ]; then echo "git@github.com: Permission denied (publickey)." >&2; exit 128; fi
    if [ "\${LOST_PUSH:-0}" = 1 ] && [ "\$n" = 0 ]; then "$real_git" "\$@" >/dev/null 2>&1; exit 128; fi
fi
exec "$real_git" "\$@"
EOF
cat > "$work/bin/gh" <<'EOF'
#!/bin/bash
state=$STUB_STATE
case "$1 $2" in
    "release view")
        n=$(cat "$state/views" 2>/dev/null || echo 0); echo $((n + 1)) > "$state/views"
        [ "$n" -ge "${FAIL_VIEW_FROM:-99}" ] && { echo "HTTP 502: Server Error" >&2; exit 1; }
        [ -f "$state/release" ] || { echo "release not found" >&2; exit 1; }
        cat "$state/release" ;;
    "release delete") rm -f "$state/release"; echo delete >> "$state/log" ;;
    "release create")
        [ -f "$state/release" ] && { echo "HTTP 422: Validation Failed (already_exists)" >&2; exit 1; }
        n=$(cat "$state/creates" 2>/dev/null || echo 0); echo $((n + 1)) > "$state/creates"
        if [ "$n" -lt "${FAIL_CREATE:-0}" ]; then
            [ "${HALF_CREATE:-0}" = 1 ] && echo "true 1" > "$state/release"
            [ "${SILENT_CREATE:-0}" = 1 ] && echo "false 2" > "$state/release"
            echo "HTTP 502: Server Error (https://api.github.com/repos/x/releases/1)" >&2; exit 1
        fi
        echo "false 2" > "$state/release"; echo "create $3" >> "$state/log" ;;
    *) echo "unexpected gh $*" >&2; exit 2 ;;
esac
EOF
chmod +x "$work/bin/git" "$work/bin/gh"

check() {
    local name=$1 want_rc=$2 want_tag=$3 want_release=$4
    shift 4
    local case="$work/$name" rc
    mkdir -p "$case/state" "$case/dist"
    "$real_git" init -q --bare "$case/remote.git"
    "$real_git" init -q "$case/repo"
    "$real_git" -C "$case/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m one
    "$real_git" -C "$case/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m two
    local main other
    main=$("$real_git" -C "$case/repo" rev-parse HEAD)
    other=$("$real_git" -C "$case/repo" rev-parse HEAD~1)
    [ "${PRESET:-}" = other ] && "$real_git" -C "$case/repo" push -q "$case/remote.git" "$other:refs/tags/v1.snapshot.1"
    [ "${PRESET:-}" = main ] && "$real_git" -C "$case/repo" tag -a pre "$main" -m pre && "$real_git" -C "$case/repo" push -q "$case/remote.git" "refs/tags/pre:refs/tags/v1.snapshot.1"
    echo zip > "$case/dist/Notchcast-1.snapshot.1.zip"
    echo dmg > "$case/dist/Notchcast-1.snapshot.1.dmg"
    (cd "$case/repo" && env PATH="$work/bin:$PATH" STUB_STATE="$case/state" PUBLISH_PAUSE=0 \
        TAG=v1.snapshot.1 MAIN="$main" VERSION=1.snapshot.1 GITHUB_REPOSITORY=x/y DIST="$case/dist" \
        REMOTE="$case/remote.git" "$@" "$here/publish-snapshot.sh") > "$case/out" 2>&1
    rc=$?
    local tag release
    tag=$("$real_git" -C "$case/remote.git" rev-parse -q --verify "refs/tags/v1.snapshot.1^{commit}" || echo none)
    [ "$tag" = "$main" ] && tag=main
    [ "$tag" = "$other" ] && tag=other
    release=$(cat "$case/state/release" 2>/dev/null || echo none)
    if [ "$rc" = "$want_rc" ] && [ "$tag" = "$want_tag" ] && [ "$release" = "$want_release" ]; then
        echo "ok    $name (exit $rc, tag $tag, release $release)"
    else
        echo "FAIL  $name: exit $rc tag $tag release '$release'; wanted exit $want_rc tag $want_tag release '$want_release'"
        sed 's/^/      /' "$case/out"
        failures=$((failures + 1))
    fi
}

check clean 0 main "false 2" env
check push-128-twice 0 main "false 2" env FAIL_PUSH=2
check push-landed-but-128 0 main "false 2" env LOST_PUSH=1
check release-502-twice 0 main "false 2" env FAIL_CREATE=2
check release-502-leaves-draft 0 main "false 2" env FAIL_CREATE=2 HALF_CREATE=1
PRESET=main check rerun-reuses-tag 0 main "false 2" env
check push-always-128 1 none none env FAIL_PUSH=9
check release-always-502-removes-tag 1 none none env FAIL_CREATE=9
check published-despite-502-then-api-down 1 main "false 2" env FAIL_CREATE=1 SILENT_CREATE=1 FAIL_VIEW_FROM=1
PRESET=other check tag-on-other-commit-untouched 1 other none env
grep -q '^delete$' "$work/release-502-leaves-draft/state/log" || { echo "FAIL  half-made release was not deleted first"; failures=$((failures + 1)); }
[ "$(cat "$work/release-502-twice/state/creates")" = 3 ] || { echo "FAIL  release-502-twice did not create 3 times"; failures=$((failures + 1)); }
[ "$failures" -eq 0 ] && echo "PASS: publish-snapshot.sh retries, reuses and cleans up" || { echo "FAILED: $failures"; exit 1; }
