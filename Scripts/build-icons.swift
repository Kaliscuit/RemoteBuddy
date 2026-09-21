import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let resources = root.appendingPathComponent("Resources")
let work = root.appendingPathComponent("work/icon-build")
let iconset = work.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func load(_ url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw NSError(domain: "RemoteBuddy.IconBuild", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot read \(url.path)"])
    }
    return image
}
func canvas(_ width: Int, _ height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
}
func write(_ image: CGImage, _ url: URL, scale: Int = 1) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "RemoteBuddy.IconBuild", code: 2)
    }
    CGImageDestinationAddImage(destination, image,
        [kCGImagePropertyDPIWidth: 72 * scale, kCGImagePropertyDPIHeight: 72 * scale] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "RemoteBuddy.IconBuild", code: 3) }
}

// Preserve the supplied app artwork, providing every standard macOS icon size.
let appSource = try load(resources.appendingPathComponent("Artwork/AppIcon-source.png"))
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let context = canvas(pixels, pixels)
        context.interpolationQuality = .high
        context.draw(appSource, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        let suffix = scale == 2 ? "@2x" : ""
        try write(context.makeImage()!, iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"), scale: scale)
    }
}

// Remove only transparent margins; keep the supplied status glyph's geometry.
let statusSource = try load(resources.appendingPathComponent("Artwork/StatusBar-source.png"))
let normalized = canvas(statusSource.width, statusSource.height)
normalized.draw(statusSource, in: CGRect(x: 0, y: 0, width: statusSource.width, height: statusSource.height))
let bytes = normalized.data!.assumingMemoryBound(to: UInt8.self)
var minX = statusSource.width, minY = statusSource.height, maxX = -1, maxY = -1
for y in 0..<statusSource.height {
    for x in 0..<statusSource.width {
        let index = (y * statusSource.width + x) * 4
        if bytes[index + 3] > 2 {
            minX = min(minX, x); minY = min(minY, y)
            maxX = max(maxX, x); maxY = max(maxY, y)
        }
        bytes[index] = 0; bytes[index + 1] = 0; bytes[index + 2] = 0
    }
}
guard maxX >= minX, maxY >= minY else { fatalError("Status image is fully transparent") }
let glyph = normalized.makeImage()!.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))!
for scale in [1, 2] {
    let pixels = 18 * scale
    let context = canvas(pixels, pixels)
    context.interpolationQuality = .high
    let ratio = min(Double(pixels) / Double(glyph.width), Double(pixels) / Double(glyph.height))
    let width = Double(glyph.width) * ratio, height = Double(glyph.height) * ratio
    context.draw(glyph, in: CGRect(x: (Double(pixels) - width) / 2, y: (Double(pixels) - height) / 2, width: width, height: height))
    let suffix = scale == 2 ? "@2x" : ""
    try write(context.makeImage()!, resources.appendingPathComponent("StatusBarTemplate\(suffix).png"), scale: scale)
}

// A visual check of the same alpha mask on light, dark and recording states.
let template = try load(resources.appendingPathComponent("StatusBarTemplate@2x.png"))
let preview = canvas(480, 96)
for (index, background, ink) in [
    (0, CGColor(gray: 0.95, alpha: 1), CGColor(gray: 0.08, alpha: 1)),
    (1, CGColor(gray: 0.12, alpha: 1), CGColor(gray: 0.95, alpha: 1)),
    (2, CGColor(gray: 0.95, alpha: 1), CGColor(red: 0.9, green: 0.12, blue: 0.12, alpha: 1))
] {
    preview.setFillColor(background)
    preview.fill(CGRect(x: index * 160, y: 0, width: 160, height: 96))
    preview.saveGState()
    preview.clip(to: CGRect(x: index * 160 + 62, y: 30, width: 36, height: 36), mask: template)
    preview.setFillColor(ink)
    preview.fill(CGRect(x: index * 160, y: 0, width: 160, height: 96))
    preview.restoreGState()
}
try write(preview.makeImage()!, work.appendingPathComponent("status-preview.png"))
print("Generated app iconset and 18pt/36px status template")
