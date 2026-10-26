import XCTest
@testable import NixMeApp

final class MenuBarIndicatorTests: XCTestCase {
    func testCriticalStateHasHighestPriority() {
        XCTAssertEqual(
            MenuBarIndicator.resolve(
                setupNeedsAttention: false,
                hasError: true,
                isWorking: true,
                hasCriticalFailure: false,
                needsAttention: true,
                softwareUpdateCount: 12
            ),
            .critical
        )
    }

    func testAttentionTakesPriorityOverAvailableUpdates() {
        XCTAssertEqual(
            MenuBarIndicator.resolve(
                setupNeedsAttention: false,
                hasError: false,
                isWorking: false,
                hasCriticalFailure: false,
                needsAttention: true,
                softwareUpdateCount: 12
            ),
            .attention
        )
    }

    func testAvailableUpdatesCarryTheirCount() {
        XCTAssertEqual(
            MenuBarIndicator.resolve(
                setupNeedsAttention: false,
                hasError: false,
                isWorking: false,
                hasCriticalFailure: false,
                needsAttention: false,
                softwareUpdateCount: 3
            ),
            .updates(3)
        )
    }

    func testCurrentStateHasNoBadge() {
        XCTAssertEqual(
            MenuBarIndicator.resolve(
                setupNeedsAttention: false,
                hasError: false,
                isWorking: false,
                hasCriticalFailure: false,
                needsAttention: false,
                softwareUpdateCount: 0
            ),
            .current
        )
    }
}
