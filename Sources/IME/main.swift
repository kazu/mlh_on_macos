import Cocoa
import InputMethodKit

// Entry point of the mlh input method server.
let connectionName = (Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String)
    ?? "com.github.kazu.inputmethod.mlh_Connection"

// IMKServer must stay alive for the whole lifetime of the process.
let server: IMKServer? = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier)

withExtendedLifetime(server) {
    NSApplication.shared.run()
}
