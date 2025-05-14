import SwiftUI

@main
struct WitWizApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: 960, height: 640)
        }
        .windowResizability(.contentSize)
    }
}
