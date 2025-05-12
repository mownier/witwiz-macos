import SwiftUI
import SpriteKit
import WitWizCl

struct ContentView: View {
    @StateObject var scene = GameScene()
    
    var body: some View {
        ZStack {
            SpriteView(scene: scene)
                .onAppear {
                    scene.activateClient()
                }
                .onDisappear {
                    scene.deactivateClient()
                }
            if !scene.clientOkay {
                Button("Connect") {
                    scene.activateClient()
                }
            }
        }
    }
}
