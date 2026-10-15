# Prototyp-Briefing: Länder- und Städte-Tracker (iOS)

Oct 9, 2026 · @Max

## Vision

Eine schlichte iPhone-App, die im Hintergrund mitzeichnet, in welchen Ländern und Städten du warst, und daraus eine ruhige Weltkarte macht. Alles bleibt auf dem Gerät.

- **Kernversprechen:** Einmal Standort erlauben, danach nichts mehr tun. Die Karte füllt sich von selbst.
- **Abgrenzung:** Kein Wegeprotokoll wie bei Google Timeline, kein manuelles Abhaken wie bei Been, kein Entdecker-Spiel wie bei Been To. Nur Land und Stadt, klar und übersichtlich.
- **Zielgruppe:** Reisende, die ihre Reisekarte besitzen und zeigen wollen, aber weder Pflegeaufwand noch Datenweitergabe möchten.
- **Wirkung der Karte:** Besuchte Länder sind farbig, ein Tipp auf ein Land zeigt die Städte als Punkte.
- **Arbeitstitel:** noch offen.

## Umfang des Prototyps

Der Prototyp soll eine Frage beantworten: Erfasst die App im Alltag zuverlässig Länder und Städte, und sieht die Karte gut aus? Dafür reichen iOS, ein Gerät und lokale Daten.

**Enthalten**

- Onboarding mit Standortberechtigung "Immer"
- Hintergrund-Erfassung bei Ortswechseln
- Offline-Zuordnung von Koordinate zu Land und Stadt
- Lokale Speicherung der Besuche
- Weltkarte mit eingefärbten Ländern, Länderansicht mit Städtepunkten
- Liste der Länder und Städte mit erstem und letztem Besuch
- Einzelne Einträge löschen, alle Daten löschen
- Diagnose-Log zum Prüfen der Erfassung (ohne Koordinaten)

**Bewusst nicht enthalten**

- Account, Cloud-Sync, Backup
- Bezahlfunktion und Premium
- Import aus Google Takeout oder Fotos
- Teilen-Bild und Jahresrückblick
- Heatmap oder Mesh der Städte
- Android, Widgets, Apple Watch

## Funktionen im Detail

Die App hat fünf Funktionen. Die erste läuft unsichtbar, die anderen vier sind die sichtbare Oberfläche.

1. **Erfassung im Hintergrund.** Das System weckt die App bei größeren Ortswechseln, auch wenn sie beendet wurde. Pro Ereignis wird die Position einmal einem Land und einer Stadt zugeordnet und sofort verworfen. Zusätzlich gibt es eine einmalige Abfrage beim Öffnen der App.
2. **Weltkarte.** Startbildschirm. Besuchte Länder sind in einem Akzentton gefüllt, alle anderen in ruhigem Grau. Oben steht ein Zähler wie "12 Länder · 31 Städte". Zoomen und Verschieben sind möglich.
3. **Länderansicht.** Ein Tipp auf ein besuchtes Land zoomt hinein. Die besuchten Städte erscheinen als Punkte, darunter steht die Liste mit erstem und letztem Besuch.
4. **Listen.** Alle Länder und Städte als Liste, sortiert nach letztem Besuch oder alphabetisch.
5. **Einstellungen.** Status der Berechtigung, Erfassung ein oder aus, einzelne Einträge löschen, alle Daten löschen, Diagnose-Log, Lizenzhinweise.

## Datenschutz-Prinzipien

Die App speichert nie, wo genau du warst, sondern nur, in welcher Stadt und welchem Land. Das ist zugleich das stärkste Verkaufsargument.

- **Keine Rohkoordinaten speichern.** Nach der Zuordnung werden Breite und Länge verworfen. Gespeichert werden Stadt-ID, Land und Zeitpunkt.
- **Kein Netzwerk im Prototyp.** Kein Account, kein Server, keine Analyse- oder Werbe-SDKs, keine Online-Geocoder.
- **Ehrliche Berechtigungstexte.** Die Begründungen für "Beim Verwenden" und "Immer" sagen klar, was erfasst wird und was nicht.
- **Diagnose-Log ohne Koordinaten.** Das Log hält nur Zeitpunkt, gefundene Stadt, Entfernung zur Stadtmitte und Quelle der Erfassung fest. Es ist standardmäßig aus.
- **Volle Kontrolle.** Einzelne Besuche und alle Daten lassen sich löschen.

## Technik

Der Prototyp ist eine native iOS-App ohne Server: Swift und SwiftUI, Zuordnung und Speicherung komplett auf dem Gerät.

- **Plattform:** iOS 17 oder neuer, Swift, SwiftUI, SwiftData für die Speicherung.
- **Standort:** Core Location mit `startMonitoringSignificantLocationChanges()`. Das System startet die App bei Ortswechseln neu, auch nach dem Beenden. `startMonitoringVisits()` ist die Alternative und im Alltag zu vergleichen. Die Berechtigung läuft in zwei Schritten: erst "Beim Verwenden", danach "Immer". Hintergrundmodus "Location updates" ist aktiviert.
- **Land bestimmen:** Vereinfachte Ländergrenzen von Natural Earth (gemeinfrei) als GeoJSON im App-Paket. Die Zuordnung läuft per Punkt-in-Polygon. Liegt ein Punkt knapp vor der Küste, gilt das nächstgelegene Land innerhalb weniger Kilometer.
- **Stadt bestimmen:** GeoNames-Liste `cities15000` (Städte ab 15.000 Einwohnern, Lizenz CC BY 4.0, Namensnennung in der App nötig). Gesucht wird die nächstgelegene Stadt innerhalb eines Radius, Startwert 25 km, als Konstante zum Anpassen. Ein k-d-Baum oder Raster beschleunigt die Suche.
- **Karte:** MapLibre Native (BSD-2-Clause) mit leerem Stil: Länder-, Regions- und Kreisgrenzen aus dem App-Paket als Flächen, keine Kartenkacheln, kein Netzwerk. Ursprünglich war MapKit geplant, MapLibre gibt aber volle Kontrolle über die ruhige Darstellung.
- **Tests ohne Reise:** Xcode kann Orte und GPX-Routen simulieren. So lässt sich die Zuordnung prüfen. Das Hintergrundverhalten zeigt sich nur auf dem echten iPhone.

&#91;embedded content: Datenfluss · 5 Schritte, Koordinate nur bis zur Zuordnung\]

Die Rohposition lebt nur in den ersten drei Schritten. Danach existieren nur noch Stadt-ID, Land und Zeitpunkt.

## Datenmodell und Besuchsregeln

Drei Tabellen reichen: Länder, Städte und Besuchstage. Alle Werte stammen aus den Datensätzen oder dem Zeitpunkt, nie aus der Position der Person.

| Entität | Felder | Zweck |
| --- | --- | --- |
| Country | isoCode, name, firstVisited, lastVisited | Eingefärbte Länder auf der Karte |
| City | geonamesId, name, countryCode, Stadtmitte (Breite, Länge aus GeoNames), firstVisited, lastVisited | Punkte in der Länderansicht |
| DayVisit | Tag, geonamesId, countryCode, Region, Kreis, erste und letzte Erfassung, Anzahl, Quellen | Ein Eintrag pro Ort und Tag, Quellen = Ortswechsel, Visit oder beim Öffnen |

**Regeln für den Start.** Alle Zahlen sind Startwerte zum Anpassen nach dem Alltagstest.

1. Ungültige Positionen werden ignoriert: negative Genauigkeit oder horizontale Genauigkeit über 10 km.
2. Das Land kommt immer aus dem Polygon, die Stadt aus dem Radius. Ohne Stadt im Radius zählt nur das Land.
3. Positionen mit Geschwindigkeit über 150 m/s gelten als Flug und werden ignoriert. Zug und Auto zählen.
4. Pro Ort und Tag gibt es einen Eintrag. Weitere Erfassungen am selben Tag erhöhen nur den Zähler und die Zeit der letzten Erfassung. (Bis Oktober 2026: neues Ereignis nach 6 Stunden.)
5. Jede gültige Erfassung zählt zunächst als Besuch. Einen Mindestaufenthalt führt die zweite Phase ein, sobald echte Daten vorliegen.
6. Das Heimatland zählt wie jedes andere Land.

## Screens und Design

Die Weltkarte ist die Hauptfigur, alles andere ordnet sich ihr unter. Vier Screens und ein kurzes Onboarding genügen.

1. **Onboarding.** Ein Screen erklärt in zwei Sätzen, was erfasst wird und was nicht. Danach folgen die zwei Berechtigungsschritte (erst "Beim Verwenden", dann "Immer"), weil iOS das so vorgibt.
2. **Karte.** Start-Screen mit Zähler oben und Weltkarte darunter.
3. **Land.** Zoom auf das Land, Städte als Punkte, darunter eine Liste mit Daten.
4. **Liste.** Länder und Städte, umschaltbar.
5. **Einstellungen.** Berechtigung, Erfassung, Löschen, Diagnose-Log, Lizenzen.

**Designprinzipien**

- Ruhig und flach: viel Weißraum, ein Akzentton, Systemschrift, Hell- und Dunkelmodus.
- Keine Gamification: keine Abzeichen, keine Prozentbalken, keine Aufforderungen zum Öffnen der App.
- Besuchte Länder tragen die Farbe, nicht die Beschriftung. Namen erscheinen erst beim Hineinzoomen oder Antippen.

## Auf dem iPhone testen

Du brauchst einen Mac mit Xcode und ein Kabel zum iPhone, ein bezahltes Entwicklerkonto brauchst du für den Prototyp nicht. Claude Code schreibt den Code, gebaut und installiert wird in Xcode.

**Voraussetzungen**

- Ein Mac mit aktuellem Xcode (kostenlos im Mac App Store). Ohne Mac lässt sich eine iPhone-App nicht bauen.
- Eine normale Apple-ID. Das kostenlose "Personal Team" erlaubt Installation auf dem eigenen iPhone. Die App läuft dann 7 Tage und wird danach über Xcode neu installiert.
- Das Apple Developer Program (99 USD pro Jahr) ist erst für TestFlight und den App Store nötig.

**Schritte**

1. In Xcode ein neues iOS-App-Projekt anlegen (Vorlage "App", Oberfläche SwiftUI, Speicherung SwiftData) und den Ordner speichern.
2. In Xcode unter Settings → Accounts deine Apple-ID hinzufügen.
3. Im Projekt unter Signing & Capabilities das Team "Personal Team" wählen und eine eindeutige Bundle-ID vergeben.
4. Dort "Background Modes" hinzufügen und "Location updates" aktivieren (Claude Code ergänzt die Texte in der Info.plist).
5. Das iPhone per Kabel verbinden und auf dem iPhone den Entwicklermodus einschalten (Einstellungen → Datenschutz & Sicherheit → Entwicklermodus).
6. Das iPhone als Ziel wählen und auf Run drücken.
7. Auf dem iPhone dem Entwickler vertrauen (Einstellungen → Allgemein → VPN & Geräteverwaltung).
8. Die App öffnen und im Onboarding "Immer" erlauben.

Nach 7 Tagen die App erneut über Xcode installieren und dabei die bestehende Installation überschreiben, nicht vorher löschen, damit die Daten bleiben.

## Akzeptanzkriterien und Alltagstest

Der Prototyp ist gelungen, wenn er nach zwei Wochen Alltag den größten Teil deiner tatsächlichen Städte erfasst hat. Der Rest sind Prüfpunkte auf dem Weg dorthin.

**Funktionstest (Simulator und Gerät)**

- [ ] Onboarding führt durch beide Berechtigungsschritte, "Immer" ist am Ende gesetzt.
- [ ] Eine simulierte GPX-Route (zum Beispiel Berlin, Paris, Rom) ergibt die richtigen Länder und Städte.
- [ ] Ein Punkt im Meer und ein Punkt an einer Grenze führen zu einem sinnvollen Ergebnis oder keinem Eintrag, aber nie zum Absturz.
- [ ] Die Datenbank enthält keine Rohkoordinaten (im Code und in den gespeicherten Daten geprüft).
- [ ] Die Weltkarte mit allen Ländern lässt sich flüssig zoomen und verschieben.

**Alltagstest (zwei Wochen auf dem echten iPhone)**

- [ ] Die App erfasst Ortswechsel auch nach dem Beenden aus dem App-Wechsler.
- [ ] Heimatstadt und die Orte der täglichen Wege sind erfasst.
- [ ] Ein Wochenendausflug oder eine Reise erscheint vollständig auf der Karte.
- [ ] Der Akkuverbrauch der App ist unauffällig (Zielwert, Annahme: unter 2 % pro Tag).

**Entscheidung nach dem Test:** Fehlt mehr als ein Zehntel der Städte, die du tatsächlich besucht hast, wird zuerst die Erfassung verbessert (Visits statt Ortswechsel, zusätzliche Abfragen). Erst danach folgen Funktionen.

