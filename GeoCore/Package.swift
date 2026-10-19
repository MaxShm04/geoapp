// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GeoCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GeoCore", targets: ["GeoCore"]),
    ],
    targets: [
        .target(
            name: "GeoCore",
            resources: [
                .copy("Resources/countries.json"),
                .copy("Resources/cities.tsv"),
                .copy("Resources/city_names.tsv"),
                .copy("Resources/regions.json.z"),
                .copy("Resources/Districts"),
                .copy("Resources/CityDetail"),
                .copy("Resources/data_version.txt"),
            ]
        ),
        .testTarget(name: "GeoCoreTests", dependencies: ["GeoCore"]),
    ]
)
