import SwiftData
import SwiftUI

@main
struct JoltApp: App {
    @State private var dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(dependencies)
                .modelContainer(dependencies.modelContainer)
        }
    }
}
