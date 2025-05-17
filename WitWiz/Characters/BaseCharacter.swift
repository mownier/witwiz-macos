import SpriteKit

let characterTextureAtlas = SKTextureAtlas(named: "Character")

class BaseCharacter: SKSpriteNode {
    var characterID: Int32 = 0
    
    convenience init(characterID: Int32) {
        let texture = characterTextureAtlas.textureNamed("base_charac_\(characterID)")
        self.init(texture: texture)
        self.characterID = characterID
    }
}
