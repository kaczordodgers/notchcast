# Release app proofs

`Proof` runs named checks inside the real Release binary built on the snapshot runner (`xcode-27`, using the snapshot Xcode selection). On a PR it builds the PR merged onto main, so a branch cut before a tool existed still runs it. It catches optimizer, toolchain, linker and Release-only flag failures that standalone harnesses cannot reproduce. The `proof` check-run must succeed on the exact PR head before `land.sh` lands changes to declared paths.

Checks run before app startup, only with bundle ID `app.notchcast.proof` and `NOTCHCAST_PROOF` set. They must remain synchronous and free of persistence, UI, permissions, network and Keychain access. They cannot verify UI input, permission prompts, hardware (treadmill, amp or fans), notifications, network services, Keychain, another Mac over SSH or runtime app state.

Add a check function and one registry line in `Tinycast/Features/AppProof/NotchcastAppProof.swift`, then declare its triggering path globs in `notchcast/app-proofs.json`. Include both the successful case and the rejection case. Run `python3 notchcast/app-proof.py plan origin/main HEAD` to inspect selection and `python3 notchcast/app-proof.py run spotify-key` to build and run locally. Local builds use the build queue when available; each invocation costs one full arm64 Release build in temporary derived data. CI skips the Mac job when no check applies.

`run --app /temporary/path/Notchcast.app spotify-key` copies, changes the copy's identity and signs it ad hoc before direct execution. Paths under `/Applications` are refused. The installed app is never used. Local success with a newer Xcode does not prove the snapshot toolchain; the PR's `proof` check provides that evidence.
