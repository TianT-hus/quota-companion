import Darwin
import Foundation

public final class QuotaSocketServer: @unchecked Sendable {
    private let path: String
    private let queue = DispatchQueue(label: "quota-companion.socket", qos: .utility)
    private let requestHandler: @Sendable (String) -> Data
    private var descriptor: Int32 = -1
    private var running = false

    public init(path: String, requestHandler: @escaping @Sendable (String) -> Data) {
        self.path = path
        self.requestHandler = requestHandler
    }

    deinit { stop() }

    public func start() throws {
        guard !running else { return }
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        Darwin.unlink(path)
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.ENOTSOCK) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let copied = path.withCString { source in
            withUnsafeMutableBytes(of: &address.sun_path) { bytes -> Bool in
                guard source.strlen < bytes.count else { return false }
                bytes.initializeMemory(as: UInt8.self, repeating: 0)
                bytes.copyBytes(from: UnsafeRawBufferPointer(start: source, count: source.strlen))
                return true
            }
        }
        guard copied else {
            Darwin.close(fd)
            throw POSIXError(.ENAMETOOLONG)
        }

        let length = socklen_t(MemoryLayout<sa_family_t>.size + path.utf8.count + 1)
        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, length) }
        }
        guard bindResult == 0, Darwin.listen(fd, 4) == 0 else {
            Darwin.close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EINVAL)
        }
        Darwin.chmod(path, S_IRUSR | S_IWUSR)
        descriptor = fd
        running = true

        queue.async { [weak self] in self?.acceptLoop() }
    }

    public func stop() {
        running = false
        if descriptor >= 0 {
            Darwin.shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor)
            descriptor = -1
        }
        Darwin.unlink(path)
    }

    private func acceptLoop() {
        while running {
            let client = Darwin.accept(descriptor, nil, nil)
            guard client >= 0 else { continue }
            var requestBytes = [UInt8](repeating: 0, count: 256)
            let count = Darwin.recv(client, &requestBytes, requestBytes.count, 0)
            let request = count > 0
                ? String(decoding: requestBytes.prefix(count), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                : "snapshot"
            var response = requestHandler(request)
            response.append(0x0A)
            response.withUnsafeBytes { bytes in
                _ = Darwin.send(client, bytes.baseAddress, bytes.count, 0)
            }
            Darwin.close(client)
        }
    }
}

public enum QuotaSocketClient {
    public static func request(path: String, message: String = "snapshot") -> Data? {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }

        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let copied = path.withCString { source in
            withUnsafeMutableBytes(of: &address.sun_path) { bytes -> Bool in
                guard source.strlen < bytes.count else { return false }
                bytes.initializeMemory(as: UInt8.self, repeating: 0)
                bytes.copyBytes(from: UnsafeRawBufferPointer(start: source, count: source.strlen))
                return true
            }
        }
        guard copied else { return nil }

        let length = socklen_t(MemoryLayout<sa_family_t>.size + path.utf8.count + 1)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, length) }
        }
        guard connected == 0 else { return nil }
        _ = "\(message)\n".withCString { Darwin.send(fd, $0, strlen($0), 0) }

        var output = Data()
        var chunk = [UInt8](repeating: 0, count: 8_192)
        while true {
            let count = Darwin.recv(fd, &chunk, chunk.count, 0)
            if count <= 0 { break }
            output.append(contentsOf: chunk.prefix(count))
            if output.contains(0x0A) { break }
        }
        if let newline = output.firstIndex(of: 0x0A) { output = output.prefix(upTo: newline) }
        return output.isEmpty ? nil : output
    }

    public static func read(path: String) -> Data? { request(path: path) }
}

private extension UnsafePointer<CChar> {
    var strlen: Int { Darwin.strlen(self) }
}
