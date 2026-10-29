// swift-tools-version: 6.1
// mlh (modeless Japanese input, after Emacs egg-mlh.el) for macOS.
// `make build` builds the input method bundle from these products.

import PackageDescription

let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]
#if os(Linux)
let bridgeTarget: Target = .target(name: "MLHBridge", dependencies: ["MLHCore"], path: "Sources", exclude: ["Core", "IME/CandidatePanel.swift", "IME/MLHInputController.swift", "IME/main.swift"], sources: ["LinuxBridge", "IME/TextContext.swift", "IME/ExecuteTask.swift"], swiftSettings: swift5)
#endif

let package = Package(
    name: "mlh",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Local kana-kanji conversion (the default kanji backend).
        .package(url: "https://github.com/azooKey/AzooKeyKanaKanjiConverter", .upToNextMinor(from: "0.11.2")),
    ],
    targets: [
        .target(
            name: "MLHCore",
            dependencies: [
                .product(name: "KanaKanjiConverterModule", package: "AzooKeyKanaKanjiConverter"),
            ],
            path: "Sources/Core",
            swiftSettings: swift5
        ),
        .executableTarget(
            name: "mlh",
            dependencies: ["MLHCore"],
            path: "Sources/IME",
            swiftSettings: swift5,
            linkerSettings: [
                .linkedFramework("InputMethodKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("Cocoa"),
                // AzooKeyKanaKanjiConverter always links llama.framework, which
                // only its Zenzai traits use; drop it so the app needs no copy.
                .unsafeFlags(["-Xlinker", "-dead_strip_dylibs"]),
            ]
        ),
        .executableTarget(
            name: "mlh-tests",
            dependencies: ["MLHCore"],
            path: "Tests",
            swiftSettings: swift5,
            linkerSettings: [.unsafeFlags(["-Xlinker", "-dead_strip_dylibs"])]
        ),
    ]
)

#if os(Linux)
package.targets.removeAll { $0.name == "mlh" }
package.targets.append(bridgeTarget)
package.products.append(.library(name: "MLHBridge", type: .dynamic, targets: ["MLHBridge"]))
#endif
