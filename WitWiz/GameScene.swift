import Foundation
import Cocoa
import SpriteKit
import WitWizCl
import GRPCCore
import GRPCNIOTransportHTTP2

class GameScene: SKScene, ObservableObject {
    let (playerInputStream, playerInputContinuation) = AsyncStream<Witwiz_PlayerInput>.makeStream()
    let (gameStateStream, gameStateContinuation) = AsyncStream<Witwiz_GameStateUpdate>.makeStream()
    
    var yourId: Int32?
    var gameState: Witwiz_GameStateUpdate?
    var connectClientTask: Task<Void, Error>?
    var processGameStateTask: Task<Void, Error>?
    
    override func didMove(to view: SKView) {
        startTasks()
    }
    
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 13: // w
            var input = Witwiz_PlayerInput()
            input.action = .moveUp
            input.playerID = yourId ?? -1
            playerInputContinuation.yield(input)
        case 0: // a
            var input = Witwiz_PlayerInput()
            input.action = .moveLeft
            input.playerID = yourId ?? -1
            playerInputContinuation.yield(input)
        case 1: // s
            var input = Witwiz_PlayerInput()
            input.action = .moveDown
            input.playerID = yourId ?? -1
            playerInputContinuation.yield(input)
        case 2: // d
            var input = Witwiz_PlayerInput()
            input.action = .moveRight
            input.playerID = yourId ?? -1
            playerInputContinuation.yield(input)
        default:
            break
        }
    }
    
    func cleanUp() {
        stopTasks()
    }
    
    private func startTasks() {
        if processGameStateTask != nil && connectClientTask != nil {
            return
        }
        processGameStateTask?.cancel()
        connectClientTask?.cancel()
        processGameStateTask = Task {
            for await state in gameStateStream {
                if Task.isCancelled {
                    return
                }
                processGameState(state)
            }
        }
        connectClientTask = Task {
            try await connectClient()
        }
    }
    
    private func stopTasks() {
        connectClientTask?.cancel()
        processGameStateTask?.cancel()
        connectClientTask = nil
        processGameStateTask = nil
    }
    
    private func connectClient() async throws {
        let client = await WitWizClient().host("192.168.1.6").port(40041).useTLS(false)
        try await client.joinGame(playerInputStream, gameStateContinuation)
        processGameStateTask?.cancel()
        processGameStateTask = nil
        gameState = nil
        yourId = nil
        connectClientTask = nil
    }
    
    func processGameState(_ state: Witwiz_GameStateUpdate) {
        print("gameState", state)
        gameState = state
        if yourId == nil && state.yourPlayerID != 0 {
            yourId = state.yourPlayerID
        }
    }
}
