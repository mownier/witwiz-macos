import SwiftUI
import SpriteKit
import WitWizCl

struct ContentView: View {
    @StateObject var scene = GameScene()
    
    var body: some View {
        ZStack {
            GeometryReader { reader in
                SpriteView(scene: scene.setSize(reader.size))
                    .onAppear {
                        scene.activateClient()
                    }
                    .onDisappear {
                        scene.deactivateClient()
                    }
            }
            if !scene.clientOkay {
                Button("Connect") {
                    scene.activateClient()
                }
            }
        }
    }
}
