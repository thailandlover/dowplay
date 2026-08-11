//
//  LocalHTTPServer.swift
//  RunnerTests
//
//  Minimal HTTP/1.1 file server used by the download tests. It runs inside the test process so
//  the suite controls the network completely: it can serve a body slowly, honour range requests
//  (which is what URLSession needs to continue an interrupted transfer), or drop the connection
//  in the middle of a transfer to reproduce a network outage.
//

import Foundation
import Network

final class LocalHTTPServer {

    struct Configuration {
        var chunkSize: Int = 32 * 1024
        var chunkDelay: TimeInterval = 0
        /// Closes the connection abruptly once this many body bytes have been written.
        var dropAfterBytes: Int?
        /// Answers every request with this status and a short error body instead of the media.
        var errorStatus: Int?
        /// Stops sending after this many body bytes while holding the connection open, the way a
        /// transfer stalls when the connection silently dies.
        var hangAfterBytes: Int?
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.dowplay.tests.httpserver")
    private let body: Data
    private let lock = NSLock()
    private var storedConfiguration = Configuration()
    private var requestHeads: [String] = []

    private(set) var port: UInt16 = 0

    var configuration: Configuration {
        get {
            lock.lock(); defer { lock.unlock() }
            return storedConfiguration
        }
        set {
            lock.lock(); storedConfiguration = newValue; lock.unlock()
        }
    }

    /// Every request head the server has answered, newest last.
    var requests: [String] {
        lock.lock(); defer { lock.unlock() }
        return requestHeads
    }

    /// The `Range` header values received so far. A non empty list proves a transfer continued
    /// from resume data instead of starting over.
    var rangeRequests: [String] {
        return requests.compactMap { head in
            head.split(separator: "\r\n")
                .first(where: { $0.lowercased().hasPrefix("range:") })
                .map { String($0) }
        }
    }

    init(body: Data) throws {
        self.body = body
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters, on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
    }

    func start() throws {
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 10) == .success, let boundPort = listener.port?.rawValue else {
            throw NSError(domain: "LocalHTTPServer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The test server did not start"])
        }
        port = boundPort
    }

    func stop() {
        listener.cancel()
    }

    func url(path: String = "/media.mp4") -> URL {
        return URL(string: "http://127.0.0.1:\(port)\(path)")!
    }

    //MARK: - Request handling

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHead(on: connection, buffer: Data())
    }

    private func receiveHead(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            var buffer = buffer
            if let data = data { buffer.append(data) }

            if let headEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[buffer.startIndex..<headEnd.lowerBound], as: UTF8.self)
                self.respond(to: head, on: connection)
                return
            }

            if error != nil || isComplete {
                connection.cancel()
                return
            }
            self.receiveHead(on: connection, buffer: buffer)
        }
    }

    private func respond(to head: String, on connection: NWConnection) {
        lock.lock(); requestHeads.append(head); lock.unlock()

        if let status = configuration.errorStatus {
            let message = Data("the link is not valid".utf8)
            let header = "HTTP/1.1 \(status) Error\r\nContent-Length: \(message.count)\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(header.utf8) + message, completion: .contentProcessed({ _ in
                connection.cancel()
            }))
            return
        }

        let start = min(LocalHTTPServer.rangeStart(in: head) ?? 0, body.count)
        let payload = body.subdata(in: start..<body.count)

        var header = start > 0
            ? "HTTP/1.1 206 Partial Content\r\nContent-Range: bytes \(start)-\(body.count - 1)/\(body.count)\r\n"
            : "HTTP/1.1 200 OK\r\n"
        header += "Content-Length: \(payload.count)\r\n"
        header += "Content-Type: application/octet-stream\r\n"
        // Accept-Ranges plus a validator are what make URLSession produce resume data.
        header += "Accept-Ranges: bytes\r\n"
        header += "ETag: \"dowplay-test\"\r\n"
        header += "Last-Modified: Mon, 01 Jan 2024 00:00:00 GMT\r\n"
        header += "Connection: close\r\n\r\n"

        connection.send(content: Data(header.utf8), completion: .contentProcessed({ [weak self] error in
            guard let self = self, error == nil else {
                connection.cancel()
                return
            }
            self.sendBody(payload, from: 0, on: connection)
        }))
    }

    private func sendBody(_ payload: Data, from offset: Int, on connection: NWConnection) {
        let configuration = self.configuration

        if let drop = configuration.dropAfterBytes, offset >= drop {
            // Truncate the response the way a dropped connection does.
            connection.forceCancel()
            return
        }

        if let hang = configuration.hangAfterBytes, offset >= hang {
            // Send nothing more and keep the connection open: the client just waits.
            return
        }

        guard offset < payload.count else {
            connection.send(content: nil, isComplete: true, completion: .contentProcessed({ _ in
                connection.cancel()
            }))
            return
        }

        let end = min(offset + max(configuration.chunkSize, 1), payload.count)
        let chunk = payload.subdata(in: offset..<end)
        connection.send(content: chunk, completion: .contentProcessed({ [weak self] error in
            guard let self = self, error == nil else {
                connection.cancel()
                return
            }
            if configuration.chunkDelay > 0 {
                self.queue.asyncAfter(deadline: .now() + configuration.chunkDelay) {
                    self.sendBody(payload, from: end, on: connection)
                }
            } else {
                self.sendBody(payload, from: end, on: connection)
            }
        }))
    }

    private static func rangeStart(in head: String) -> Int? {
        guard let line = head.split(separator: "\r\n").first(where: { $0.lowercased().hasPrefix("range:") }) else {
            return nil
        }
        guard let equals = line.firstIndex(of: "=") else { return nil }
        let value = line[line.index(after: equals)...]
        let bounds = value.split(separator: "-", omittingEmptySubsequences: false)
        return bounds.first.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }
}
