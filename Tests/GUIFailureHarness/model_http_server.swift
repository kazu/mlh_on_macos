import Foundation
import Darwin

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let portFile = URL(fileURLWithPath: CommandLine.arguments[2])
let readyFile = URL(fileURLWithPath: CommandLine.arguments[3])
let releaseFile = URL(fileURLWithPath: CommandLine.arguments[4])

signal(SIGPIPE, SIG_IGN)
let listener = socket(AF_INET, SOCK_STREAM, 0)
guard listener >= 0 else { fatalError("socket failed") }
var address = sockaddr_in()
address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
address.sin_family = sa_family_t(AF_INET)
address.sin_addr = in_addr(s_addr: in_addr_t(0x7f000001).bigEndian)
address.sin_port = 0
let bound = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
    }
}
guard bound == 0, listen(listener, 8) == 0 else { fatalError("bind or listen failed") }
var length = socklen_t(MemoryLayout<sockaddr_in>.size)
let named = withUnsafeMutablePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        getsockname(listener, $0, &length)
    }
}
guard named == 0 else { fatalError("getsockname failed") }
try String(address.sin_port.bigEndian).write(to: portFile, atomically: true, encoding: .utf8)

@Sendable func sendAll(_ bytes: [UInt8], to client: Int32) {
    bytes.withUnsafeBytes { buffer in
        var offset = 0
        while offset < buffer.count {
            let written = write(client, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
            if written <= 0 { return }
            offset += written
        }
    }
}

func respond(to client: Int32) {
    defer { close(client) }
    var request = [UInt8](repeating: 0, count: 4096)
    let count = read(client, &request, request.count)
    guard count > 0,
          let firstLine = String(bytes: request[..<count], encoding: .utf8)?.components(separatedBy: "\r\n").first,
          let path = firstLine.split(separator: " ").dropFirst().first else { return }

    if path == "/error.gguf" || path == "/missing.gguf" {
        let status = path == "/error.gguf" ? "500 Internal Server Error" : "404 Not Found"
        sendAll(Array("HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), to: client)
        return
    }

    let slow = path == "/slow.gguf" || path == "/unknown.gguf"
    let payload: [UInt8]
    if slow {
        payload = Array("GGUF".utf8) + [UInt8](repeating: 120, count: 65532)
    } else {
        let name = String(path.dropFirst())
        guard name == "model.gguf" || name == "invalid.gguf",
              let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return }
        payload = Array(data)
    }
    let sizeHeader = path == "/unknown.gguf" ? "" : "Content-Length: \(payload.count)\r\n"
    sendAll(Array("HTTP/1.1 200 OK\r\n\(sizeHeader)Connection: close\r\n\r\n".utf8), to: client)
    if slow {
        sendAll(Array(payload[..<32768]), to: client)
        FileManager.default.createFile(atPath: readyFile.path, contents: nil)
        let deadline = Date().addingTimeInterval(10)
        while !FileManager.default.fileExists(atPath: releaseFile.path) && Date() < deadline {
            usleep(20_000)
        }
        sendAll(Array(payload[32768...]), to: client)
    } else {
        sendAll(payload, to: client)
    }
}

while true {
    let client = accept(listener, nil, nil)
    if client >= 0 {
        DispatchQueue.global().async { respond(to: client) }
    }
}
