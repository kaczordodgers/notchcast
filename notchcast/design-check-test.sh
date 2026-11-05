#!/bin/bash
set -euo pipefail
tools=$(cd "$(dirname "$0")" && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin" "$scratch/repo/notchcast" "$scratch/tmp"
cp "$tools/design-check.sh" "$scratch/repo/notchcast/"
printf 'DESIGN_CHECK_VERSION=test\n' > "$scratch/repo/notchcast/config.env"
cat > "$scratch/bin/git" <<'STUB'
#!/bin/bash
case "$1" in
    rev-parse) echo "$FIXTURE" ;;
    archive) tar -cf - -T /dev/null ;;
esac
STUB
cat > "$scratch/bin/npx" <<'STUB'
#!/bin/bash
case " $* " in
    *' --write-baseline '*) echo '{}' > .ai-design-check-baseline.json ;;
    *) exit "$CHECK_STATUS" ;;
esac
STUB
printf '#!/bin/bash\nexit 0\n' > "$scratch/bin/python3"
printf '#!/bin/bash\n/usr/bin/mktemp -d "$TMPDIR/check.XXXXXX"\n' > "$scratch/bin/mktemp"
chmod +x "$scratch/bin/"*
export PATH="$scratch/bin:$PATH" FIXTURE="$scratch/repo" TMPDIR="$scratch/tmp"
for expected in 0 7; do
    actual=0
    CHECK_STATUS=$expected bash "$tools/design-check.sh" base || actual=$?
    [ "$actual" -eq "$expected" ] || { echo "FAIL: status $actual, expected $expected"; exit 1; }
    [ -z "$(ls -A "$TMPDIR")" ] || { echo "FAIL: archived scratch trees leaked (status $expected)"; exit 1; }
done
echo 'PASS: scratch trees removed and checker statuses 0 and 7 preserved'
