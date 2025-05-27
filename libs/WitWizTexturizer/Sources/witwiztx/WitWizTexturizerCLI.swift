import Foundation
import ArgumentParser
import WitWizTexturizerCore

// MARK: - Main Command Structure

@main
struct WitWizTexturizerCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A Swift-based tool for slicing images and packing textures.",
        version: "0.1.0",
        subcommands: [SliceCommand.self, PackCommand.self], // Define subcommands
        defaultSubcommand: PackCommand.self // Optional: set a default subcommand if none is specified
    )
}

// MARK: - Slice Command

struct SliceCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "slice",
        abstract: "Slices a single large image into smaller tiles."
    )

    @Argument(help: "Path to the input image file (e.g., your_design.png).")
    var inputImagePath: String

    @Argument(help: "Path to the directory where the sliced tile images will be saved.")
    var outputPath: String

    @Option(name: .shortAndLong, help: "Size of each tile (e.g., 32 for 32x32 pixels).")
    var tileSize: Int = 32

    func run() throws {
        let inputFileURL = URL(fileURLWithPath: inputImagePath)
        let outputDirectoryURL = URL(fileURLWithPath: outputPath)

        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: inputFileURL.path) else {
            print("Error: Input image file not found at '\(inputImagePath)'")
            throw ExitCode.validationFailure
        }

        if !fileManager.fileExists(atPath: outputDirectoryURL.path) {
            do {
                try fileManager.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true)
                print("Created output directory: '\(outputPath)'")
            } catch {
                print("Error creating output directory: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }

        print("Slicing '\(inputFileURL.lastPathComponent)' into \(tileSize)x\(tileSize) tiles...")
        
        do {
            let originalImage = try ImageUtilities.loadCGImage(from: inputFileURL)
            let imageSliceOutput = try ImageUtilities.sliceCGImageIntoTiles(image: originalImage, tileSize: tileSize)

            if imageSliceOutput.slicedTiles.isEmpty {
                print("No tiles were generated. Check input image dimensions and tile size.")
                throw ExitCode.failure
            }

            for slicedTile in imageSliceOutput.slicedTiles {
                let tileURL = outputDirectoryURL.appendingPathComponent("\(slicedTile.name).png")
                let pngData = try ImageUtilities.createPNGData(from: slicedTile.cgImage)
                try pngData.write(to: tileURL)
            }
            
            let tilesURL = outputDirectoryURL.appendingPathComponent("tiles.json")
            let jsonData = try JSONEncoder().encode(imageSliceOutput.tiles)
            try jsonData.write(to: tilesURL)
            
            print("Successfully sliced \(imageSliceOutput.slicedTiles.count) tiles to: '\(outputDirectoryURL.path)'")
            
        } catch let error as ImageError {
            print("Slicing error: \(error.localizedDescription)")
            throw ExitCode.failure
            
        } catch {
            print("An unexpected error occurred during slicing: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}

// MARK: - Pack Command (Your existing packing logic)

struct PackCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pack",
        abstract: "Packs individual images from a directory into a single texture atlas."
    )

    @Argument(help: "Path to the directory containing input image files (tiles to pack).")
    var inputPath: String

    @Argument(help: "Path to the directory where the output atlas and data files will be saved.")
    var outputPath: String

    @Option(name: .shortAndLong, help: "Padding between sprites in pixels.")
    var padding: Int = 2

    @Option(name: .shortAndLong, help: "Maximum allowed width/height for the atlas texture.")
    var maxAtlasSize: Int = 4096

    func run() throws {
        let inputDirectoryURL = URL(fileURLWithPath: inputPath)
        let outputDirectoryURL = URL(fileURLWithPath: outputPath)

        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: inputDirectoryURL.path) else {
            print("Error: Input directory not found at '\(inputPath)'")
            throw ExitCode.validationFailure
        }

        if !fileManager.fileExists(atPath: outputDirectoryURL.path) {
            do {
                try fileManager.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true)
                print("Created output directory: '\(outputPath)'")
            } catch {
                print("Error creating output directory: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }

        let imageFiles = try fileManager.contentsOfDirectory(at: inputDirectoryURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            .filter { $0.pathExtension.lowercased() == "png" }

        if imageFiles.isEmpty {
            print("No PNG images found in input directory: '\(inputPath)'")
            throw ExitCode.success // Or validationError if empty input is an error
        }

        let packer = TexturePacker()
        do {
            print("Starting packing process for \(imageFiles.count) images...")
            let (packedImage, atlasData) = try packer.pack(
                inputImageURLs: imageFiles,
                padding: padding,
                maxAtlasSize: maxAtlasSize
            )

            let atlasFileName = "atlas.png"
            let dataFileName = "atlas.plist"

            let finalAtlasURL = outputDirectoryURL.appendingPathComponent(atlasFileName)
            let finalDataURL = outputDirectoryURL.appendingPathComponent(dataFileName)

            // Save the packed image
            let pngData = try ImageUtilities.createPNGData(from: packedImage)
            try pngData.write(to: finalAtlasURL)
            print("Saved atlas image to: \(finalAtlasURL.path)")

            // Save the atlas data (as Plist)
            let plistData = try PropertyListSerialization.data(fromPropertyList: atlasData.asDictionary(), format: .xml, options: 0)
            try plistData.write(to: finalDataURL)
            print("Saved atlas data to: \(finalDataURL.path)")

            print("Texture packing completed successfully!")

        } catch let error as ImageError {
            print("Packing error: \(error.localizedDescription)")
            throw ExitCode.failure
        } catch {
            print("An unexpected error occurred during packing: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}

// Helper to convert Encodable to Dictionary for PropertyListSerialization
extension Encodable {
    func asDictionary() throws -> [String: Any] {
        let data = try JSONEncoder().encode(self)
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = jsonObject as? [String: Any] else {
            throw NSError(domain: "Codable", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not convert to dictionary"])
        }
        return dictionary
    }
}
