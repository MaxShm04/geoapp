import CoreGraphics
import Foundation
import GeoCore
import UIKit

/// Zeichnet die Weltkarte für das Karten-Widget als PNG aus den Ländergrenzen von Natural Earth.
enum WidgetMapRenderer {
    /// PNG mit Skalierung 1, besuchte Länder hervorgehoben.
    static func render(visited: Set<String>, size: CGSize, dark: Bool) -> Data? {
        let ocean = dark ? UIColor(red: 0.08, green: 0.09, blue: 0.10, alpha: 1) : UIColor(red: 0.93, green: 0.95, blue: 0.96, alpha: 1)
        let land = dark ? UIColor(white: 0.24, alpha: 1) : UIColor(white: 0.84, alpha: 1)
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        let accent = (UIColor(named: "AccentColor") ?? .systemTeal).resolvedColor(with: traits)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            ocean.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            for country in GeoLookup.shared.countries.countries {
                let path = UIBezierPath()
                path.usesEvenOddFillRule = true
                for polygon in country.polygons {
                    for flat in polygon.rings where flat.count >= 6 {
                        path.move(to: point(lat: flat[1], lon: flat[0], in: size))
                        for i in stride(from: 2, to: flat.count - 1, by: 2) {
                            path.addLine(to: point(lat: flat[i + 1], lon: flat[i], in: size))
                        }
                        path.close()
                    }
                }
                (visited.contains(country.code) ? accent : land).setFill()
                path.fill()
                // Dünne Grenze in Meerfarbe, damit Länder nicht ineinanderlaufen.
                ocean.setStroke()
                path.lineWidth = 0.5
                path.stroke()
            }
        }
        return image.pngData()
    }

    /// Bildpunkt einer Koordinate in der Projektion der Karte (zum Testen der Zeichnung).
    /// Equirechteckig, Antarktis oberhalb von -58° Breite abgeschnitten.
    static func point(lat: Double, lon: Double, in size: CGSize) -> CGPoint {
        CGPoint(x: (lon + 180) / 360 * size.width, y: (84 - lat) / (84 + 58) * size.height)
    }
}
