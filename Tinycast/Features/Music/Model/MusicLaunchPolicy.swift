// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum MusicLaunchPolicy {
    static let launchArmWindow: TimeInterval = 2

    enum MediaKey: Equatable, Sendable {
        case playPause
        case next
        case previous
        case fastForward
        case rewind
    }

    static func shouldBlock(now: TimeInterval, keyAt: TimeInterval?, gestureAge: TimeInterval) -> Bool {
        guard now.isFinite, now >= 0, let keyAt, keyAt.isFinite, keyAt >= 0,
            !gestureAge.isNaN, gestureAge >= 0 else { return false }
        let elapsed = now - keyAt
        return (0...launchArmWindow).contains(elapsed) && gestureAge > elapsed
    }
}
