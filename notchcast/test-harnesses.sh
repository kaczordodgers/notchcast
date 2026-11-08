# Sourced by upstream's runner so fork harnesses never need another shared registration.
harness_inputs=$(python3 notchcast/harness_inputs.py) || {
    echo '::error::Fork harness input resolution failed; refusing an incomplete test suite' >&2
    exit 1
}
while IFS=$'\t' read -r harness has_header sources; do
    [ -e "$harness" ] || continue
    name=$(basename "$harness" .swift)
    if [ "$has_header" -eq 1 ]; then
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
                for queue_file in "$QUEUE" ${EXCLUSIVE_QUEUE:+"$EXCLUSIVE_QUEUE"}; do # upstream dropped it in ff4fa05
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
        run "$name" $sources
    elif grep -q "^run $name " "$SELF"; then
        continue
    else
        # Compiles alone and fails as one harness; the rest of the suite still runs.
        echo "::error::$harness needs a // notchcast-sources: header" >&2
        run "$name"
    fi
done <<< "$harness_inputs"
