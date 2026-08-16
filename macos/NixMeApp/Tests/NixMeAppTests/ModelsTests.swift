import XCTest
@testable import NixMeApp

final class ModelsTests: XCTestCase {
    func testSnapshotDecodesAndCalculatesDashboardCounts() throws {
        let data = Data(fixture.utf8)
        let snapshot = try JSONDecoder().decode(ManagementSnapshot.self, from: data)

        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.host.hostname, "bellerofonte")
        XCTAssertEqual(snapshot.desiredSoftwareCount, 5)
        XCTAssertEqual(snapshot.installedHomebrewCount, 3)
        XCTAssertEqual(snapshot.projectAttentionCount, 1)
        XCTAssertEqual(snapshot.softwareUpdateCount, 3)
        XCTAssertEqual(snapshot.updates.macAppStore.first?.storeId, 497799835)
        XCTAssertEqual(snapshot.configuration.desiredSource?.revision, "def-dirty")
        XCTAssertEqual(snapshot.softwareDifferences.count, 1)
        XCTAssertEqual(snapshot.softwareDifferences.first?.name, "git")
        XCTAssertEqual(snapshot.softwareDifferences.first?.change, .versionChanged)
        XCTAssertEqual(snapshot.softwareDifferences.first?.appliedVersion, "2.52.0")
        XCTAssertEqual(snapshot.softwareDifferences.first?.desiredVersion, "2.53.0")
    }

    private let fixture = #"""
    {
      "schemaVersion": 1,
      "generatedAt": "2026-08-12T10:00:00Z",
      "host": {"hostname":"bellerofonte","machineName":"Bellerofonte","machineType":"macbook-pro","username":"batman"},
      "configuration": {
        "path":"/Users/batman/.config/nixpkgs","exists":true,"appliedManifestPath":"/etc/nix-me/manifest.json",
        "applyState":"pending","generation":100,
        "desiredSource":{"revision":"def-dirty","dirty":true,"contentHash":"desired-source","lockHash":"desired-lock"},
        "appliedSource":{"revision":"abc","dirty":false,"contentHash":"applied-source","lockHash":"applied-lock"},
        "git":{"repository":true,"branch":"main","revision":"abc","dirty":false,"upstream":"origin/main","ahead":0,"behind":0,"remoteState":"upToDate"}
      },
      "health": {"nix":{"available":true,"version":"nix 2.31"},"nixDarwin":{"available":true},"homebrew":{"available":true}},
      "inventory": {
        "desired":{"nixPackages":["git-2.53.0","jq-1.8.1"],"nixPackageDetails":[{"name":"git","fullName":"git-2.53.0","version":"2.53.0","description":"Version control","homepage":"https://git-scm.com","license":"GPL-2.0"},{"name":"jq","fullName":"jq-1.8.1","version":"1.8.1","description":"JSON processor","homepage":"https://jqlang.org","license":"MIT"}],"homebrew":{"formulae":["coreutils"],"casks":["raycast"],"masApps":{"Xcode":497799835}}},
        "applied":{"nixPackages":["git-2.52.0","jq-1.8.1"],"homebrew":{"formulae":["coreutils"],"casks":["raycast"],"masApps":{"Xcode":497799835}}},
        "installed":{"homebrew":{"formulae":[{"name":"coreutils","versions":["9.7"]}],"casks":[{"name":"raycast","versions":["1.0"]},{"name":"rectangle","versions":["1.0"]}]}}
      },
      "updates":{
        "homebrew":[{"name":"raycast","kind":"cask","installedVersions":["1.0"],"availableVersion":"1.1"}],
        "macAppStore":[{"name":"Xcode","kind":"mas","installedVersions":["26.3"],"availableVersion":"26.4","storeId":497799835}],
        "nixFlake":[{"name":"nixpkgs","kind":"nixFlake","installedVersions":["abc1234"],"availableVersion":"def5678"}]
      },
      "projects":[
        {"name":"platformatic","url":"https://github.com/platformatic/platformatic.git","path":"src/platformatic/platformatic","branch":null,"remote":"origin","clone":true,"update":true,"absolutePath":"/Users/batman/src/platformatic/platformatic","present":true,"isGitRepository":true,"status":"current","git":null},
        {"name":"desk","url":"https://github.com/platformatic/desk.git","path":"src/platformatic/desk","branch":null,"remote":"origin","clone":true,"update":true,"absolutePath":"/Users/batman/src/platformatic/desk","present":false,"isGitRepository":false,"status":"missing","git":null}
      ],
      "warnings":[]
    }
    """#
}
