import Foundation
import Cocoa
import SpriteKit
import WitWizCl
import GRPCCore
import GRPCNIOTransportHTTP2

class GameScene: SKScene, ObservableObject {
    var yourId: Int32?
    var gameState: Witwiz_GameStateUpdate?
    var connectClientTask: Task<Void, Error>?
    var processGameStateTask: Task<Void, Error>?
    
    var playerInputContinuation: AsyncStream<Witwiz_PlayerInput>.Continuation?
    
    @Published var clientOkay: Bool = false
    
    override func didMove(to view: SKView) {
        backgroundColor = .gray
    }
    
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 13: // w
            var input = Witwiz_PlayerInput()
            input.action = .moveUp
            input.playerID = yourId ?? -1
            playerInputContinuation?.yield(input)
        case 0: // a
            var input = Witwiz_PlayerInput()
            input.action = .moveLeft
            input.playerID = yourId ?? -1
            playerInputContinuation?.yield(input)
        case 1: // s
            var input = Witwiz_PlayerInput()
            input.action = .moveDown
            input.playerID = yourId ?? -1
            playerInputContinuation?.yield(input)
        case 2: // d
            var input = Witwiz_PlayerInput()
            input.action = .moveRight
            input.playerID = yourId ?? -1
            playerInputContinuation?.yield(input)
        default:
            break
        }
    }
    
    func activateClient() {
        processGameStateTask?.cancel()
        connectClientTask?.cancel()
        connectClientTask = Task {
            do {
                try await connectClient()
            } catch {
                clientOkay = false
            }
        }
        clientOkay = true
    }
    
    func deactivateClient() {
        connectClientTask?.cancel()
        processGameStateTask?.cancel()
        connectClientTask = nil
        processGameStateTask = nil
    }
    
    private func connectClient() async throws {
        let (gsStream, gsContinuation) = AsyncStream<Witwiz_GameStateUpdate>.makeStream()
        let (piStream, piContinuation) = AsyncStream<Witwiz_PlayerInput>.makeStream()
        playerInputContinuation = piContinuation
        processGameStateTask?.cancel()
        processGameStateTask = Task {
            for try await state in gsStream {
                processGameState(state)
            }
        }
        let client = await WitWizClient().host("192.168.1.6").port(40041).useTLS(false)
        try await client.joinGame(piStream, gsContinuation)
        processGameStateTask?.cancel()
        processGameStateTask = nil
        gameState = nil
        yourId = nil
        connectClientTask = nil
    }
    
    private func processGameState(_ state: Witwiz_GameStateUpdate) {
        print("gameState", state)
        gameState = state
        if yourId == nil && state.yourPlayerID != 0 {
            yourId = state.yourPlayerID
        }
        state.players.forEach { player in
            
        }
    }
}
