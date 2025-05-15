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
            if scene.gameOver {
                VStack {
                    Text("Game Over")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    Color.black.opacity(0.5)
                }
            } else if !scene.clientOkay {
                VStack {
                    Button("Connect") {
                        scene.activateClient()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    Color.black.opacity(0.5)
                }
            } else if scene.selectCharacter {
                VStack {
                    Text("Select your character")
                    ForEach(scene.characterIds, id: \.self) { characterID in
                        Button("Char \(characterID)") {
                            scene.selectCharacter(characterID)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    Color.black.opacity(0.5)
                }
            } else if scene.gamePaused {
                VStack {
                    Text("Game Paused")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    Color.black.opacity(0.5)
                }
            } 
        }
    }
}
