import SwiftUI

@main
struct NixMeApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardView()
                .frame(minWidth: 1040, minHeight: 680)
        }
        .defaultSize(width: 1180, height: 760)
        .windowToolbarStyle(.unified)
    }
}
