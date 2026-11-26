import XCTest
@testable import Roocast

final class LaunchHandoffPlanTests: XCTestCase {

    // MARK: - AC1: dismiss before launch / activate

    func testApplicationPlanDismissesBeforeActivateOrLaunch() {
        let plan = LaunchHandoffPlan.forApplication(path: "/Applications/Notes.app")
        XCTAssertEqual(
            plan.steps,
            [
                .dismissPanel,
                .activateOrLaunch(path: "/Applications/Notes.app"),
            ]
        )
    }

    func testFirefoxProfilePlanDismissesBeforeLaunch() {
        let plan = LaunchHandoffPlan.forFirefoxProfile(
            profile: "work",
            path: "/Applications/Firefox.app"
        )
        XCTAssertEqual(
            plan.steps,
            [
                .dismissPanel,
                .launchFirefoxProfile(profile: "work", path: "/Applications/Firefox.app"),
            ]
        )
    }

    func testFolderPlanDismissesBeforeOpen() {
        let plan = LaunchHandoffPlan.forFolder(path: "/Users/nate/Downloads")
        XCTAssertEqual(
            plan.steps,
            [
                .dismissPanel,
                .openFolder(path: "/Users/nate/Downloads"),
            ]
        )
    }

    // MARK: - AC2: launch dismiss does not restore prior-app focus

    func testLaunchPlansDoNotRestoreFocus() {
        XCTAssertFalse(LaunchHandoffPlan.forApplication(path: "/a.app").restoreFocus)
        XCTAssertFalse(
            LaunchHandoffPlan.forFirefoxProfile(profile: "p", path: "/a.app").restoreFocus
        )
        XCTAssertFalse(LaunchHandoffPlan.forFolder(path: "/tmp").restoreFocus)
    }

    // MARK: - AC3: do not await launch completion

    func testLaunchPlansDoNotAwaitCompletion() {
        XCTAssertFalse(LaunchHandoffPlan.forApplication(path: "/a.app").awaitsLaunchCompletion)
        XCTAssertFalse(
            LaunchHandoffPlan.forFirefoxProfile(profile: "p", path: "/a.app")
                .awaitsLaunchCompletion
        )
        XCTAssertFalse(LaunchHandoffPlan.forFolder(path: "/tmp").awaitsLaunchCompletion)
    }

    // MARK: - AC4: exact URL — no running-application substitution

    func testLaunchPlansDisableRunningApplicationSubstitution() {
        XCTAssertFalse(
            LaunchHandoffPlan.forApplication(path: "/a.app")
                .allowsRunningApplicationSubstitution
        )
        XCTAssertFalse(
            LaunchHandoffPlan.forFirefoxProfile(profile: "p", path: "/a.app")
                .allowsRunningApplicationSubstitution
        )
    }
}
