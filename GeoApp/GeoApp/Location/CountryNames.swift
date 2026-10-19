import Foundation
import GeoCore

enum CountryNames {
    /// Name in der Gerätesprache, sonst der englische Name aus Natural Earth.
    static func name(for code: String) -> String {
        Locale.current.localizedString(forRegionCode: code)
            ?? GeoLookup.shared.countries.shape(for: code)?.name
            ?? code
    }

    /// Flagge als Emoji aus dem ISO-Code, leer für Gebiete ohne zweistelligen Code.
    static func flag(for code: String) -> String {
        guard code.count == 2, code.allSatisfy({ $0.isASCII && $0.isLetter }) else { return "" }
        return String(String.UnicodeScalarView(code.uppercased().unicodeScalars.compactMap {
            UnicodeScalar(127_397 + $0.value)
        }))
    }
}
