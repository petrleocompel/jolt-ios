import SwiftData
import SwiftUI

@main
struct JoltApp: App {
    @UIApplicationDelegateAdaptor(JoltAppDelegate.self) private var appDelegate
    @State private var dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(dependencies)
                .modelContainer(dependencies.modelContainer)
        }
    }
}
