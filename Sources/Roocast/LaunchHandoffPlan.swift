import Foundation

/// Tinycast-style launcher → app handoff.
///
/// A slow cold start must never freeze a visible panel: dismiss first, then
/// fire Launch Services without waiting for the target to finish launching.
struct LaunchHandoffPlan: Equatable {
    enum Step: Equatable {
        case dismissPanel
        case activateOrLaunch(path: String)
        case launchFirefoxProfile(profile: String, path: String)
        case openFolder(path: String)
    }

    /// Escape / hotkey restore is wrong here — the target activates itself.
    let restoreFocus: Bool
    /// Waiting on `openApplication` completion (or app finish) freezes the UI.
    let awaitsLaunchCompletion: Bool
    /// Pin the selected installation; do not substitute another running copy.
    let allowsRunningApplicationSubstitution: Bool
    let steps: [Step]

    /// Standard app row (Enter / click).
    nonisolated static func forApplication(path: String) -> LaunchHandoffPlan {
        LaunchHandoffPlan(
            restoreFocus: false,
            awaitsLaunchCompletion: false,
            allowsRunningApplicationSubstitution: false,
            steps: [.dismissPanel, .activateOrLaunch(path: path)]
        )
    }

    /// Firefox profile row — same dismiss-first order.
    nonisolated static func forFirefoxProfile(profile: String, path: String) -> LaunchHandoffPlan {
        LaunchHandoffPlan(
            restoreFocus: false,
            awaitsLaunchCompletion: false,
            allowsRunningApplicationSubstitution: false,
            steps: [.dismissPanel, .launchFirefoxProfile(profile: profile, path: path)]
        )
    }

    /// Folder shortcut row.
    nonisolated static func forFolder(path: String) -> LaunchHandoffPlan {
        LaunchHandoffPlan(
            restoreFocus: false,
            awaitsLaunchCompletion: false,
            allowsRunningApplicationSubstitution: false,
            steps: [.dismissPanel, .openFolder(path: path)]
        )
    }
}
