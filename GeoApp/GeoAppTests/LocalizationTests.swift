import Foundation
import Testing
@testable import GeoApp

/// Ordner `GeoApp/` (Xcode-Projekt), abgeleitet aus diesem Dateipfad: `GeoApp/GeoAppTests/<Datei>.swift`.
private let projectDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()

/// Quellordner der App (synchronisierte Gruppe `GeoApp/GeoApp`).
private let appSourceDirectory = projectDirectory.appendingPathComponent("GeoApp")

/// Lädt die `strings` eines `.xcstrings`-Katalogs aus dem Quellordner. Fehlt die Datei, wird ein Issue gemeldet.
private func loadStrings(_ file: String) -> [String: Any]? {
    let url = appSourceDirectory.appendingPathComponent(file)
    guard let data = try? Data(contentsOf: url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let strings = json["strings"] as? [String: Any] else {
        Issue.record("\(file) fehlt oder ist kein gültiger String-Katalog: \(url.path)")
        return nil
    }
    return strings
}

/// Der `stringUnit.value` einer Sprache, z. B. für `InfoPlist.xcstrings`.
private func stringValue(_ entry: [String: Any]?, _ language: String) -> String? {
    guard let localizations = entry?["localizations"] as? [String: Any],
          let localization = localizations[language] as? [String: Any],
          let unit = localization["stringUnit"] as? [String: Any] else { return nil }
    return unit["value"] as? String
}

/// Eine Lokalisierung ist fertig, wenn ihre `stringUnit` den Status `translated` hat.
/// Bei Variationen (Plural) müssen alle Fälle fertig sein.
private func isTranslated(_ localization: [String: Any]) -> Bool {
    if let unit = localization["stringUnit"] as? [String: Any] {
        return (unit["state"] as? String) == "translated"
    }
    if let variations = localization["variations"] as? [String: Any] {
        let cases = variations.values
            .compactMap { $0 as? [String: Any] }
            .flatMap { $0.values }
            .compactMap { $0 as? [String: Any] }
        return !cases.isEmpty && cases.allSatisfy { isTranslated($0) }
    }
    return false
}

/// Entfernt `//`- und `/* */`-Kommentare. String-Literale bleiben erhalten, Zeilenumbrüche auch (Zeilennummern stimmen).
private func stripComments(_ source: String) -> String {
    let s = Array(source.unicodeScalars)
    func at(_ index: Int) -> Unicode.Scalar? { index < s.count ? s[index] : nil }
    var out = String.UnicodeScalarView()
    var i = 0
    while i < s.count {
        if s[i] == "/" && at(i + 1) == "/" {
            while i < s.count && s[i] != "\n" { i += 1 }
        } else if s[i] == "/" && at(i + 1) == "*" {
            i += 2
            while i < s.count && !(s[i] == "*" && at(i + 1) == "/") {
                if s[i] == "\n" { out.append("\n") }
                i += 1
            }
            i += 2
        } else if s[i] == "\"" {
            // Einfaches oder mehrzeiliges (""") Literal, damit Kommentarzeichen darin nicht entfernt werden.
            let delimiter = at(i + 1) == "\"" && at(i + 2) == "\"" ? 3 : 1
            for _ in 0..<delimiter {
                out.append(s[i])
                i += 1
            }
            while i < s.count {
                if s[i] == "\\" {
                    out.append(s[i])
                    i += 1
                    if i < s.count {
                        out.append(s[i])
                        i += 1
                    }
                } else if s[i] == "\"" && (delimiter == 1 || (at(i + 1) == "\"" && at(i + 2) == "\"")) {
                    break
                } else if s[i] == "\n" && delimiter == 1 {
                    break
                } else {
                    out.append(s[i])
                    i += 1
                }
            }
            if i < s.count && s[i] == "\"" {
                for _ in 0..<delimiter {
                    out.append(s[i])
                    i += 1
                }
            }
        } else {
            out.append(s[i])
            i += 1
        }
    }
    return String(out)
}

/// Alle `.swift`-Dateien unter `directory`, ohne `Data/MockData.swift` (Beispiel-Ortsnamen).
private func swiftFiles(in directory: URL) -> [URL] {
    guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
        return []
    }
    return enumerator
        .compactMap { $0 as? URL }
        .filter { $0.pathExtension == "swift" && !$0.path.hasSuffix("/Data/MockData.swift") }
}

@MainActor
struct LocalizationTests {
    let en = Locale(identifier: "en")
    let de = Locale(identifier: "de")

    @Test func counterSingular() {
        #expect(MapScreen.counterText(countries: 1, cities: 1, locale: en) == "1 country · 1 city")
    }

    @Test func counterPlural() {
        #expect(MapScreen.counterText(countries: 5, cities: 12, locale: en) == "5 countries · 12 cities")
    }

    @Test func counterGerman() {
        #expect(MapScreen.counterText(countries: 1, cities: 1, locale: de) == "1 Land · 1 Stadt")
        #expect(MapScreen.counterText(countries: 5, cities: 12, locale: de) == "5 Länder · 12 Städte")
    }

    @Test func cityCountGerman() {
        #expect(ListScreen.cityCountText(0, locale: de) == "0 Städte")
        #expect(ListScreen.cityCountText(1, locale: de) == "1 Stadt")
        #expect(ListScreen.cityCountText(3, locale: de) == "3 Städte")
    }

    @Test func cityCountEnglish() {
        #expect(ListScreen.cityCountText(0, locale: en) == "0 cities")
        #expect(ListScreen.cityCountText(1, locale: en) == "1 city")
        #expect(ListScreen.cityCountText(3, locale: en) == "3 cities")
    }

    @Test func catalogComplete() {
        guard let strings = loadStrings("Localizable.xcstrings") else { return }
        var missing: [String] = []
        for key in strings.keys.sorted() {
            guard let entry = strings[key] as? [String: Any] else {
                missing.append(key)
                continue
            }
            if entry["shouldTranslate"] as? Bool == false { continue }
            guard let localizations = entry["localizations"] as? [String: Any],
                  let german = localizations["de"] as? [String: Any],
                  isTranslated(german) else {
                missing.append(key)
                continue
            }
        }
        #expect(missing.isEmpty, "Keys without a complete de translation: \(missing.joined(separator: ", "))")
    }

    @Test func noGermanSourceStrings() {
        let files = swiftFiles(in: appSourceDirectory)
        #expect(!files.isEmpty, "No Swift files found under \(appSourceDirectory.path)")

        let pattern = #"(?<![A-Za-z0-9_])(Text|Label|Button|Section|\.navigationTitle|Toggle|LabeledContent|ContentUnavailableView|\.alert|\.confirmationDialog|hintCapsule)\(\s*"((?:[^"\\]|\\.)*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            Issue.record("Invalid regular expression for string literal scan")
            return
        }
        let germanMarkers = CharacterSet(charactersIn: "äöüßÄÖÜ„")

        var offending: [String] = []
        for file in files {
            let relativePath = file.path.replacingOccurrences(of: appSourceDirectory.path + "/", with: "")
            guard let source = try? String(contentsOf: file, encoding: .utf8) else {
                Issue.record("Cannot read \(relativePath)")
                continue
            }
            let text = stripComments(source) as NSString
            for match in regex.matches(in: text as String, range: NSRange(location: 0, length: text.length)) {
                let literal = text.substring(with: match.range(at: 2))
                guard literal.rangeOfCharacter(from: germanMarkers) != nil else { continue }
                let line = text.substring(to: match.range.location).components(separatedBy: "\n").count
                offending.append("\(relativePath):\(line) \"\(literal)\"")
            }
        }
        #expect(offending.isEmpty, "German string literals in UI calls: \(offending.joined(separator: "; "))")
    }

    @Test func permissionTextsLocalized() {
        guard let strings = loadStrings("InfoPlist.xcstrings") else { return }

        for key in ["NSLocationWhenInUseUsageDescription", "NSLocationAlwaysAndWhenInUseUsageDescription"] {
            let entry = strings[key] as? [String: Any]
            let english = stringValue(entry, "en") ?? ""
            let german = stringValue(entry, "de") ?? ""
            #expect(entry != nil, "\(key) is missing from InfoPlist.xcstrings")
            #expect(!english.isEmpty && !german.isEmpty, "\(key) needs non-empty en and de values")
            #expect(english != german, "\(key): en and de values are identical")
        }

        let alwaysEnglish = stringValue(strings["NSLocationAlwaysAndWhenInUseUsageDescription"] as? [String: Any], "en") ?? ""
        for word in ["city", "country", "time"] {
            #expect(alwaysEnglish.localizedCaseInsensitiveContains(word),
                    "English Always text must mention \"\(word)\": \(alwaysEnglish)")
        }

        // Die Texte kommen nur aus dem Katalog, nicht mehr aus den Build-Settings.
        let pbxprojURL = projectDirectory.appendingPathComponent("GeoApp.xcodeproj/project.pbxproj")
        if let pbxproj = try? String(contentsOf: pbxprojURL, encoding: .utf8) {
            #expect(!pbxproj.contains("INFOPLIST_KEY_NSLocation"),
                    "project.pbxproj still sets INFOPLIST_KEY_NSLocation* build settings")
        } else {
            Issue.record("Cannot read project.pbxproj: \(pbxprojURL.path)")
        }
    }
}
