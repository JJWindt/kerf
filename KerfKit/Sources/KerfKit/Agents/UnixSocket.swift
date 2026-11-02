import Darwin
import Foundation

/// One line of JSON per connection over a Unix socket: `kerf` sends, the app may answer.
public enum UnixSocket {
    /// Sends a line. With `waitForReply`, waits up to `timeout` for one line back.
    /// Nil when nobody listens or nothing came back.
    public static func send(_ line: Data, to path: String, waitForReply: Bool, timeout: TimeInterval) -> Data? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        guard var address = socketAddress(path) else { return nil }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0, writeAll(fd, line + Data([0x0A])) else { return nil }
        guard waitForReply else { return Data() }
        return readLine(fd, timeout: timeout)
    }

    static func socketAddress(_ path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        return address
    }

    static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if written <= 0 { return false }
                offset += written
            }
            return true
        }
    }

    /// Reads up to the first newline, or nil after `timeout` or a closed connection.
    static func readLine(_ fd: Int32, timeout: TimeInterval, limit: Int = 4 << 20) -> Data? {
        var data = Data()
        let deadline = Date().addingTimeInterval(timeout)
        var chunk = [UInt8](repeating: 0, count: 65536)
        while data.count < limit {
            let left = deadline.timeIntervalSinceNow
            guard left > 0 else { return nil }
            var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&poller, 1, Int32(min(left, 3600) * 1000))
            guard ready > 0 else { return nil }
            let count = read(fd, &chunk, chunk.count)
            guard count > 0 else { return data.isEmpty ? nil : data }
            if let newline = chunk[0..<count].firstIndex(of: 0x0A) {
                data.append(contentsOf: chunk[0..<newline])
                return data
            }
            data.append(contentsOf: chunk[0..<count])
        }
        return nil
    }
}

/// The app's end: one connection per message, answered (or not) when you decide.
public final class UnixSocketServer: @unchecked Sendable {
    /// A message that may still need an answer. Answer once; `onClose` fires when the sender gives up.
    public final class Connection: @unchecked Sendable {
        private let fd: Int32
        private let lock = NSLock()
        private var finished = false
        private var watcher: DispatchSourceRead?
        public var onClose: (@Sendable () -> Void)?

        init(fd: Int32) {
            self.fd = fd
        }

        public func reply(_ data: Data?) {
            lock.lock()
            defer { lock.unlock() }
            guard !finished else { return }
            finished = true
            if let data { _ = UnixSocket.writeAll(fd, data + Data([0x0A])) }
            watcher?.cancel()
            watcher = nil
            close(fd)
        }

        /// Notices when `kerf` is gone, for instance because Claude Code stopped waiting. The source
        /// keeps the connection alive until it is answered or closed.
        func watch(on queue: DispatchQueue) {
            // A suspended source must never be released, so only make one for an open connection.
            lock.lock()
            defer { lock.unlock() }
            guard !finished else { return }
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [self] in
                var byte: UInt8 = 0
                if recv(fd, &byte, 1, MSG_PEEK | MSG_DONTWAIT) <= 0 {
                    lock.lock()
                    let wasOpen = !finished
                    finished = true
                    watcher?.cancel()
                    watcher = nil
                    if wasOpen { close(fd) }
                    lock.unlock()
                    if wasOpen { onClose?() }
                }
            }
            watcher = source
            source.resume()
        }
    }

    public typealias Handler = @Sendable (Data, Connection) -> Void

    private let path: String
    private let listener: Int32
    private let source: DispatchSourceRead
    /// The socket file this server made; a newer server may have replaced it since.
    private let inode: ino_t
    private let queue = DispatchQueue(label: "nl.paulboerma.kerf.socket", attributes: .concurrent)

    public init(path: String, handler: @escaping Handler) throws {
        self.path = path
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, var address = UnixSocket.socketAddress(path) else { throw POSIXError(.EINVAL) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(fd, 32) == 0 else {
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        chmod(path, 0o600)
        var info = stat()
        stat(path, &info)
        inode = info.st_ino
        listener = fd
        source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        let queue = self.queue
        source.setEventHandler {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            var on: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            queue.async {
                guard let line = UnixSocket.readLine(client, timeout: 5) else {
                    close(client)
                    return
                }
                let connection = Connection(fd: client)
                handler(line, connection)
                connection.watch(on: queue)
            }
        }
        source.resume()
    }

    /// Closes, and removes the socket file only if it is still this server's: an old copy of the
    /// app quitting must not take a new copy's socket with it.
    public func stop() {
        source.cancel()
        close(listener)
        var info = stat()
        if stat(path, &info) == 0, info.st_ino == inode { unlink(path) }
    }
}
