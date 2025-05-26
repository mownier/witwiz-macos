import Foundation
import Cocoa
import SpriteKit
import WitWizCl
import GRPCCore
import GRPCNIOTransportHTTP2

class GameScene: SKScene, ObservableObject {
    let tileSet = SKTileSet(named: "Level Tile Set")!
    let tileSize: CGFloat = 32
    
    var connectClientTask: Task<Void, Error>?
    var processGameStateTask: Task<Void, Error>?
    var joinGameOkTask: Task<Void, Error>?
    
    var yourID: Int32 = 0
    var levelID: Int32 = 0
    var characterIds: [Int32] = []
    var playerIDs: Set<Int32> = []
    var tileChunks: [Witwiz_TileChunk] = []
    
    var playerInputContinuation: AsyncStream<Witwiz_PlayerInput>.Continuation?
    
    var moveUpKeyPressed: Bool = false
    var moveDownKeyPressed: Bool = false
    var moveRightKeyPressed: Bool = false
    var moveLeftKeyPressed: Bool = false
    var pauseGameKeyPressed: Bool = false
    
    var gameWorld: SKNode!
    var gameCamera: SKCameraNode!
    var tileMap: SKTileMapNode!
    
    @Published var clientOkay: Bool = false
    @Published var gameStarted: Bool = false
    @Published var selectCharacter: Bool = false
    @Published var gameOver: Bool = false
    @Published var gamePaused: Bool = false
    
    func setSize(_ value: CGSize) -> GameScene {
        size = value
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
            joinGameOkTask?.cancel()
            processGameStateTask?.cancel()
            joinGameOkTask = nil
            processGameStateTask = nil
            connectClientTask = nil
            playerInputContinuation = nil
            characterIds = []
            playerIDs = []
            tileChunks = []
            yourID = 0
            levelID = 0
            tileMap?.removeAllChildren()
            tileMap?.removeFromParent()
            tileMap = nil
            gameWorld?.removeAllChildren()
            gameWorld?.removeFromParent()
            gameWorld = nil
            gameCamera?.removeFromParent()
            gameCamera = nil
            camera = nil
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
        let client = await WitWizClient().host("localhost").port(40041).useTLS(false)
        try await client.joinGame(piStream, gsContinuation, okContinuation)
    }
    
    private func processGameState(_ state: Witwiz_GameStateUpdate) {
        if state.isInitial {
            state.players.forEach { player in
                yourID = player.id
            }
            if !state.tileChunks.isEmpty {
                tileChunks = state.tileChunks
            }
            return
        }
        updateGameStarted(state.gameStarted)
        updateGameOver(state.gameOver)
        updateGamePaused(state.gamePaused)
        characterIds = state.characterIds
        if !state.gameStarted {
            if let player = state.players.withID(yourID) {
                updateSelectCharacter(!characterIds.contains(player.characterID))
            }
            return
        }
        if state.gameOver {
            size = .zero
            backgroundColor = .gray
            levelID = 0
            gameWorld?.removeAllChildren()
            gameWorld?.removeFromParent()
            gameWorld = nil
            gameCamera?.removeFromParent()
            gameCamera = nil
            camera = nil
            return
        }
        if state.hasNextLevelPortal {
            createNextLevelPortal(state.nextLevelPortal)
        }
        if state.levelID != 0 && levelID != state.levelID {
            levelID = state.levelID
            createWorld(state.levelSize, state.levelPosition, state.levelEdges)
        }
        createObstacles(state.obstacles)
        state.players.forEach { player in
            if player.id == yourID {
                updateSelectCharacter(!characterIds.contains(player.characterID))
            }
            if let node = gameWorld?.childNode(withName: "player\(player.id)") as? BaseCharacter {
                if node.characterID == player.characterID {
                    let pos = CGPoint(x: player.position.x.cgFloat, y: player.position.y.cgFloat)
                    node.position = pos
                } else if characterIds.contains(player.characterID) {
                    node.removeFromParent()
                    createPlayer(player)
                }
            } else if characterIds.contains(player.characterID) {
                createPlayer(player)
            }
            playerIDs.insert(player.id)
        }
        if !state.players.isEmpty {
            updateWorld(state.levelPosition, state.levelEdges)
        }
        let toRemovePlayers = playerIDs.compactMap { playerID -> Int32? in
            if !state.players.contains(where: { $0.id == playerID }) {
                gameWorld?.childNode(withName: "player\(playerID)")?.removeFromParent()
                return playerID
            }
            return nil
        }
        toRemovePlayers.forEach { playerIDs.remove($0) }
    }
    
    private func updateWorld(_ levelPoint: Witwiz_Point, _ levelEdges: [Witwiz_LevelEdgeState]) {
        for levelEdge in levelEdges {
            if let node = gameWorld?.childNode(withName: "levelEdge\(levelEdge.id)") {
                node.position = CGPoint(x: levelEdge.position.x.cgFloat, y: levelEdge.position.y.cgFloat)
            }
        }
        let position = CGPoint(x: levelPoint.x.cgFloat * -1, y: levelPoint.y.cgFloat * -1)
        let rect = CGRect(origin: position, size: size)
        gameCamera?.position = CGPoint(x: rect.midX, y: rect.midY)
    }
    
    private func createPlayer(_ player: Witwiz_PlayerState) {
        let position = CGPoint(x: player.position.x.cgFloat, y: player.position.y.cgFloat)
        let node: BaseCharacter = BaseCharacter(characterID: player.characterID)
        node.position = position
        node.name = "player\(player.id)"
        node.characterID = player.characterID
        gameWorld?.addChild(node)
    }
    
    private func createWorld(_ levelSize: Witwiz_Size, _ levelPoint: Witwiz_Point, _ levelEdges: [Witwiz_LevelEdgeState]) {
        tileMap?.removeAllChildren()
        tileMap?.removeFromParent()
        tileMap = nil
        
        gameWorld?.removeAllChildren()
        gameWorld?.removeFromParent()
        gameWorld = nil
        
        gameCamera?.removeFromParent()
        gameCamera = nil
        camera = nil
        
        switch levelID {
        case 1: backgroundColor = .systemBlue
        case 2: backgroundColor = .systemPink
        default: return
        }
        
        let parentNode = SKNode()
        
        // Tile map
        tileMap = SKTileMapNode()
        tileMap.anchorPoint = CGPoint(x: 0, y: 0)
        tileMap.tileSet = tileSet
        tileMap.tileSize = CGSize(width: tileSize, height: tileSize)
        tileMap.numberOfColumns = Int(levelSize.width.cgFloat / tileSize)
        tileMap.numberOfRows = Int(levelSize.height.cgFloat / tileSize)
        parentNode.addChild(tileMap)
        
        for tileChunk in tileChunks {
            for tile in tileChunk.tiles {
                let tileGroup = tileSet.tileGroups.first(where: { $0.name == "Tile \(tile.id)" })!
                tileMap.setTileGroup(tileGroup, forColumn: Int(tile.col), row: Int(tile.row))
            }
        }
        tileChunks.removeAll()
        
        // Level edges
        for levelEdge in levelEdges {
            let node = SKSpriteNode()
            node.name = "levelEdge\(levelEdge.id)"
            node.size = CGSize(width: levelEdge.size.width.cgFloat, height: levelEdge.size.height.cgFloat)
            node.position = CGPoint(x: levelEdge.position.x.cgFloat, y: levelEdge.position.y.cgFloat)
            node.color = .green.withAlphaComponent(0.0)
            parentNode.addChild(node)
        }
        
        // Set game world
        gameWorld = parentNode
        addChild(parentNode)
        
        // Set camera
        let cam = SKCameraNode()
        let position = CGPoint(x: levelPoint.x.cgFloat * -1, y: levelPoint.y.cgFloat * -1)
        let rect = CGRect(origin: position, size: size)
        cam.position = CGPoint(x: rect.midX, y: rect.midY)
        gameCamera = cam
        camera = cam
        addChild(cam)
    }
    
    private func createNextLevelPortal(_ portal: Witwiz_NextLevelPortalState) {
        if gameWorld?.childNode(withName: "next_level_portal") != nil {
            return
        }
        let position = CGPoint(x: portal.position.x.cgFloat, y: portal.position.y.cgFloat)
        let size = CGSize(width: portal.size.width.cgFloat, height: portal.size.height.cgFloat)
        let node = SKSpriteNode()
        node.name = "next_level_portal"
        node.color = .cyan.withAlphaComponent(0.75)
        node.position = position
        node.size = size
        gameWorld?.addChild(node)
    }
    
    private func createObstacles(_ obstacles: [Witwiz_ObstacleState]) {
        for obstacle in obstacles {
            if let node = gameWorld?.childNode(withName: "obstacle\(obstacle.id)") {
                node.position = CGPoint(x: obstacle.position.x.cgFloat, y: obstacle.position.y.cgFloat)
            } else {
                let node = SKSpriteNode()
                switch obstacle.id {
                case 1:
                    node.color = .magenta.withAlphaComponent(0.5)
                default:
                    break
                }
                node.name = "obstacle\(obstacle.id)"
                node.position = CGPoint(x: obstacle.position.x.cgFloat, y: obstacle.position.y.cgFloat)
                node.size = CGSize(width: obstacle.size.width.cgFloat, height: obstacle.size.height.cgFloat)
                gameWorld?.addChild(node)
            }
        }
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

extension Array<Witwiz_PlayerState> {
    func withID(_ playerID: Int32) -> Witwiz_PlayerState? {
        return first { $0.id == playerID }
    }
}
