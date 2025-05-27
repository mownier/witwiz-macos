import CoreGraphics

public struct Sprite {
    public let name: String
    public let cgImage: CGImage
    public let width: Int
    public let height: Int
    public var packedX: Int = 0
    public var packedY: Int = 0
}

public struct AtlasData: Encodable {
    public let textureFileName: String
    public var frames: [String: FrameData]
    public let metadata: Metadata
}

public struct FrameData: Encodable {
    public let frame: String // "{{x,y},{w,h}}"
    public let spriteSourceSize: String // "{w,h}" (original sprite size)
    public let sourceSize: String // "{w,h}" (actual content size if trimmed)
}

public struct Metadata: Encodable {
    public let format: Int
    public let size: String // "{w,h}" (atlas texture size)
    public let name: String
    public let version: String
}
