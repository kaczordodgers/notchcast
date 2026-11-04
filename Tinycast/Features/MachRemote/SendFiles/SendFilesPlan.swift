import Foundation

enum SendFilesPlan {
    static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func prepare(staging: String) -> String {
        "mkdir -p Downloads && mkdir -- " + quote(staging)
    }

    static func arguments(source: URL, alias: String, staging: String) -> [String] {
        ["-a", "--safe-links", "--progress", "--timeout=30", "-e", "ssh -o BatchMode=yes",
         "--", source.path, alias + ":" + quote(staging + "/")]
    }

    static func commit(staging: String, name: String) -> String {
        // A hidden lock serializes our claims; mv -n also protects names created by other apps.
        """
        s=\(quote(staging + "/" + name)); n=\(quote(name)); i=1
        while [ "$i" -le 100 ]; do
          d="Downloads/$n"; lock="$d.notchcast-claim"
          if mkdir -- "$lock" 2>/dev/null; then
            if [ ! -e "$d" ] && [ ! -L "$d" ]; then
              mv -n -- "$s" "$d"
              rc=$?
              rmdir -- "$lock"
              if [ "$rc" -eq 0 ] && [ ! -e "$s" ] && [ ! -L "$s" ]; then exit 0; fi
              exit 1
            fi
            rmdir -- "$lock"
          fi
          i=$((i+1)); n=\(quote(name))" $i"
        done
        exit 3
        """
    }

    static func percent(in record: String) -> Int? {
        let fields = record.split(whereSeparator: \.isWhitespace)
        guard fields.count >= 2, fields[0].allSatisfy({ $0.isNumber || $0 == "," }),
              fields[1].hasSuffix("%"), let value = Int(fields[1].dropLast()), (0...100).contains(value)
        else { return nil }
        return value
    }
}
