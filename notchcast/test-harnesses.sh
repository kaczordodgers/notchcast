# Sourced by upstream's runner so fork harnesses never need another shared registration.
for harness in $(ls Tests/nc-*-test.swift Tests/notchcast-*-test.swift 2>/dev/null; grep -l "^// notchcast-sources: " Tests/*-test.swift | grep -v -E "Tests/(nc|notchcast)-") ; do
    [ -e "$harness" ] || continue
    name=$(basename "$harness" .swift)
    sources=$(sed -n 's|^// notchcast-sources: ||p' "$harness")
    if [ -n "$sources" ]; then
        if [[ "$name" != nc-* && "$name" != notchcast-* ]]; then
            if [ "$emit_db" -eq 1 ]; then
                if node - "$DB" "$PWD/$harness" $sources <<'JS'
const fs = require("node:fs");
const path = require("node:path");
const [file, harness, ...sources] = process.argv.slice(2);
const entries = JSON.parse(fs.readFileSync(file, "utf8") + "]");
const entry = entries.find((item) => item.files.includes(harness));
if (!entry) process.exit(1);
entry.command += " " + sources.map((source) => path.resolve(source)).join(" ");
fs.writeFileSync(file, JSON.stringify(entries).slice(0, -1));
JS
                then continue; fi
            else
                found=0
                extra_sources=$(printf '%s ' $sources)
                extra_sources=${extra_sources% }
                for queue_file in "$QUEUE" "$EXCLUSIVE_QUEUE"; do
                    if awk -v name="$name" '$2 == name { found=1 } END { exit !found }' "$queue_file"; then
                        awk -v name="$name" -v extras="$extra_sources" \
                            '$2 == name { $0 = $0 " " extras } { print }' "$queue_file" > "$queue_file.sources"
                        mv "$queue_file.sources" "$queue_file"
                        found=1
                    fi
                done
                [ "$found" -eq 0 ] || continue
            fi
        fi
        run "$name" $sources
    elif [[ "$name" == nc-* ]]; then
        folder=${name#nc-}
        run "$name" $(ls Tinycast/Features/${folder%%-*}/{Model,Service}/*.swift 2>/dev/null)
    elif grep -q "^run $name " "$SELF"; then
        continue
    else
        # Compiles alone and fails as one harness; the rest of the suite still runs.
        echo "::error::$harness needs a // notchcast-sources: header" >&2
        run "$name"
    fi
done
