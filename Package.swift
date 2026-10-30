// swift-tools-version: 6.1
// mlh (modeless Japanese input, after Emacs egg-mlh.el) for macOS.
// `make build` builds the input method bundle from these products.

import Foundation
import PackageDescription

// azooKey's neural conversion (Zenzai), which can take the text before the
// conversion as context: MLH_ZENZAI=cpu (the default on macOS), gpu or off.
#if os(macOS)
let zenzai = ProcessInfo.processInfo.environment["MLH_ZENZAI"] ?? "cpu"
#else
let zenzai = ProcessInfo.processInfo.environment["MLH_ZENZAI"] ?? "off"
#endif
let zenzaiTraits: Set<Package.Dependency.Trait> =
    zenzai == "gpu" ? ["Zenzai"] : zenzai == "cpu" ? ["ZenzaiCPU"] : []

// Modules that import a Zenzai build of azooKey need C++ interoperability.
let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]
    + (zenzaiTraits.isEmpty ? [] : [.interoperabilityMode(.Cxx)])
// AzooKeyKanaKanjiConverter always links llama.framework; without Zenzai it
// is unused, so drop it and the app needs no copy. With Zenzai the app
// carries it in Contents/Frameworks.
let appLinkerFlags: [String] = ["-Xlinker", "-dead_strip_dylibs"]
    + (zenzaiTraits.isEmpty ? [] : ["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])

#if os(Linux)
let bridgeTarget: Target = .target(name: "MLHBridge", dependencies: ["MLHCore"], path: "Sources", exclude: ["Core", "IME/CandidatePanel.swift", "IME/MLHInputController.swift", "IME/main.swift"], sources: ["LinuxBridge", "IME/TextContext.swift", "IME/ExecuteTask.swift"], swiftSettings: swift5)
#endif

let package = Package(
    name: "mlh",
    // llama.framework (Zenzai) needs macOS 13.3.
    platforms: [zenzaiTraits.isEmpty ? .macOS(.v13) : .macOS("13.3")],
    dependencies: [
        // Local kana-kanji conversion (the default kanji backend).
        .package(url: "https://github.com/azooKey/AzooKeyKanaKanjiConverter", .upToNextMinor(from: "0.11.2"),
                 traits: zenzaiTraits),
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
                .unsafeFlags(appLinkerFlags),
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
