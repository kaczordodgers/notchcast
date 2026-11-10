## Launcher commands

Add Task from Clipboard parses one task with the quick-add parser, resolving existing projects,
sections and labels and parsing English or Polish dates. Complete Next Task uses the default Today
view ordering, including overdue tasks. Undo Last Task Change uses the store's persisted undo log.
Each action reports its result through command feedback and checks the Tasks switch before reading
the clipboard or accessing the store. The switch also refreshes launcher availability. Command deep
links use the command hook's standard consent gate.
