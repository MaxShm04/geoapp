import Foundation
import GeoCore

enum CountryNames {
    /// Name in der Gerätesprache, sonst der englische Name aus Natural Earth.
    static func name(for code: String) -> String {
        Locale.current.localizedString(forRegionCode: code)
            ?? GeoLookup.shared.countries.shape(for: code)?.name
            ?? code
    }
}
