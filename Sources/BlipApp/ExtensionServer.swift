import Foundation
import Darwin
import BlipShared

/// Stream socket ~/.blip/blip-ext.sock for the Copilot CLI extension(s).
/// One connection per Copilot session; messages are JSON, one per line.
final class ExtensionServer {
    private final class Client {
        let fd: Int32
        var source: DispatchSourceRead?
        var buffer = Data()
        var sessionId: String?
        init(fd: Int32) { self.fd = fd }
    }

    /// (sessionId, message)
    var onMessage: ((String, [String: Any]) -> Void)?
    /// A session's connection is gone (session ended or extension crashed).
    var onDisconnect: ((String) -> Void)?

    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var clients: [Int32: Client] = [:]

    enum ServerError: Error { case socket, bind(Int32), listen(Int32) }

    func start() throws {
        let path = BlipPaths.extensionSocket.path
        unlink(path)
        listenFD = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { throw ServerError.socket }
        let bound = BlipSocket.withAddress(path) { sa, len in bind(listenFD, sa, len) } ?? -1
        guard bound == 0 else { throw ServerError.bind(errno) }
        guard listen(listenFD, 16) == 0 else { throw ServerError.listen(errno) }
        chmod(path, 0o600)
        setNonBlocking(listenFD)

        let source = DispatchSource.makeReadSource(fileDescriptor: listenFD, queue: .main)
        source.setEventHandler { [weak self] in self?.acceptClients() }
        source.resume()
        acceptSource = source
    }

    func stop() {
        acceptSource?.cancel()
        for client in clients.values { client.source?.cancel() }
        clients.removeAll()
        if listenFD >= 0 { close(listenFD) }
        unlink(BlipPaths.extensionSocket.path)
    }

    /// Sends a message to the session's extension.
    @discardableResult
    func send(to sessionId: String, _ message: [String: Any]) -> Bool {
        guard let client = clients.values.first(where: { $0.sessionId == sessionId }),
              var data = try? JSONSerialization.data(withJSONObject: message) else { return false }
        data.append(0x0A)
        return data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = write(client.fd, raw.baseAddress! + offset, raw.count - offset)
                if n > 0 { offset += n; continue }
                if n < 0 && (errno == EAGAIN || errno == EINTR) { usleep(1000); continue }
                return false
            }
            return true
        }
    }

    // MARK: Internals

    private func acceptClients() {
        while true {
            let fd = accept(listenFD, nil, nil)
            guard fd >= 0 else { return }
            setNonBlocking(fd)
            var on: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

            let client = Client(fd: fd)
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
            source.setEventHandler { [weak self, weak client] in
                guard let self, let client else { return }
                self.read(client)
            }
            source.setCancelHandler { close(fd) }
            client.source = source
            clients[fd] = client
            source.resume()
        }
    }

    private func read(_ client: Client) {
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let n = Darwin.read(client.fd, &chunk, chunk.count)
            if n > 0 {
                client.buffer.append(contentsOf: chunk[0..<n])
                continue
            }
            if n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) { break }
            disconnect(client) // n == 0 (closed) or error
            return
        }
        while let index = client.buffer.firstIndex(of: 0x0A) {
            let line = client.buffer[client.buffer.startIndex..<index]
            client.buffer.removeSubrange(client.buffer.startIndex...index)
            guard let message = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                  let sessionId = message["sessionId"] as? String, !sessionId.isEmpty else { continue }
            client.sessionId = sessionId
            onMessage?(sessionId, message)
        }
    }

    private func disconnect(_ client: Client) {
        clients[client.fd] = nil
        client.source?.cancel()
        if let sessionId = client.sessionId { onDisconnect?(sessionId) }
    }

    private func setNonBlocking(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    }
}
