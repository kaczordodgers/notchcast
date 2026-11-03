# Sourced by upstream's runner so fork harnesses never need another shared registration.
for harness in $(ls Tests/nc-*-test.swift Tests/notchcast-*-test.swift 2>/dev/null; grep -l "^// notchcast-sources: " Tests/*-test.swift | grep -v -E "Tests/(nc|notchcast)-") ; do
    [ -e "$harness" ] || continue
    name=$(basename "$harness" .swift)
    sources=$(sed -n 's|^// notchcast-sources: ||p' "$harness")
    if [ -n "$sources" ]; then
        run "$name" $sources
    elif [[ "$name" == nc-* ]]; then
        folder=${name#nc-}
        run "$name" $(ls Tinycast/Features/${folder%%-*}/{Model,Service}/*.swift 2>/dev/null)
    else
        # Compiles alone and fails as one harness; the rest of the suite still runs.
        echo "::error::$harness needs a // notchcast-sources: header" >&2
        run "$name"
    fi
done
