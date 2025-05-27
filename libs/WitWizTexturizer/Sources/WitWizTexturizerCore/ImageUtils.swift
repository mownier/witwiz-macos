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
    public static func sliceCGImageIntoTiles(image: CGImage, tileSize: Int) throws -> [(tileName: String, cgImage: CGImage)] {
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

        var slicedTiles: [(tileName: String, cgImage: CGImage)] = []

        for row in 0..<rows {
            for col in 0..<columns {
                let x = col * tileSize
                let y = row * tileSize
                
                let cropRect = CGRect(x: x, y: y, width: tileSize, height: tileSize)
                
                guard let tileCGImage = image.cropping(to: cropRect) else {
                    print("Warning: Failed to crop tile at (\(x), \(y)). Skipping.")
                    continue
                }
                
                let tileID = row*col + col + 1
                
                let tileName = "tile_\(tileID)"
                slicedTiles.append((tileName: tileName, cgImage: tileCGImage))
            }
        }
        return slicedTiles
    }
}
