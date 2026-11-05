#!/bin/bash
set -euo pipefail
tools=$(cd "$(dirname "$0")" && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir "$scratch/bin"
printf 'working helper\n' > "$scratch/helper"
printf 'working rule\n' > "$scratch/rule"
cat > "$scratch/bin/git" <<'STUB'
#!/bin/bash
echo ' M main.swift'
STUB
printf '#!/bin/bash\necho fixture\n' > "$scratch/bin/stat"
printf '#!/bin/bash\necho 0\n' > "$scratch/bin/id"
printf '#!/bin/bash\necho "FAIL: sudo invoked" >&2\nexit 99\n' > "$scratch/bin/sudo"
chmod +x "$scratch/bin/"*
sed -e "s|^PATH=.*|PATH=$scratch/bin:/usr/bin:/bin:/usr/sbin:/sbin|" \
    -e 's|/usr/bin/git|git|g' -e 's|/usr/bin/id|id|g' -e 's|/usr/bin/stat|stat|g' \
    -e "s|^helper=.*|helper=$scratch/helper|" -e "s|^rule=.*|rule=$scratch/rule|" \
    "$tools/root/install.sh" > "$scratch/install.sh"
status=0
bash "$scratch/install.sh" > "$scratch/output" 2>&1 || status=$?
[ "$status" -eq 65 ] || { cat "$scratch/output"; exit 1; }
grep -q 'uncommitted changes' "$scratch/output"
[ -f "$scratch/helper" ] && [ -f "$scratch/rule" ] || { echo 'FAIL: dirty checkout removed installed helper or rule'; exit 1; }
[ "$(cat "$scratch/helper")" = 'working helper' ]
[ "$(cat "$scratch/rule")" = 'working rule' ]
echo 'PASS: dirty checkout preserves installed helper and sudo rule'
