# Low disk warning

Low disk warning watches free space on the startup disk. Set **Warn below** in Settings to choose when the island warns. After one warning, a drive icon stays in the resting island. A song or meeting glance takes priority over the icon. Hover or open the island to see the **Low disk space** label. Click the status or run **Check Disk Space** to read and show the current free space.

## Invariants

- The same saved flag tracks whether the current spell has warned and whether a valid, awake reading should show the icon. Restarting while space is still low restores the icon after the first reading. Turning the switch off clears it.
- A reading clears the icon and re-arms the warning once free space reaches the threshold plus 10% of that threshold or 1 GB, whichever is greater. At the default 10 GB threshold the warning starts below 10 GB and clears at 11 GB.
- The module checks at startup, on display wake, when the threshold changes and every 30 minutes. Clicking the status or running **Check Disk Space** can clear it sooner. Failed reads and reads while the display is asleep leave the warning state alone.
