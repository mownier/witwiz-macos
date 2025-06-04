import Foundation
import Cocoa
import SpriteKit
import WitWizCl
import GRPCCore
import GRPCNIOTransportHTTP2
import AppKit

class GameScene: SKScene, ObservableObject {
    let tileSize: CGFloat = 32
    let tileChunkSize: CGFloat = 16
    
    var connectClientTask: Task<Void, Error>?
    var processGameStateTask: Task<Void, Error>?
    var joinGameOkTask: Task<Void, Error>?
    
    var yourID: Int32 = 0
    var levelID: Int32 = 0
    var characterIds: [Int32] = []
    var playerIDs: Set<Int32> = []
    var allTileChunks: [String: Bool] = [:]
    
    var playerInputContinuation: AsyncStream<Witwiz_PlayerInput>.Continuation?
    
    var moveUpKeyPressed: Bool = false
    var moveDownKeyPressed: Bool = false
    var moveRightKeyPressed: Bool = false
    var moveLeftKeyPressed: Bool = false
    var pauseGameKeyPressed: Bool = false
    var shootKeyPressed: Bool = false
    
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
        case 38 where !shootKeyPressed:  // j
            shootKeyPressed = true
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
        case 38 where shootKeyPressed: // j
            shootKeyPressed = false
            var input = Witwiz_PlayerInput()
            input.action = .shoot
            input.playerID = yourID
            playerInputContinuation?.yield(input)
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
            allTileChunks = [:]
            return
        }
        if state.hasNextLevelPortal {
            createNextLevelPortal(state.nextLevelPortal)
        }
        if state.levelID != 0 && levelID != state.levelID {
            levelID = state.levelID
            createWorld(state.levelSize, state.levelPosition, state.levelEdges, state.tileChunks)
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
            updateWorld(state.levelPosition, state.levelEdges, state.tileChunks)
        }
        let toRemovePlayers = playerIDs.compactMap { playerID -> Int32? in
            if !state.players.contains(where: { $0.id == playerID }) {
                gameWorld?.childNode(withName: "player\(playerID)")?.removeFromParent()
                return playerID
            }
            return nil
        }
        toRemovePlayers.forEach { playerIDs.remove($0) }
        state.friendlyBullets.forEach { bullet in
            if !bullet.active {
                gameWorld?.childNode(withName: "friendly_bullet\(bullet.id)")?.removeFromParent()
                return
            }
            if let node = gameWorld?.childNode(withName: "friendly_bullet\(bullet.id)") {
                node.position = CGPoint(x: bullet.position.x.cgFloat, y: bullet.position.y.cgFloat)
            } else {
                let node = SKShapeNode(rectOf: CGSize(width: bullet.size.width.cgFloat, height: bullet.size.height.cgFloat))
                node.fillColor = .red
                node.name = "friendly_bullet\(bullet.id)"
                node.position = CGPoint(x: bullet.position.x.cgFloat, y: bullet.position.y.cgFloat)
                node.strokeColor = .clear
                gameWorld?.addChild(node)
            }
        }
    }
    
    private func updateWorld(
        _ levelPoint: Witwiz_Point,
        _ levelEdges: [Witwiz_LevelEdgeState],
        _ tileChunks: [Witwiz_TileChunk]
    ) {
        for levelEdge in levelEdges {
            if let node = gameWorld?.childNode(withName: "levelEdge\(levelEdge.id)") {
                node.position = CGPoint(x: levelEdge.position.x.cgFloat, y: levelEdge.position.y.cgFloat)
            }
        }
        let position = CGPoint(x: levelPoint.x.cgFloat * -1, y: levelPoint.y.cgFloat * -1)
        let rect = CGRect(origin: position, size: size)
        gameCamera?.position = CGPoint(x: rect.midX, y: rect.midY)
        
        for tileChunk in tileChunks {
            if tileChunk.row >= tileMap.numberOfRows ||
                tileChunk.col >= tileMap.numberOfColumns ||
                tileChunk.tiles.isEmpty {
                continue
            }
            let name = "\(tileChunk.row),\(tileChunk.col)"
            if allTileChunks[name] == true {
                continue
            }
            allTileChunks[name] = true
            for tile in tileChunk.tiles {
                if tile.id == 0 {
                    tileMap.setTileGroup(nil, forColumn: Int(tile.col), row: tileMap.numberOfRows - Int(tile.row) - 1)
                    continue
                }
                let tileGroup = tileMap.tileSet.tileGroups.first(where: { $0.name == "tile_\(tile.id)" })!
                tileMap.setTileGroup(tileGroup, forColumn: Int(tile.col), row: tileMap.numberOfRows - Int(tile.row) - 1)
            }
        }
        
        if allTileChunks.reduce(true, { $0 && $1.value }) {
            return
        }
        
        let minX = levelPoint.x.cgFloat * -1
        let maxX = minX + size.width
        let minY = levelPoint.y.cgFloat * -1
        let maxY = minY + size.height
        
        let minTileCol = floor(minX / tileSize)
        let maxTileCol = ceil(maxX / tileSize)
        let minTileRow = floor(minY / tileSize)
        let maxTileRow = ceil(maxY / tileSize)
        
        let minChunkCol = Int(floor(minTileCol / tileChunkSize))
        let maxChunkCol = Int(floor(maxTileCol / tileChunkSize))
        let minChunkRow = Int(floor(minTileRow / tileChunkSize))
        let maxChunkRow = Int(floor(maxTileRow / tileChunkSize))
        
        var tileChunksToLoad: [Witwiz_TileChunkToLoad] = []
        
        for chunkRow in minChunkRow...maxChunkRow {
            for chunkCol in minChunkCol...maxChunkCol {
                if chunkRow >= tileMap.numberOfRows || chunkCol >= tileMap.numberOfColumns {
                    continue
                }
                let name = "\(chunkRow),\(chunkCol)"
                let loaded = allTileChunks[name] ?? false
                if !loaded {
                    var tileChunkToLoad = Witwiz_TileChunkToLoad()
                    tileChunkToLoad.col = Int32(chunkCol)
                    tileChunkToLoad.row = Int32(chunkRow)
                    tileChunksToLoad.append(tileChunkToLoad)
                }
            }
        }
        
        if tileChunksToLoad.isEmpty {
            return
        }
        
        var input = Witwiz_PlayerInput()
        input.playerID = yourID
        input.action = .tileChunksRequest
        input.tileChunksToLoad = tileChunksToLoad
        playerInputContinuation?.yield(input)
    }
    
    private func createPlayer(_ player: Witwiz_PlayerState) {
        let position = CGPoint(x: player.position.x.cgFloat, y: player.position.y.cgFloat)
        let node: BaseCharacter = BaseCharacter(characterID: player.characterID)
        node.position = position
        node.name = "player\(player.id)"
        node.characterID = player.characterID
        gameWorld?.addChild(node)
    }
    
    private func createTileSet() -> SKTileSet {
        let atlasName: String
        switch levelID {
        case 3: atlasName = "level_3_atlas"
        case 4: atlasName = "level_4_atlas"
        default: atlasName = "level_default_atlas"
        }
        
        // 1. Load the individual SKTexture objects from your custom atlas data
        let customTextures = loadCustomAtlasTextures(imageAssetName: atlasName, plistFileName: atlasName)!

        // 2. Create SKTileDefinition objects
        var tileDefinitions: [String: SKTileDefinition] = [:]

        for (textureName, texture) in customTextures {
            texture.filteringMode = .nearest // Important for pixel art
            let tileDef = SKTileDefinition(texture: texture)
            tileDef.size = CGSize(width: tileSize, height: tileSize)
            tileDefinitions[textureName] = tileDef
        }

        // 3. Create SKTileGroup objects
        var tileGroups: [String: SKTileGroup] = [:]
        for (name, definition) in tileDefinitions {
            let group = SKTileGroup(tileDefinition: definition)
            group.name = name
            tileGroups[name] = group
        }

        // 4. Assemble an SKTileSet from your groups
        let allTileGroups = Array(tileGroups.values)
        let tileSet = SKTileSet(tileGroups: allTileGroups)
        tileSet.name = "Tile set for \(atlasName)"
        
        return tileSet
    }
    
    private func createWorld(
        _ levelSize: Witwiz_Size,
        _ levelPoint: Witwiz_Point,
        _ levelEdges: [Witwiz_LevelEdgeState],
        _ tileChunks: [Witwiz_TileChunk]
    ) {
        tileMap?.removeAllChildren()
        tileMap?.removeFromParent()
        tileMap = nil
        
        gameWorld?.removeAllChildren()
        gameWorld?.removeFromParent()
        gameWorld = nil
        
        gameCamera?.removeFromParent()
        gameCamera = nil
        camera = nil
        
        allTileChunks = [:]
        
        switch levelID {
        case 1: backgroundColor = .systemBlue
        case 2: backgroundColor = .systemPink
        case 3: backgroundColor = .systemMint
        case 4: backgroundColor = .systemTeal
        default: return
        }
        
        let parentNode = SKNode()
        
        // Tile map
        let tileSet = createTileSet()
        tileMap = SKTileMapNode()
        tileMap.anchorPoint = CGPoint(x: 0, y: 0)
        tileMap.tileSize = CGSize(width: tileSize, height: tileSize)
        tileMap.numberOfColumns = Int(levelSize.width.cgFloat / tileSize)
        tileMap.numberOfRows = Int(levelSize.height.cgFloat / tileSize)
        tileMap.tileSet = tileSet
        parentNode.addChild(tileMap)
        
        let tileChunkRowCount: Int = tileMap.numberOfRows / Int(tileChunkSize)
        let tileChunkColCount: Int = tileMap.numberOfColumns / Int(tileChunkSize)
        
        for chunkRow in 0..<tileChunkRowCount {
            for chunkCol in 0..<tileChunkColCount {
                let name = "\(chunkRow),\(chunkCol)"
                allTileChunks[name] = false
            }
        }
        
        for tileChunk in tileChunks {
            if tileChunk.row >= tileMap.numberOfRows ||
                tileChunk.col >= tileMap.numberOfColumns ||
                tileChunk.tiles.isEmpty {
                continue
            }
            let name = "\(tileChunk.row),\(tileChunk.col)"
            allTileChunks[name] = true
            for tile in tileChunk.tiles {
                if tile.id == 0 {
                    continue
                }
                let tileGroup = tileSet.tileGroups.first(where: { $0.name == "tile_\(tile.id)" })!
                tileMap.setTileGroup(tileGroup, forColumn: Int(tile.col), row: tileMap.numberOfRows - Int(tile.row) - 1)
            }
        }
        
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
    
    private func loadCustomAtlasTextures(imageAssetName: String, plistFileName: String) -> [String: SKTexture]? {
        // Load the main atlas image from Assets.xcassets
        let nsImage = NSImage(named: imageAssetName)!
        let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        
        // Load and parse the plist data
        let plistPath = Bundle.main.path(forResource: plistFileName, ofType: "plist")!
        let plistData = try! Data(contentsOf: URL(fileURLWithPath: plistPath))
        let dictionary = try! PropertyListSerialization.propertyList(from: plistData, format: nil) as! [String: Any]
     
        var textures: [String: SKTexture] = [:]

        // Extract frame data and create textures
        if let framesDict = dictionary["frames"] as? [String: [String: Any]] {
            for (name, frameInfo) in framesDict {
                if let frameString = frameInfo["frame"] as? String,
                   let rect = CGRect(string: frameString) {
                    if let croppedCGImage = cgImage.cropping(to: rect) {
                        let texture = SKTexture(cgImage: croppedCGImage)
                        textures[name] = texture
                    }
                }
            }
        }
        
        return textures.isEmpty ? nil : textures
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

// Helper extension to parse CGRect from string, if your plist uses "{{x,y},{w,h}}"
// This extension is cross-platform.
extension CGRect {
    init?(string: String) {
        let cleanString = string.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
        let components = cleanString.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }

        guard components.count == 4,
              let x = components[0],
              let y = components[1],
              let width = components[2],
              let height = components[3] else {
            return nil
        }
        self.init(x: x, y: y, width: width, height: height)
    }
}
