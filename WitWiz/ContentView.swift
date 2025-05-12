import SwiftUI
import SpriteKit
import WitWizCl

struct ContentView: View {
    @StateObject var scene = GameScene()
    
    var body: some View {
        SpriteView(scene: scene)
            .onDisappear {
                scene.isPaused = true
                scene.cleanUp()
            }
        Button("Action") {
            print("TODO")
        }
    }
}
