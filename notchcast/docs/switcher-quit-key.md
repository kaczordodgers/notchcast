# Switcher quit key

The optional Notchcast Launcher switch enables bare Q in Switch Windows when search is empty.
It defaults off and is independent of Navigation and the island. Existing quit shortcuts remain.
Menus, marked text, modified keys and nonempty searches keep their normal input behavior.
Repeats are consumed without another quit request. Quit uses upstream's coordinator: save sheets
can refuse termination, and rows leave only when the application exits.

This is the smallest catalogue delta. Close-window W, previews and Cmd-Tab takeover are deferred.
The only upstream hook is the first line of `PalettePanel.sendEvent`; fork code validates the
panel's palette identity before dispatching to the selected live window's application.

`Tests/notchcast-switcher-quit-test.swift` checks input eligibility without Accessibility.
