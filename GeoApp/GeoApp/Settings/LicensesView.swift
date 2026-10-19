import GeoCore
import SwiftUI

/// Lizenzhinweise für die Datensätze im App-Paket.
struct LicensesView: View {
    var body: some View {
        List {
            Section {
                Text("Country borders: Made with Natural Earth. Free vector and raster map data @ naturalearthdata.com.")
                Text("Natural Earth is in the public domain. Country borders are used at a scale of 1:50 million, and 1:10 million for small countries.")
                    .foregroundStyle(.secondary)
                Link("naturalearthdata.com", destination: URL(string: "https://www.naturalearthdata.com")!)
            } header: {
                Text("Natural Earth")
            }

            Section {
                Text("City data: GeoNames (geonames.org), licensed under Creative Commons Attribution 4.0 International (CC BY 4.0).")
                Text("Uses the list of places with 15,000 or more residents and English names. The data was changed for the app: districts and suburbs are assigned to their city (for example, arrondissements to Paris, Stepney to London).")
                    .foregroundStyle(.secondary)
                Link("geonames.org", destination: URL(string: "https://www.geonames.org")!)
                Link("CC BY 4.0 license", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/deed.de")!)
            } header: {
                Text("GeoNames")
            }

            Section {
                ForEach(DistrictIndex.shared.sources, id: \.cc) { source in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(CountryNames.name(for: source.cc))
                        Text(verbatim: "\(source.source) · \(source.license)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Districts")
            } footer: {
                Text("District borders from geoBoundaries (geoboundaries.org) and Natural Earth, simplified for the app. The license applies to each country’s data.")
            }

            Section {
                Text("Main roads in cities: © OpenStreetMap contributors, available under the Open Database License (ODbL).")
                Text("Simplified for the app and cut to the area around the cities.")
                    .foregroundStyle(.secondary)
                Link("openstreetmap.org/copyright", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
            } header: {
                Text("OpenStreetMap")
            }

            Section {
                Text("Map display with MapLibre Native (BSD 2-Clause license). The map shows only the data above, without map tiles from the network.")
                    .foregroundStyle(.secondary)
                Link("maplibre.org", destination: URL(string: "https://maplibre.org")!)
                NavigationLink("MapLibre Native license text") { MapLibreLicenseView() }
            } header: {
                Text("Map")
            }
        }
        .navigationTitle("Licenses")
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
