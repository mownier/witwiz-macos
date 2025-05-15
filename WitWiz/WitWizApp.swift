import SwiftUI

@main
struct WitWizApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: 1080, height: 720)
        }
        .windowResizability(.contentSize)
    }
}
