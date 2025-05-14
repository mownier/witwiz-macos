import SpriteKit

class GameLevel1: SKSpriteNode {
    
    static func make(size: CGSize) -> GameLevel1 {
        let parentNode = GameLevel1()
        parentNode.anchorPoint.x = 0
        parentNode.anchorPoint.y = 0
        parentNode.color = .red
        parentNode.size = size
        parentNode.position = CGPoint(x: 0, y: 0)
        let childCount = 100
        let childWidth = size.width / 100
        for i in 0..<childCount {
            let childNode = SKSpriteNode.make()
            childNode.size = CGSize(width: childWidth, height: size.height)
            childNode.position.x = CGFloat(i) * childWidth
            childNode.color = i % 2 == 0 ? .lightGray : .gray
            parentNode.addChild(childNode)
        }
        return parentNode
    }
}
