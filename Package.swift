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
#if os(macOS)
let settingsBackendLinkerSettings: [LinkerSetting] = [.unsafeFlags(
    ["-Xlinker", "-dead_strip_dylibs"]
        + (zenzaiTraits.isEmpty ? [] : ["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../../../../Frameworks"])
)]
#else
let settingsBackendLinkerSettings: [LinkerSetting] = []
#endif

#if os(Linux)
let bridgeTarget: Target = .target(name: "MLHBridge", dependencies: ["MLHCore"], path: "Sources", exclude: ["Core", "IME/CandidatePanel.swift", "IME/MLHInputController.swift", "IME/main.swift"], sources: ["LinuxBridge", "IME/TextContext.swift", "IME/ExecuteTask.swift"], swiftSettings: swift5)
#endif

var coreDependencies: [Target.Dependency] = [
    .product(name: "KanaKanjiConverterModule", package: "AzooKeyKanaKanjiConverter"),
]
#if os(Linux)
coreDependencies.append("CLinuxSecret")
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
            dependencies: coreDependencies,
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
            name: "mlh-settings",
            path: "Sources/SettingsGUI",
            swiftSettings: swift5,
            linkerSettings: [.linkedFramework("AppKit")]
        ),
        .executableTarget(
            name: "mlh-settings-backend",
            dependencies: ["MLHCore"],
            path: "Sources/SettingsBackendCLI",
            swiftSettings: swift5,
            linkerSettings: settingsBackendLinkerSettings
        ),
        .executableTarget(
            name: "mlh-tests",
            dependencies: ["MLHCore"],
            path: "Tests",
            exclude: ["GUIFailureHarness"],
            swiftSettings: swift5,
            linkerSettings: settingsBackendLinkerSettings
        ),
    ]
)

#if os(Linux)
package.targets.removeAll { $0.name == "mlh" || $0.name == "mlh-settings" }
package.targets.append(.systemLibrary(name: "CLibSecret", pkgConfig: "libsecret-1", providers: [.apt(["libsecret-1-dev"])]))
package.targets.append(.target(name: "CLinuxSecret", dependencies: ["CLibSecret"], path: "Sources/CLinuxSecret"))
package.targets.append(bridgeTarget)
package.products.append(.library(name: "MLHBridge", type: .dynamic, targets: ["MLHBridge"]))
#endif
