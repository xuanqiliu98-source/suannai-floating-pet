// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "YunduoFloatingPet",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "YunduoPet", targets: ["YunduoPet"])
    ],
    targets: [
        .executableTarget(
            name: "YunduoPet",
            resources: [.process("Resources")]
        )
    ]
)
