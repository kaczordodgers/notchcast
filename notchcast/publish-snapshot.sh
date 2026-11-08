#!/bin/bash
# Tag MAIN as TAG and publish DIST's zip and dmg as a prerelease, with bounded retries.
# Safe to rerun: a tag already on MAIN is reused, and a half-made release is replaced.
# If publishing still fails, the tag it pushed is removed so no stray tag stays behind.
set -uo pipefail
: "${TAG:?}" "${MAIN:?}" "${VERSION:?}" "${GITHUB_REPOSITORY:?}" "${DIST:?}"
source "$(dirname "$0")/config.env"
REMOTE=${REMOTE:-git@github.com:$GITHUB_REPOSITORY.git}
TRIES=${PUBLISH_TRIES:-5}
PAUSE=${PUBLISH_PAUSE:-20}
ASSETS=("$DIST/$APP_NAME-$VERSION.zip" "$DIST/$APP_NAME-$VERSION.dmg")
NOTES=$(mktemp)
printf 'Notchcast snapshot of main %s. Signed arm64 build.\n' "$MAIN" > "$NOTES"
for asset in "${ASSETS[@]}"; do
    [ -s "$asset" ] || { echo "::error::missing $asset"; exit 1; }
done

retry() {
    local what=$1 attempt
    shift
    for ((attempt = 1; ; attempt++)); do
        "$@" && return 0
        [ "$attempt" -lt "$TRIES" ] || { echo "::error::$what failed $TRIES times"; return 1; }
        echo "::warning::$what failed (try $attempt of $TRIES); retrying in $((PAUSE * attempt))s"
        sleep $((PAUSE * attempt))
    done
}

pushed=0
push_tag() {
    local listed
    listed=$(git ls-remote "$REMOTE" "refs/tags/$TAG" "refs/tags/$TAG^{}") || return 1
    if [ -n "$listed" ]; then
        if [ "$(awk '/\^\{\}$/ { print $1 }' <<< "$listed")" = "$MAIN" ]; then
            echo "Tag $TAG is already on ${MAIN:0:8}"
            pushed=1
            return 0
        fi
        echo "::error::$TAG already exists on another commit; not touching it"
        exit 1
    fi
    git push "$REMOTE" "refs/tags/$TAG" && pushed=1
}

# Prints "<isDraft> <uploaded assets>", or "none"; fails on any other error, such as a 5xx.
release_state() {
    local out
    if out=$(gh release view "$TAG" -R "$GITHUB_REPOSITORY" --json isDraft,assets \
        --jq '"\(.isDraft) \([.assets[] | select(.state == "uploaded")] | length)"' 2>&1); then
        echo "$out"
    elif grep -q 'release not found' <<< "$out"; then
        echo none
    else
        echo "$out" >&2
        return 1
    fi
}

publish() {
    local state
    state=$(release_state) || return 1
    [ "$state" = none ] || {
        if [ "$state" = "false ${#ASSETS[@]}" ]; then
            echo "Release $TAG is already published"
            return 0
        fi
        echo "Replacing the half-made release $TAG ($state)"
        gh release delete "$TAG" -R "$GITHUB_REPOSITORY" --yes || return 1
    }
    gh release create "$TAG" "${ASSETS[@]}" -R "$GITHUB_REPOSITORY" --verify-tag --prerelease \
        --title "$APP_NAME $VERSION" --notes-file "$NOTES"
}

# Only this run's tag on MAIN, and only while no release uses it.
remove_tag() {
    local listed
    [ "$(release_state)" = none ] || return 1
    listed=$(git ls-remote "$REMOTE" "refs/tags/$TAG^{}") || return 1
    [ -z "$listed" ] && return 0
    [ "${listed%%[[:space:]]*}" = "$MAIN" ] || return 1
    git push "$REMOTE" ":refs/tags/$TAG"
}

git -c user.name="$MAINTAINER_NAME" -c user.email="$MAINTAINER_EMAIL" \
    tag -f -a "$TAG" "$MAIN" -m "Notchcast snapshot $MAIN" >/dev/null || exit 1
retry "tag push" push_tag || exit 1
if retry "release" publish; then
    echo "Published $TAG"
    exit 0
fi
if [ "$pushed" -eq 1 ] && retry "stray tag removal" remove_tag; then
    echo "::error::Not published; removed $TAG again. Rerun the failed job: it reuses this run's build."
else
    echo "::error::Not published, and $TAG may remain on ${MAIN:0:8}: harmless, since snapshot.py plans from releases only."
fi
exit 1
