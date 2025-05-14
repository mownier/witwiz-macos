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
    var worldViewPort: Witwiz_ViewPort?
    
    var playerInputContinuation: AsyncStream<Witwiz_PlayerInput>.Continuation?
    
    var moveUpKeyPressed: Bool = false
    var moveDownKeyPressed: Bool = false
    var moveRightKeyPressed: Bool = false
    var moveLeftKeyPressed: Bool = false
    
    @Published var clientOkay: Bool = false
    
    func setSize(_ value: CGSize) -> GameScene {
        size = value
        if let playerID = yourId {
            sendViewPort(playerID)
        }
        return self
    }
    
    override func didMove(to view: SKView) {
        backgroundColor = .gray
    }
    
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 13 where !moveUpKeyPressed: // w
            moveUpKeyPressed = true
            var input = Witwiz_PlayerInput()
            input.action = .moveUpStart
            input.playerID = yourId ?? -1
            playerInputContinuation?.yield(input)
        case 0 where !moveLeftKeyPressed: // a
            moveLeftKeyPressed = true
            var input = Witwiz_PlayerInput()
            input.action = .moveLeftStart
            input.playerID = yourId ?? -1
            playerInputContinuation?.yield(input)
        case 1 where !moveDownKeyPressed: // s
            moveDownKeyPressed = true
            var input = Witwiz_PlayerInput()
            input.action = .moveDownStart
            input.playerID = yourId ?? -1
            playerInputContinuation?.yield(input)
        case 2 where !moveRightKeyPressed: // d
            moveRightKeyPressed = true
            var input = Witwiz_PlayerInput()
            input.action = .moveRightStart
            input.playerID = yourId ?? -1
            playerInputContinuation?.yield(input)
        default:
            break
        }
    }
    
    override func keyUp(with event: NSEvent) {
        switch event.keyCode {
        case 13 where moveUpKeyPressed: // w
            moveUpKeyPressed = false
            var input = Witwiz_PlayerInput()
            input.action = .moveUpStop
            input.playerID = yourId ?? -1
            playerInputContinuation?.yield(input)
        case 0 where moveLeftKeyPressed: // a
            moveLeftKeyPressed = false
            var input = Witwiz_PlayerInput()
            input.action = .moveLeftStop
            input.playerID = yourId ?? -1
            playerInputContinuation?.yield(input)
        case 1 where moveDownKeyPressed: // s
            moveDownKeyPressed = false
            var input = Witwiz_PlayerInput()
            input.action = .moveDownStop
            input.playerID = yourId ?? -1
            playerInputContinuation?.yield(input)
        case 2 where moveRightKeyPressed: // d
            moveRightKeyPressed = false
            var input = Witwiz_PlayerInput()
            input.action = .moveRightStop
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
        if let yourId = yourId {
            childNode(withName: "player\(yourId)")?.removeFromParent()
        }
        gameState = nil
        yourId = nil
        connectClientTask = nil
        worldViewPort = nil
        playerInputContinuation = nil
    }
    
    private func processGameState(_ state: Witwiz_GameStateUpdate) {
        gameState = state
        if yourId == nil && state.yourPlayerID != 0 {
            yourId = state.yourPlayerID
            sendViewPort(state.yourPlayerID)
        }
        if worldViewPort == nil && state.hasWorldViewPort {
            worldViewPort = state.worldViewPort
        }
        state.players.forEach { player in
            if let node = childNode(withName: "player\(player.playerID)") {
                let pos = CGPoint(x: player.position.x.cgFloat, y: player.position.y.cgFloat)
                node.position = pos
            } else {
                let size = CGSize(width: player.boundingBox.width.cgFloat, height: player.boundingBox.height.cgFloat)
                let position = CGPoint(x: player.position.x.cgFloat, y: player.position.y.cgFloat)
                let rect = CGRect(origin: CGPoint(x: 0, y: 0), size: size)
                let node = SKShapeNode(rect: rect)
                node.name = "player\(player.playerID)"
                if player.playerID == 1 {
                    node.fillColor = .blue
                    node.strokeColor = .blue
                } else if player.playerID == 2 {
                    node.fillColor = .orange
                    node.strokeColor = .orange
                } else {
                    node.fillColor = .red
                    node.strokeColor = .red
                }
                node.position = position
                addChild(node)
            }
        }
    }
    
    private func sendViewPort(_ playerID: Int32) {
        var input = Witwiz_PlayerInput()
        input.playerID = playerID
        input.action = .reportViewport
        input.viewPort = Witwiz_ViewPort()
        input.viewPort.width = size.width.float
        input.viewPort.height = size.height.float
        playerInputContinuation?.yield(input)
    }
}

extension Float {
    var cgFloat: CGFloat {
        return CGFloat(self)
    }
}

extension CGFloat {
    var float: Float {
        return Float(self)
    }
}
