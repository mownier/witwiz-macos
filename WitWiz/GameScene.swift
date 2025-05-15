import Foundation
import Cocoa
import SpriteKit
import WitWizCl
import GRPCCore
import GRPCNIOTransportHTTP2

class GameScene: SKScene, ObservableObject {
    var yourId: Int32?
    var levelID: Int32?
    var connectClientTask: Task<Void, Error>?
    var processGameStateTask: Task<Void, Error>?
    var joinGameOkTask: Task<Void, Error>?
    var worldViewPort: Witwiz_ViewPort?
    var characterIds: [Int32] = []
    var playerIds: Set<Int32> = []
    
    var playerInputContinuation: AsyncStream<Witwiz_PlayerInput>.Continuation?
    
    var moveUpKeyPressed: Bool = false
    var moveDownKeyPressed: Bool = false
    var moveRightKeyPressed: Bool = false
    var moveLeftKeyPressed: Bool = false
    
    var worldOffsetX: CGFloat = 0
    
    @Published var clientOkay: Bool = false
    @Published var gameStarted: Bool = false
    @Published var selectCharacter: Bool = false
    @Published var gameOver: Bool = false
    
    func setSize(_ value: CGSize) -> GameScene {
        scaleMode = .aspectFit
        if value != size {
            size = value
            if let viewPort = worldViewPort {
                size.width = min(viewPort.width.cgFloat, size.width)
                size.height = min(viewPort.height.cgFloat, size.height)
            }
            if let playerID = yourId {
                sendViewPort(playerID)
            }
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
        joinGameOkTask?.cancel()
        processGameStateTask?.cancel()
        connectClientTask?.cancel()
        connectClientTask = Task {
            do {
                try await connectClient()
            } catch {
                clientOkay = false
            }
            joinGameOkTask?.cancel()
            processGameStateTask?.cancel()
            processGameStateTask = nil
            joinGameOkTask = nil
            if let yourId = yourId {
                childNode(withName: "player\(yourId)")?.removeFromParent()
                childNode(withName: "world_background")?.removeFromParent()
            }
            yourId = nil
            connectClientTask = nil
            worldViewPort = nil
            playerInputContinuation = nil
            characterIds = []
            gameStarted = false
            selectCharacter = false
            playerIds = []
        }
    }
    
    func deactivateClient() {
        joinGameOkTask?.cancel()
        processGameStateTask?.cancel()
        connectClientTask?.cancel()
        joinGameOkTask = nil
        processGameStateTask = nil
        connectClientTask = nil
    }
    
    func triggerGameStart() {
        guard let playerID = yourId else {
            return
        }
        var input = Witwiz_PlayerInput()
        input.playerID = playerID
        input.action = .startGame
        playerInputContinuation?.yield(input)
    }
    
    func selectCharacter(_ characterID: Int32) {
        guard let playerID = yourId else {
            return
        }
        var input = Witwiz_PlayerInput()
        input.playerID = playerID
        input.action = .selectCharacter
        input.characterID = characterID
        playerInputContinuation?.yield(input)
    }
    
    private func connectClient() async throws {
        let (gsStream, gsContinuation) = AsyncStream<Witwiz_GameStateUpdate>.makeStream()
        let (piStream, piContinuation) = AsyncStream<Witwiz_PlayerInput>.makeStream()
        let (okStream, okContinuation) = AsyncStream<Bool>.makeStream()
        playerInputContinuation = piContinuation
        processGameStateTask?.cancel()
        processGameStateTask = Task {
            for try await state in gsStream {
                if Task.isCancelled {
                    break
                }
                processGameState(state)
            }
        }
        joinGameOkTask?.cancel()
        joinGameOkTask = Task {
            for try await ok in okStream {
                if Task.isCancelled {
                    break
                }
                clientOkay = ok
                break
            }
        }
        let client = await WitWizClient().host("192.168.1.6").port(40041).useTLS(false)
        try await client.joinGame(piStream, gsContinuation, okContinuation)
    }
    
    private func processGameState(_ state: Witwiz_GameStateUpdate) {
        if gameStarted != state.gameStarted {
            gameStarted = state.gameStarted
        }
        if gameOver != state.gameOver {
            gameOver = state.gameOver
        }
        if state.hasWorldOffset {
            worldOffsetX = state.worldOffset.x.cgFloat
        }
        if yourId == nil && state.yourPlayerID != 0 {
            yourId = state.yourPlayerID
            sendViewPort(state.yourPlayerID)
        }
        if state.hasWorldViewPort {
            worldViewPort = state.worldViewPort
        }
        if state.levelID != 0 && levelID != state.levelID {
            levelID = state.levelID
            childNode(withName: "world_background")?.removeFromParent()
        }
        if characterIds.isEmpty {
            characterIds = state.characterIds
        }
        if !gameStarted {
            state.players.forEach { player in
                if player.playerID == yourId {
                    if player.characterID < 1 {
                        if !selectCharacter {
                            selectCharacter = true
                        }
                    } else {
                        if selectCharacter {
                            selectCharacter = false
                        }
                    }
                }
            }
            return
        }
        if let viewPort = worldViewPort {
            if let node = childNode(withName: "world_background") as? SKSpriteNode {
                if state.gameOver {
                    node.removeFromParent()
                } else {
                    node.position.x = worldOffsetX * -1
                }
            } else if !state.gameOver {
                size.width = min(viewPort.width.cgFloat, size.width)
                size.height = min(viewPort.height.cgFloat, size.height)
                let worldSize = CGSize(width: viewPort.width.cgFloat, height: viewPort.height.cgFloat)
                if let levelID = levelID {
                    createGameLevel(levelID: levelID, size: worldSize)
                }
            }
        }
        state.players.forEach { player in
            let needCharacterSelection: Bool
            if player.characterID < 1 {
                needCharacterSelection = true
            } else {
                needCharacterSelection = false
            }
            if let node = childNode(withName: "player\(player.playerID)") as? SKSpriteNode, !needCharacterSelection {
                if state.gameOver {
                    node.removeFromParent()
                } else {
                    let pos = CGPoint(x: player.position.x.cgFloat, y: player.position.y.cgFloat)
                    node.position = pos
                    switch player.characterID {
                    case 1: node.color = .blue
                    case 2: node.color = .orange
                    case 3: node.color = .red
                    case 4: node.color = .magenta
                    case 5: node.color = .cyan
                    default: node.color = .black
                    }
                }
            } else if !state.gameOver {
                if player.playerID == yourId {
                    if needCharacterSelection != selectCharacter {
                        selectCharacter = needCharacterSelection
                    }
                }
                if !needCharacterSelection {
                    let size = CGSize(width: player.boundingBox.width.cgFloat, height: player.boundingBox.height.cgFloat)
                    let position = CGPoint(x: player.position.x.cgFloat, y: player.position.y.cgFloat)
                    let node = SKSpriteNode.make()
                    node.size = size
                    node.position = position
                    node.name = "player\(player.playerID)"
                    switch player.characterID {
                    case 1: node.color = .blue
                    case 2: node.color = .orange
                    case 3: node.color = .red
                    case 4: node.color = .magenta
                    case 5: node.color = .cyan
                    default: node.color = .black
                    }
                    addChild(node)
                    playerIds.insert(player.playerID)
                }
            }
        }
        playerIds.forEach { pId in
            if !state.players.contains(where: { $0.playerID == pId }) {
                childNode(withName: "player\(pId)")?.removeFromParent()
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
    
    private func createGameLevel(levelID: Int32, size: CGSize) {
        let gameLevel: SKSpriteNode
        switch levelID {
        case 1: gameLevel = GameLevel1.make(size: size)
        case 2: gameLevel = GameLevel2.make(size: size)
        default:
            return
        }
        gameLevel.name = "world_background"
        gameLevel.zPosition = -1
        addChild(gameLevel)
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

extension SKSpriteNode {
    static func make() -> SKSpriteNode {
        let node = SKSpriteNode()
        node.anchorPoint.x = 0
        node.anchorPoint.y = 0
        return node
    }
}
