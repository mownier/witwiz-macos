import Foundation
import Cocoa
import SpriteKit
import WitWizCl
import GRPCCore
import GRPCNIOTransportHTTP2

class GameScene: SKScene, ObservableObject {
    var connectClientTask: Task<Void, Error>?
    var processGameStateTask: Task<Void, Error>?
    var joinGameOkTask: Task<Void, Error>?
    
    var yourID: Int32 = 0
    var levelID: Int32 = 0
    var worldOffsetX: CGFloat = 0
    var worldViewPort: Witwiz_ViewPort = Witwiz_ViewPort()
    var characterIds: [Int32] = []
    var playerIDs: Set<Int32> = []
    
    var playerInputContinuation: AsyncStream<Witwiz_PlayerInput>.Continuation?
    
    var moveUpKeyPressed: Bool = false
    var moveDownKeyPressed: Bool = false
    var moveRightKeyPressed: Bool = false
    var moveLeftKeyPressed: Bool = false
    var pauseGameKeyPressed: Bool = false
    
    @Published var clientOkay: Bool = false
    @Published var gameStarted: Bool = false
    @Published var selectCharacter: Bool = false
    @Published var gameOver: Bool = false
    @Published var gamePaused: Bool = false
    
    func setSize(_ value: CGSize) -> GameScene {
        scaleMode = .aspectFit
        if value == size {
            return self
        }
        size = value
        size.width = min(worldViewPort.width.cgFloat, size.width)
        size.height = min(worldViewPort.height.cgFloat, size.height)
        sendViewPort()
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
            input.playerID = yourID
            playerInputContinuation?.yield(input)
        case 0 where !moveLeftKeyPressed: // a
            moveLeftKeyPressed = true
            var input = Witwiz_PlayerInput()
            input.action = .moveLeftStart
            input.playerID = yourID
            playerInputContinuation?.yield(input)
        case 1 where !moveDownKeyPressed: // s
            moveDownKeyPressed = true
            var input = Witwiz_PlayerInput()
            input.action = .moveDownStart
            input.playerID = yourID
            playerInputContinuation?.yield(input)
        case 2 where !moveRightKeyPressed: // d
            moveRightKeyPressed = true
            var input = Witwiz_PlayerInput()
            input.action = .moveRightStart
            input.playerID = yourID
            playerInputContinuation?.yield(input)
        case 49 where !pauseGameKeyPressed: // space bar
            pauseGameKeyPressed = true
            var input = Witwiz_PlayerInput()
            input.action = .pauseResume
            input.playerID = yourID
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
            input.playerID = yourID
            playerInputContinuation?.yield(input)
        case 0 where moveLeftKeyPressed: // a
            moveLeftKeyPressed = false
            var input = Witwiz_PlayerInput()
            input.action = .moveLeftStop
            input.playerID = yourID
            playerInputContinuation?.yield(input)
        case 1 where moveDownKeyPressed: // s
            moveDownKeyPressed = false
            var input = Witwiz_PlayerInput()
            input.action = .moveDownStop
            input.playerID = yourID
            playerInputContinuation?.yield(input)
        case 2 where moveRightKeyPressed: // d
            moveRightKeyPressed = false
            var input = Witwiz_PlayerInput()
            input.action = .moveRightStop
            input.playerID = yourID
            playerInputContinuation?.yield(input)
        case 49 where pauseGameKeyPressed: // space bar
            pauseGameKeyPressed = false
        default:
            break
        }
    }
    
    func activateClient() {
        connectClientTask?.cancel()
        connectClientTask = Task {
            do {
                try await connectClient()
            } catch {
                updateClientOkay(false)
            }
            playerIDs.forEach { playerId in
                childNode(withName: "player\(playerId)")?.removeFromParent()
            }
            childNode(withName: "world_background")?.removeFromParent()
            joinGameOkTask?.cancel()
            processGameStateTask?.cancel()
            joinGameOkTask = nil
            processGameStateTask = nil
            connectClientTask = nil
            playerInputContinuation = nil
            worldViewPort = Witwiz_ViewPort()
            characterIds = []
            playerIDs = []
            updateGameStarted(false)
            updateSelectCharacter(false)
            updateGameOver(false)
            updateGamePaused(false)
        }
    }
    
    func deactivateClient() {
        connectClientTask?.cancel()
        connectClientTask = nil
    }
    
    func selectCharacter(_ characterID: Int32) {
        if yourID == 0 {
            return
        }
        var input = Witwiz_PlayerInput()
        input.playerID = yourID
        input.action = .selectCharacter
        input.characterID = characterID
        playerInputContinuation?.yield(input)
    }
    
    private func updateClientOkay(_ value: Bool) {
        if clientOkay == value {
            return
        }
        clientOkay = value
    }
    
    private func updateGameStarted(_ value: Bool) {
        if gameStarted == value {
            return
        }
        gameStarted = value
    }
    
    private func updateSelectCharacter(_ value: Bool) {
        if selectCharacter == value {
            return
        }
        selectCharacter = value
    }
    
    private func updateGameOver(_ value: Bool) {
        if gameOver == value {
            return
        }
        gameOver = value
    }
    
    private func updateGamePaused(_ value: Bool) {
        if gamePaused == value {
            return
        }
        gamePaused = value
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
                updateClientOkay(ok)
                break
            }
        }
        let client = await WitWizClient().host("192.168.1.6").port(40041).useTLS(false)
        try await client.joinGame(piStream, gsContinuation, okContinuation)
    }
    
    private func processGameState(_ state: Witwiz_GameStateUpdate) {
        if state.isInitial {
            state.players.forEach { player in
                yourID = player.playerID
                sendViewPort()
            }
            return
        }
        updateGameStarted(state.gameStarted)
        updateGameOver(state.gameOver)
        updateGamePaused(state.gamePaused)
        worldOffsetX = state.worldOffset.x.cgFloat
        worldViewPort = state.worldViewPort
        if levelID != state.levelID {
            childNode(withName: "world_background")?.removeFromParent()
        }
        levelID = state.levelID
        characterIds = state.characterIds
        if !state.gameStarted {
            if let player = state.players.withID(yourID) {
                updateSelectCharacter(!characterIds.contains(player.characterID))
            }
            return
        }
        if state.gameOver {
            childNode(withName: "world_background")?.removeFromParent()
        } else if let node = childNode(withName: "world_background") as? SKSpriteNode {
            node.position.x = worldOffsetX * -1
        } else {
            size.width = min(worldViewPort.width.cgFloat, size.width)
            size.height = min(worldViewPort.height.cgFloat, size.height)
            createGameLevel()
        }
        state.players.forEach { player in
            if state.gameOver {
                childNode(withName: "player\(player.playerID)")?.removeFromParent()
                return
            }
            if player.playerID == yourID {
                updateSelectCharacter(!characterIds.contains(player.characterID))
            }
            if let node = childNode(withName: "player\(player.playerID)") as? PlayerSpriteNode {
                let pos = CGPoint(x: player.position.x.cgFloat, y: player.position.y.cgFloat)
                node.position = pos
                node.updateCharacterID(player.characterID)
            } else {
                let size = CGSize(width: player.boundingBox.width.cgFloat, height: player.boundingBox.height.cgFloat)
                let position = CGPoint(x: player.position.x.cgFloat, y: player.position.y.cgFloat)
                let node = PlayerSpriteNode.make(player.characterID)
                node.size = size
                node.position = position
                node.name = "player\(player.playerID)"
                addChild(node)
                playerIDs.insert(player.playerID)
            }
        }
        playerIDs.forEach { playerID in
            if !state.players.contains(where: { $0.playerID == playerID }) {
                childNode(withName: "player\(playerID)")?.removeFromParent()
            }
        }
    }
    
    private func sendViewPort() {
        if yourID == 0 {
            return
        }
        var input = Witwiz_PlayerInput()
        input.playerID = yourID
        input.action = .reportViewport
        input.viewPort = Witwiz_ViewPort()
        input.viewPort.width = size.width.float
        input.viewPort.height = size.height.float
        playerInputContinuation?.yield(input)
    }
    
    private func createGameLevel() {
        if levelID == 0 {
            return
        }
        let size = CGSize(width: worldViewPort.width.cgFloat, height: worldViewPort.height.cgFloat)
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

extension Array<Witwiz_PlayerState> {
    func withID(_ playerID: Int32) -> Witwiz_PlayerState? {
        return first { $0.playerID == playerID }
    }
}

class PlayerSpriteNode: SKSpriteNode {
    private var characterID: Int32 = 0
    
    func updateCharacterID(_ value: Int32) {
        if value == characterID {
            return
        }
        characterID = value
        switch characterID {
        case 1: color = .blue
        case 2: color = .orange
        case 3: color = .red
        case 4: color = .magenta
        case 5: color = .cyan
        default: color = .clear
        }
    }
    
    static func make(_ characterID: Int32) -> PlayerSpriteNode {
        let node = PlayerSpriteNode()
        node.anchorPoint.x = 0
        node.anchorPoint.y = 0
        node.updateCharacterID(characterID)
        return node
    }
}
