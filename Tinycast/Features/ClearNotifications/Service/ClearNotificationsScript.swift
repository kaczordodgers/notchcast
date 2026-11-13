import Foundation

enum ClearNotificationsScript {
    static var source: String {
        source(localized: ["Clear Notifications…", "Clear All Notifications", "Clear All", "Close"].map {
            SystemLanguages.localized($0, bundlePath: "/System/Library/CoreServices/NotificationCenter.app")
        })
    }

    static func source(localized: [String]) -> String {
        let names = localized.map {
            $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r")
        }
        return """
        on matchesName(candidate, names, prefixMatch)
            repeat with n in names
                if prefixMatch then
                    if candidate starts with (n as text) then return true
                else
                    if candidate is (n as text) then return true
                end if
            end repeat
            return false
        end matchesName

        on panelOpen()
            tell application "System Events" to tell process "NotificationCenter"
                return (count of windows) > 0
            end tell
        end panelOpen

        on toggleClock()
            tell application "System Events"
                try
                    tell process "MenuBarAgent"
                        click menu bar item 1 of (last group of menu bar 1)
                    end tell
                on error
                    error "notification-center-unavailable" number -10001
                end try
            end tell
        end toggleClock

        on openPanel()
            repeat 2 times
                set sawPanel to false
                if not my panelOpen() then my toggleClock()
                set stableChecks to 0
                repeat 40 times
                    delay 0.1
                    if my panelOpen() then
                        set sawPanel to true
                        set stableChecks to stableChecks + 1
                        if stableChecks = 5 then return "open"
                    else if stableChecks > 0 then
                        exit repeat
                    end if
                end repeat
            end repeat
            if sawPanel then return "empty"
            error "notification-center-unavailable" number -10001
        end openPanel

        on closePanel()
            if my panelOpen() then my toggleClock()
        end closePanel

        on findElement(e, wantRole, wantName, depth)
            tell application "System Events"
                try
                    if (role of e as text) is wantRole and ¬
                        my matchesName(name of e as text, wantName, false) then return e
                end try
                if depth > 10 then return missing value
                set kids to UI elements of e
                repeat with k in kids
                    set r to my findElement(k, wantRole, wantName, depth + 1)
                    if r is not missing value then return r
                end repeat
            end tell
            return missing value
        end findElement

        on clearAllViaMenu()
            tell application "System Events" to tell process "NotificationCenter"
                set w to window 1
                set mb to my findElement(w, "AXMenuButton", {"\(names[0])", "Clear Notifications…"}, 0)
                if mb is missing value then return false
                perform action "AXPress" of mb
                repeat 40 times
                    delay 0.1
                    if (count of menus of mb) > 0 then exit repeat
                end repeat
                if (count of menus of mb) = 0 then return false
                try
                    set clearItem to my findElement(menu 1 of mb, "AXMenuItem", ¬
                        {"\(names[1])", "Clear All Notifications"}, 0)
                    if clearItem is missing value then error "clear-menu-unavailable"
                    click clearItem
                    return true
                on error
                    try
                        perform action "AXCancel" of menu 1 of mb
                    end try
                    return false
                end try
            end tell
        end clearAllViaMenu

        on collectAlerts(e, depth, acc)
            tell application "System Events"
                set alertRole to ""
                try
                    set alertRole to subrole of e as text
                end try
                if alertRole is in {"AXNotificationCenterAlert", "AXNotificationCenterAlertStack", ¬
                    "AXNotificationCenterBanner"} then
                    set end of acc to e
                    return true
                end if
                set kids to UI elements of e
                if depth > 64 and (count of kids) > 0 then return false
                repeat with k in kids
                    if not my collectAlerts(k, depth + 1, acc) then return false
                end repeat
            end tell
            return true
        end collectAlerts

        on readAlerts()
            if not my panelOpen() then
                if my openPanel() is "empty" then return {}
            end if
            set alerts to {}
            tell application "System Events" to tell process "NotificationCenter"
                if not my collectAlerts(window 1, 0, alerts) then ¬
                    error "notification-tree-unreadable" number -10002
            end tell
            return alerts
        end readAlerts

        on closeAlert(a)
            tell application "System Events"
                set acts to actions of a
                repeat with ac in acts
                    if my matchesName(name of ac, {"Name:\(names[2])", "Name:Clear All"}, true) then
                        perform ac
                        return true
                    end if
                end repeat
                repeat with ac in acts
                    if my matchesName(name of ac, {"Name:\(names[3])", "Name:Close"}, true) then
                        perform ac
                        return true
                    end if
                end repeat
            end tell
            return false
        end closeAlert

        on clearOneByOne()
            repeat 40 times
                set alerts to my readAlerts()
                if (count of alerts) = 0 then return
                set closedThisPass to 0
                repeat with a in alerts
                    try
                        if my closeAlert(a) then set closedThisPass to closedThisPass + 1
                    end try
                end repeat
                if closedThisPass = 0 then return
                delay 0.15
            end repeat
        end clearOneByOne

        on verifyEmpty()
            repeat with attempt from 1 to 60
                try
                    set remaining to my readAlerts()
                    if (count of remaining) = 0 then return
                    if attempt = 60 then error "notifications-remain" number -10003
                on error reason number code
                    if attempt = 60 then error reason number code
                end try
                delay 0.1
            end repeat
        end verifyEmpty

        on run
            try
                with timeout of 30 seconds
                    set panelState to my openPanel()
                    set initialAlerts to {}
                    if panelState is not "empty" then
                        repeat with attempt from 1 to 60
                            try
                                set initialAlerts to my readAlerts()
                                exit repeat
                            on error reason number code
                                if code is not -1719 or attempt = 60 then error reason number code
                            end try
                            delay 0.1
                        end repeat
                    end if
                    set initialCount to count of initialAlerts
                    if initialCount > 0 then
                        if not my clearAllViaMenu() then my clearOneByOne()
                        my verifyEmpty()
                    end if
                end timeout
            on error reason number code
                try
                    my closePanel()
                end try
                error reason number code
            end try
            my closePanel()
            return initialCount
        end run
        """
    }
}
