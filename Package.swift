// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Financas",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Financas", targets: ["Financas"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .executableTarget(name: "Financas", dependencies: ["CSQLite"]),
        .testTarget(name: "FinancasTests", dependencies: ["Financas"])
    ]
)
