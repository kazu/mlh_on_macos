#if os(Linux)
import Foundation
import FoundationNetworking
import MLHCore

private final class OpenAIDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    weak var owner: OpenAITask?

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        owner?.receive(response: response)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) { owner?.receive(data: data) }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        owner?.complete(error: error)
        session.finishTasksAndInvalidate()
    }
}

final class OpenAITask: ExecuteTaskBase, ExecuteTask, @unchecked Sendable {
    static var hasAPIKey: Bool { ProcessInfo.processInfo.environment["OPENAI_API_KEY"] != nil }

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private var reply = ""
    private var status = 0

    init(source: String, config: OpenAI.Config) {
        super.init(source: source)
        let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        guard var request = OpenAI.request(source, config: config, apiKey: key) else {
            DispatchQueue.main.async { self.finish(nil) }
            return
        }
        request.timeoutInterval = Self.timeout
        let delegate = OpenAIDelegate()
        delegate.owner = self
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        self.session = session
        task = session.dataTask(with: request)
        task?.resume()
    }

    fileprivate func receive(response: URLResponse) {
        status = (response as? HTTPURLResponse)?.statusCode ?? 0
    }

    fileprivate func receive(data: Data) {
        buffer.append(data)
        guard status == 200 else { return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = String(decoding: buffer[..<newline], as: UTF8.self)
            buffer.removeSubrange(...newline)
            if case .delta(let delta) = OpenAI.parseStreamLine(line) {
                reply += delta
                let progress = reply
                DispatchQueue.main.async { self.partial = progress; self.onProgress?(progress) }
            }
        }
    }

    fileprivate func complete(error: Error?) {
        if let error { fputs("OpenAI request failed: \(error.localizedDescription)\n", stderr) }
        if status != 200 {
            let message = OpenAI.errorMessage(buffer) ?? String(decoding: buffer, as: UTF8.self)
            fputs("OpenAI HTTP \(status): \(message)\n", stderr)
        }
        let result = error == nil && status == 200 && !reply.isEmpty ? reply.trimmingCharacters(in: .newlines) : nil
        DispatchQueue.main.async { self.finish(result) }
        self.session = nil
    }

    override func cancel() { task?.cancel() }
}
#endif
