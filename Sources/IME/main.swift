import Cocoa
import MLHCore
import InputMethodKit

// Entry point of the mlh input method server.
let connectionName = (Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String)
    ?? "com.github.kazu.inputmethod.mlh_Connection"

// IMKServer must stay alive for the whole lifetime of the process.
let server: IMKServer? = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier)

// `make install` stops mlh with SIGTERM. Exit cleanly on it: macOS counts an
// input method killed by a signal as having died, and after too many deaths
// it no longer launches it for the apps that are already running.
signal(SIGTERM, SIG_IGN)
let terminationSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
terminationSource.setEventHandler { exit(0) }
terminationSource.resume()

// Load the kanji converter now rather than on the first conversion.
DispatchQueue.main.async { MLHShared.shared.warmUp() }

withExtendedLifetime((server, terminationSource)) {
    NSApplication.shared.run()
}
