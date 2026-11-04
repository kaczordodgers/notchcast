# Memory monitor

Run `bash notchcast/install-memory-monitor.sh` from a checkout. The installer copies the sampler into Application Support and installs only `notchcast.memory`. It runs immediately and every 900 seconds; a stopped app produces no row. It uses the Python interpreter selected at installation. Reinstall after changing that interpreter or updating the sampler.

Samples append to `~/Library/Logs/notchcast/memory.csv`: UTC timestamp, installed version and build, process elapsed time, physical footprint, lifetime footprint peak and RSS. Memory uses decimal MB; footprint and RSS measure different things. It samples only the executable in `/Applications/Notchcast.app`. Errors go to `memory-monitor.log` and produce no partial row. No network, app settings, hardware or CI is involved.

Run `python3 notchcast/memory.py trend` to print first, last and maximum footprint per build, maximum lifetime peak and RSS, and the count of RSS samples above the upstream 100 MB resident budget. This is a report, with no pass/fail threshold. Sparse samples cannot identify a short-lived spike's cause; peak persists until process exit.

Remove the monitor with `launchctl bootout gui/$(id -u)/notchcast.memory`, then remove its plist and installed sampler if desired. The CSV remains a local historical record.
