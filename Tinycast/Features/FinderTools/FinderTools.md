# Finder tools

Both switches default on in the fork-local preferences and work independently of the island.
Accessibility is declared through `NotchcastFeature.requiredGrants`; the existing Permissions pane
owns consent. Nothing prompts on startup. Finder's native keyboard commands need no Apple Events
or Automation grant.

Command-X copies Finder's selection and remembers that clipboard version. Command-V then asks
Finder to Move Item Here (Option-Command-V). Finder owns conflicts, failures, cross-volume moves,
and its native progress UI. A different clipboard version, Command-C, Escape, disabling the feature,
or losing Accessibility cancels the pending cut. Text editing receives the original cut/paste keys.

Hyper-R sends Finder's Return key when no text or dialog is being edited, following the native
Return variant of the feature. Other applications keep their shortcuts. Cut, paste and rename
register through `NotchcastCommandCatalog+All.swift` and support launcher aliases and hotkeys.

The shared tap does no Accessibility queries or waiting. Requests carry lifecycle and cut identities;
Accessibility reads leave the main actor, and results must still address the frontmost Finder.
Injected events target Finder's PID and carry the existing synthetic-event tag.
App-activation notifications refresh context and permissions; there are no idle polling timers.

The private cut session validates the clipboard version before requesting a move.
A custom progress HUD and clipboard-image paste are not provided here. No Finder progress percentage
is inferred from a submitted keyboard command.

Run `./Scripts/run-tests.sh nc-FinderTools-policy-test` and
`./Scripts/run-tests.sh nc-FinderTools-services-test`. They compile shipped sources without changing
the clipboard, user files, or Finder. Finder's native move/rename behavior requires a later live check
in a temporary directory with Accessibility granted.
