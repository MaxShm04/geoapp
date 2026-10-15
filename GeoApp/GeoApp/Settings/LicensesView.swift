import GeoCore
import SwiftUI

/// Lizenzhinweise für die Datensätze im App-Paket.
struct LicensesView: View {
    var body: some View {
        List {
            Section {
                Text("Ländergrenzen: Made with Natural Earth. Free vector and raster map data @ naturalearthdata.com.")
                Text("Natural Earth ist gemeinfrei (Public Domain). Verwendet werden die Ländergrenzen im Maßstab 1:50 Mio., für Kleinstaaten 1:10 Mio.")
                    .foregroundStyle(.secondary)
                Link("naturalearthdata.com", destination: URL(string: "https://www.naturalearthdata.com")!)
            } header: {
                Text("Natural Earth")
            }

            Section {
                Text("Städtedaten: GeoNames (geonames.org), lizenziert unter Creative Commons Namensnennung 4.0 International (CC BY 4.0).")
                Text("Verwendet wird die Liste der Orte ab 15.000 Einwohnern mit englischen Namen. Für die App wurden die Daten verändert: Stadtteile und Vororte sind ihrer Stadt zugeordnet (zum Beispiel Arrondissements zu Paris, Stepney zu London).")
                    .foregroundStyle(.secondary)
                Link("geonames.org", destination: URL(string: "https://www.geonames.org")!)
                Link("Lizenz CC BY 4.0", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/deed.de")!)
            } header: {
                Text("GeoNames")
            }

            Section {
                ForEach(DistrictIndex.shared.sources, id: \.cc) { source in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(CountryNames.name(for: source.cc))
                        Text("\(source.source) · \(source.license)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Kreise und Bezirke")
            } footer: {
                Text("Grenzen der Kreise aus geoBoundaries (geoboundaries.org) und Natural Earth, vereinfacht für die App. Die Lizenz gilt jeweils für die Daten des Landes.")
            }

            Section {
                Text("Hauptstraßen in Großstädten: © OpenStreetMap-Mitwirkende, verfügbar unter der Open Database License (ODbL).")
                Text("Für die App vereinfacht und auf die Umgebung der Städte zugeschnitten.")
                    .foregroundStyle(.secondary)
                Link("openstreetmap.org/copyright", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
            } header: {
                Text("OpenStreetMap")
            }

            Section {
                Text("Kartendarstellung mit MapLibre Native (BSD-2-Clause-Lizenz). Die Karte zeigt nur die Daten oben, ohne Kartenkacheln aus dem Netz.")
                    .foregroundStyle(.secondary)
                Link("maplibre.org", destination: URL(string: "https://maplibre.org")!)
                NavigationLink("Lizenztext MapLibre Native") { MapLibreLicenseView() }
            } header: {
                Text("Karte")
            }
        }
        .navigationTitle("Lizenzen")
    }
}

/// Die BSD-2-Clause-Lizenz verlangt den vollständigen Text samt Copyright in der App.
private struct MapLibreLicenseView: View {
    var body: some View {
        ScrollView {
            Text(Self.text)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .padding()
        }
        .navigationTitle("MapLibre Native")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static let text = """
        BSD 2-Clause License

        Copyright (c) 2021 MapLibre contributors

        Copyright (c) 2018-2021 MapTiler.com

        Copyright (c) 2014-2020 Mapbox

        Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

        * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
        * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

        THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
        """
}
