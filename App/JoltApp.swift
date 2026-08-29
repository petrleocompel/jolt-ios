import SwiftData
import SwiftUI

@main
struct JoltApp: App {
    @UIApplicationDelegateAdaptor(JoltAppDelegate.self) private var appDelegate
    @State private var dependencies = AppDependencies()
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environment(dependencies)
                    .modelContainer(dependencies.modelContainer)
                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .task {
                // A brief branded hold, then cross-fade to the app.
                try? await Task.sleep(for: .seconds(1.4))
                withAnimation(.easeOut(duration: 0.4)) { showSplash = false }
            }
        }
    }
}
