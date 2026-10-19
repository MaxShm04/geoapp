import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import GeoApp

/// Farben in einem Bildpunkt (0–255).
private typealias RGB = (r: Int, g: Int, b: Int)

/// Liest die Farbe eines Bildpunkts. Das Bild wird in einen RGBA8-Kontext gezeichnet, damit die Werte gleich aussehen.
private func rgb(of data: Data, at point: CGPoint) throws -> RGB {
    let image = try #require(UIImage(data: data)?.cgImage)
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    try #require(drawn)
    let x = Int(point.x)
    let y = Int(point.y)
    try #require(x >= 0 && x < width && y >= 0 && y < height)
    let index = (y * width + x) * 4
    return (Int(pixels[index]), Int(pixels[index + 1]), Int(pixels[index + 2]))
}

/// Summe der Unterschiede in Rot, Grün und Blau.
private func difference(_ a: RGB, _ b: RGB) -> Int {
    abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b)
}

@MainActor
struct WidgetMapTests {
    let size = CGSize(width: 600, height: 300)

    @Test func rendersPNG() throws {
        let visited = try #require(WidgetMapRenderer.render(visited: ["DE"], size: size, dark: false))
        #expect(Array(visited.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])

        let image = try #require(UIImage(data: visited))
        let cgImage = try #require(image.cgImage)
        #expect(cgImage.width == 600)

        let empty = try #require(WidgetMapRenderer.render(visited: [], size: size, dark: false))
        let germany = WidgetMapRenderer.point(lat: 51.1, lon: 10.4, in: size)
        let visitedGermany = try rgb(of: visited, at: germany)
        let emptyGermany = try rgb(of: empty, at: germany)
        #expect(difference(visitedGermany, emptyGermany) > 30)

        let dark = try #require(WidgetMapRenderer.render(visited: ["DE"], size: size, dark: true))
        let sea = WidgetMapRenderer.point(lat: 30, lon: -30, in: size)
        let lightSea = try rgb(of: visited, at: sea)
        let darkSea = try rgb(of: dark, at: sea)
        #expect(difference(lightSea, darkSea) > 30)
    }
}
