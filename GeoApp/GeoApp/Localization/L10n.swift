import Foundation

/// Übersetzungen aus dem Katalog in der Sprache eines bestimmten `Locale`, nicht nur mit dessen Zahlenformat.
enum L10n {
    /// Sucht `key` im `<sprache>.lproj` des Hauptbundles und fällt sonst auf das Hauptbundle zurück.
    static func string(_ key: String.LocalizationValue, locale: Locale) -> String {
        let bundle: Bundle
        if let code = locale.language.languageCode?.identifier,
           let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let languageBundle = Bundle(path: path) {
            bundle = languageBundle
        } else {
            bundle = .main
        }
        return String(localized: key, bundle: bundle, locale: locale)
    }
}
