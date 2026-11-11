extension NotchcastPreferences {
    /// The one Status Messages gate: its descriptor depends on Island, the only surface that shows one.
    var showsStatusMessages: Bool { isEnabled(.islandStatusMessages) }
}
