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
# CI narrows the finished queue here: a selection, one "<index> <count>" shard by a hash of the name
# (so a harness keeps its shard, and its cached binary, when others come and go), then the hosted runner's skips.
if [ "$emit_db" -eq 0 ] && [ -z "$only" ] && [ -n "${NOTCHCAST_ONLY_TESTS:-}${CI_SKIP_TESTS:-}${NOTCHCAST_SHARD:-}" ]; then
    awk -v only=" ${NOTCHCAST_ONLY_TESTS:-} " -v skip=" ${CI_SKIP_TESTS:-} " -v shard="${NOTCHCAST_SHARD:-0 1}" '
        BEGIN { split(shard, part, " "); alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.+" }
        only !~ /^ *$/ && !index(only, " " $2 " ") { next }
        { skipped = index(skip, " " $2 " "); total += !skipped }
        { hash = 0; for (i = 1; i <= length($2); i++) hash = (hash * 31 + index(alphabet, substr($2, i, 1))) % 1000003 }
        hash % part[2] != part[1] { next }
        skipped { print "skipped on the runner: " $2 > "/dev/stderr"; next }
        { kept++; print }
        END { if (part[2] > 1) print "shard " part[1] " of " part[2] ": " kept + 0 " of " total + 0 " harnesses" > "/dev/stderr" }
        ' "$QUEUE" > "$QUEUE.kept" || exit 1
    mv "$QUEUE.kept" "$QUEUE"
    ran=$(($(wc -l < "$QUEUE")))
fi
