import Foundation
import CoreGraphics
import AppKit

public class TexturePacker {
    public init() {}

    public func pack(inputImageURLs: [URL], padding: Int = 2, maxAtlasSize: Int = 4096) throws -> (CGImage, AtlasData) {
        var sprites: [Sprite] = []

        for url in inputImageURLs {
            let cgImage = try ImageUtilities.loadCGImage(from: url)
            sprites.append(Sprite(name: url.deletingPathExtension().lastPathComponent,
                                  cgImage: cgImage,
                                  width: cgImage.width,
                                  height: cgImage.height))
        }

        // Sort sprites (larger ones first often helps packing efficiency)
        sprites.sort { ($0.width * $0.height) > ($1.width * $1.height) }

        // --- Simplified Packing Algorithm (as discussed, replace with MaxRects/Guillotine for efficiency) ---
        var currentX: Int = 0
        var currentY: Int = 0
        var maxHeightInCurrentRow: Int = 0
        var atlasWidth: Int = 0
        var atlasHeight: Int = 0

        for i in 0..<sprites.count {
            if currentX + sprites[i].width + padding > maxAtlasSize {
                currentX = 0
                currentY += maxHeightInCurrentRow + padding
                maxHeightInCurrentRow = 0
            }

            sprites[i].packedX = currentX
            sprites[i].packedY = currentY

            currentX += sprites[i].width + padding
            maxHeightInCurrentRow = max(maxHeightInCurrentRow, sprites[i].height)

            atlasWidth = max(atlasWidth, currentX)
            atlasHeight = max(atlasHeight, currentY + maxHeightInCurrentRow)
        }

        // --- Create the Texture Atlas Image ---
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil,
                                      width: atlasWidth,
                                      height: atlasHeight,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 4 * atlasWidth,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ImageError.createCGContextFailed
        }

        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0)) // Transparent background
        context.fill(CGRect(x: 0, y: 0, width: atlasWidth, height: atlasHeight))

        for sprite in sprites {
            let rect = CGRect(x: sprite.packedX, y: sprite.packedY, width: sprite.width, height: sprite.height)
            context.draw(sprite.cgImage, in: rect)
        }

        guard let finalCGImage = context.makeImage() else {
            throw ImageError.createCGImageFailed
        }

        // --- Generate Atlas Data ---
        var framesData: [String: FrameData] = [:]
        for sprite in sprites {
            let frameRectString = String(format: "{{%d,%d},{%d,%d}}", sprite.packedX, sprite.packedY, sprite.width, sprite.height)
            let sourceSizeString = String(format: "{%d,%d}", sprite.width, sprite.height)
            framesData[sprite.name] = FrameData(frame: frameRectString,
                                                spriteSourceSize: sourceSizeString,
                                                sourceSize: sourceSizeString)
        }

        let metadata = Metadata(format: 2, // Standard format for plist atlases
                                size: String(format: "{%d,%d}", atlasWidth, atlasHeight),
                                name: "GeneratedAtlas", // Default name, can be customized
                                version: "1.0")

        let atlasData = AtlasData(textureFileName: "atlas.png", frames: framesData, metadata: metadata) // Customize filename

        return (finalCGImage, atlasData)
    }
}
