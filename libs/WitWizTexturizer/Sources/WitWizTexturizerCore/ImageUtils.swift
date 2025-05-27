import Foundation
import CoreGraphics
import AppKit

public enum ImageError: Error, LocalizedError {
    case loadImageFailed(URL)
    case createCGContextFailed
    case createCGImageFailed
    case createPNGDataFailed
    case tiffRepresentationFailed
    case imageTooSmallForTileSize(imageSize: String, tileSize: Int)
    case imageDimensionNotMultipleOfTileSize(dimension: String, value: Int, tileSize: Int)


    public var errorDescription: String? {
        switch self {
        case .loadImageFailed(let url): return "Failed to load image from URL: \(url.lastPathComponent)"
        case .createCGContextFailed: return "Failed to create CoreGraphics context."
        case .createCGImageFailed: return "Failed to create CGImage from context."
        case .createPNGDataFailed: return "Failed to convert image to PNG data."
        case .tiffRepresentationFailed: return "Failed to get TIFF representation for image."
        case .imageTooSmallForTileSize(let imageSize, let tileSize): return "Image (\(imageSize)) is too small for tile size \(tileSize)."
        case .imageDimensionNotMultipleOfTileSize(let dimension, let value, let tileSize): return "Image \(dimension) (\(value)px) is not a multiple of tile size \(tileSize)px."
        }
    }
}

public class ImageUtilities {
    public static func loadCGImage(from url: URL) throws -> CGImage {
        guard let nsImage = NSImage(contentsOf: url) else {
            throw ImageError.loadImageFailed(url)
        }
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageError.loadImageFailed(url) // More specific error could be made
        }
        return cgImage
    }

    public static func createPNGData(from cgImage: CGImage) throws -> Data {
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        guard let tiffRepresentation = nsImage.tiffRepresentation else {
            throw ImageError.tiffRepresentationFailed
        }
        guard let bitmapImageRep = NSBitmapImageRep(data: tiffRepresentation) else {
            throw ImageError.tiffRepresentationFailed // Or more specific error
        }
        guard let pngData = bitmapImageRep.representation(using: .png, properties: [:]) else {
            throw ImageError.createPNGDataFailed
        }
        return pngData
    }

    // New slicing function
    public static func sliceCGImageIntoTiles(image: CGImage, tileSize: Int) throws -> ImageSliceOutput{
        let imageWidth = image.width
        let imageHeight = image.height

        guard imageWidth >= tileSize && imageHeight >= tileSize else {
            throw ImageError.imageTooSmallForTileSize(imageSize: "\(imageWidth)x\(imageHeight)", tileSize: tileSize)
        }
        guard imageWidth % tileSize == 0 else {
            throw ImageError.imageDimensionNotMultipleOfTileSize(dimension: "width", value: imageWidth, tileSize: tileSize)
        }
        guard imageHeight % tileSize == 0 else {
            throw ImageError.imageDimensionNotMultipleOfTileSize(dimension: "height", value: imageHeight, tileSize: tileSize)
        }

        let columns = imageWidth / tileSize
        let rows = imageHeight / tileSize

        var slicedTiles: [SlicedTile] = []
        var tiles: [Tile] = []
        var tileID: Int = 0

        for row in 0..<rows {
            for col in 0..<columns {
                let x = col * tileSize
                let y = row * tileSize
                
                let cropRect = CGRect(x: x, y: y, width: tileSize, height: tileSize)
                
                guard let tileCGImage = image.cropping(to: cropRect) else {
                    continue
                }
                
                if tileCGImage.isCompletelyTransparent() {
                    continue
                }
                
                if let slicedTile = slicedTiles.first(where: { tileCGImage.isEqualTo($0.cgImage) }) {
                    tiles.append(Tile(row: row, col: col, id: slicedTile.id))
                    continue
                }
                
                tileID += 1
                slicedTiles.append(SlicedTile(name: "tile_\(tileID)", cgImage: tileCGImage, id: tileID))
                tiles.append(Tile(row: row, col: col, id: tileID))
            }
        }
        
        return ImageSliceOutput(slicedTiles: slicedTiles, tiles: tiles)
    }
}

extension CGImage {
    /// Checks if the CGImage is entirely transparent (all pixels have an alpha of 0).
    func isCompletelyTransparent() -> Bool {
        guard let dataProvider = self.dataProvider,
              let data = dataProvider.data else {
            return true // If no data, consider it transparent (or handle as an error)
        }

        let pixelData: UnsafePointer<UInt8> = CFDataGetBytePtr(data)
        let width = self.width
        let height = self.height
        let bytesPerPixel = self.bitsPerPixel / 8
        let bytesPerRow = self.bytesPerRow

        // Determine the offset for the alpha channel based on the alphaInfo
        var alphaOffset: Int?
        switch self.alphaInfo {
        case .premultipliedLast, .last: // RGBA or BGRA
            alphaOffset = bytesPerPixel - 1
        case .premultipliedFirst, .first: // ARGB or ABGR
            alphaOffset = 0
        case .none, .noneSkipFirst, .noneSkipLast: // No alpha channel
            return false // If there's no alpha channel, it's not transparent in the way we're checking
        default:
            // Handle future cases or unexpected alphaInfo
            print("Warning: Unknown CGImageAlphaInfo encountered: \(self.alphaInfo)")
            return false // Default to not transparent
        }

        guard let offset = alphaOffset else {
            // No alpha channel or unhandled alphaInfo, treat as not completely transparent
            return false
        }

        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = (bytesPerRow * y) + (x * bytesPerPixel)
                let alpha = pixelData[pixelIndex + offset]
                if alpha != 0 {
                    return false // Found at least one non-transparent pixel
                }
            }
        }
        return true // All pixels were transparent
    }
}

extension CGImage {
    /// Compares two CGImage objects for pixel-by-pixel equality.
    ///
    /// - Parameter otherImage: The other CGImage to compare with.
    /// - Returns: `true` if the images are identical in terms of dimensions,
    ///            pixel format, and pixel data, `false` otherwise.
    func isEqualTo(_ otherImage: CGImage) -> Bool {
        // 1. Basic properties check (fastest checks first)
        guard self.width == otherImage.width &&
              self.height == otherImage.height &&
              self.bitsPerComponent == otherImage.bitsPerComponent &&
              self.bitsPerPixel == otherImage.bitsPerPixel &&
              self.bytesPerRow == otherImage.bytesPerRow &&
              self.colorSpace == otherImage.colorSpace && // Compare color spaces
              self.alphaInfo == otherImage.alphaInfo else { // Compare alpha info
            return false
        }

        // 2. Get pixel data
        guard let dataProvider1 = self.dataProvider,
              let data1 = dataProvider1.data,
              let dataProvider2 = otherImage.dataProvider,
              let data2 = dataProvider2.data else {
            // If data is missing for either, they can't be equal (or handle as an error)
            return false
        }

        // 3. Compare raw pixel data
        // For direct byte-by-byte comparison, ensure sizes are the same.
        // CGImage data size can be different from width * height * bytesPerPixel due to padding.
        let byteCount1 = CFDataGetLength(data1)
        let byteCount2 = CFDataGetLength(data2)

        guard byteCount1 == byteCount2 else {
            return false // Data sizes must match
        }

        let pixelData1: UnsafePointer<UInt8> = CFDataGetBytePtr(data1)
        let pixelData2: UnsafePointer<UInt8> = CFDataGetBytePtr(data2)

        // memcmp is highly efficient for comparing raw memory blocks
        return memcmp(pixelData1, pixelData2, byteCount1) == 0
    }
}
