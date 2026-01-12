//
//  OrbitCLIBridgeService.swift
//  Deck
//
//  Local HTTP bridge for Orbit clipboard access
//

import AppKit
import Foundation
import Network
import Observation

@Observable
final class OrbitCLIBridgeService {
    static let shared = OrbitCLIBridgeService()

    private static let port: UInt16 = 53129
    private static let maxHeaderBytes = 32 * 1024
    private static let maxBodyBytes = 10 * 1024 * 1024

    @ObservationIgnored
    private let ioQueue = DispatchQueue(label: "deck.orbit.bridge", qos: .utility)

    @ObservationIgnored
    private var listener: NWListener?
    @ObservationIgnored
    private var activeConnections: [ObjectIdentifier: OrbitCLIBridgeConnection] = [:]
    @ObservationIgnored
    private let connectionsLock = NSLock()

    private(set) var isListening = false
    private(set) var lastError: String?

    private init() {}

    func start() {
        guard listener == nil else { return }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredInterfaceType = .loopback

            let port = NWEndpoint.Port(rawValue: Self.port)!
            let listener = try NWListener(using: parameters, on: port)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                self?.handleListenerState(state, port: Int(port.rawValue))
            }
            listener.start(queue: ioQueue)
            self.listener = listener
        } catch {
            log.error("Orbit CLI bridge failed to start: \(error)")
            updateListeningState(isListening: false, error: error.localizedDescription)
        }
    }

    private func handleListenerState(_ state: NWListener.State, port: Int) {
        switch state {
        case .ready:
            log.info("Orbit CLI bridge listening on 127.0.0.1:\(port)")
            updateListeningState(isListening: true, error: nil)
        case .failed(let error):
            log.error("Orbit CLI bridge listener failed: \(error)")
            listener?.cancel()
            listener = nil
            updateListeningState(isListening: false, error: error.localizedDescription)
        case .cancelled:
            updateListeningState(isListening: false, error: nil)
        default:
            break
        }
    }

    private func updateListeningState(isListening: Bool, error: String?) {
        let updateBlock = { [weak self] in
            self?.isListening = isListening
            if let error {
                self?.lastError = error
            } else if isListening {
                self?.lastError = nil
            }
        }
        if Thread.isMainThread {
            updateBlock()
        } else {
            DispatchQueue.main.async(execute: updateBlock)
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        if case let .hostPort(host, _) = connection.endpoint,
           !Self.isLoopbackHost(host) {
            connection.cancel()
            return
        }

        let connectionId = ObjectIdentifier(connection)
        let handler = OrbitCLIBridgeConnection(
            connection: connection,
            queue: ioQueue,
            maxHeaderBytes: Self.maxHeaderBytes,
            maxBodyBytes: Self.maxBodyBytes,
            requestHandler: { request, respond in
                Task { @MainActor in
                    Self.handleRequest(request, respond: respond)
                }
            },
            onFinish: { [weak self] in
                self?.removeConnection(id: connectionId)
            }
        )
        connectionsLock.lock()
        activeConnections[connectionId] = handler
        connectionsLock.unlock()
        handler.start()
    }

    private static func isLoopbackHost(_ host: NWEndpoint.Host) -> Bool {
        let value = host.debugDescription.lowercased()
        return value == "127.0.0.1" || value == "::1" || value == "localhost"
    }

    private func removeConnection(id: ObjectIdentifier) {
        connectionsLock.lock()
        activeConnections.removeValue(forKey: id)
        connectionsLock.unlock()
    }
}

private struct OrbitCLIBridgeRequest: Sendable {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data
}

private struct OrbitCLIBridgeResponse: Sendable {
    let statusCode: Int
    let reason: String
    let headers: [String: String]
    let body: Data

    static func ok(_ body: String, contentType: String = "text/plain; charset=utf-8") -> OrbitCLIBridgeResponse {
        OrbitCLIBridgeResponse(
            statusCode: 200,
            reason: "OK",
            headers: ["Content-Type": contentType],
            body: Data(body.utf8)
        )
    }

    static func okData(_ body: Data, contentType: String = "application/json; charset=utf-8") -> OrbitCLIBridgeResponse {
        OrbitCLIBridgeResponse(
            statusCode: 200,
            reason: "OK",
            headers: ["Content-Type": contentType],
            body: body
        )
    }

    static func badRequest(_ message: String) -> OrbitCLIBridgeResponse {
        OrbitCLIBridgeResponse(
            statusCode: 400,
            reason: "Bad Request",
            headers: ["Content-Type": "text/plain; charset=utf-8"],
            body: Data(message.utf8)
        )
    }

    static func unauthorized(_ message: String) -> OrbitCLIBridgeResponse {
        OrbitCLIBridgeResponse(
            statusCode: 401,
            reason: "Unauthorized",
            headers: ["Content-Type": "text/plain; charset=utf-8"],
            body: Data(message.utf8)
        )
    }

    static func notFound() -> OrbitCLIBridgeResponse {
        OrbitCLIBridgeResponse(
            statusCode: 404,
            reason: "Not Found",
            headers: ["Content-Type": "text/plain; charset=utf-8"],
            body: Data("Not Found".utf8)
        )
    }

    static func methodNotAllowed(allowed: String) -> OrbitCLIBridgeResponse {
        OrbitCLIBridgeResponse(
            statusCode: 405,
            reason: "Method Not Allowed",
            headers: [
                "Content-Type": "text/plain; charset=utf-8",
                "Allow": allowed
            ],
            body: Data("Method Not Allowed".utf8)
        )
    }

    static func payloadTooLarge() -> OrbitCLIBridgeResponse {
        OrbitCLIBridgeResponse(
            statusCode: 413,
            reason: "Payload Too Large",
            headers: ["Content-Type": "text/plain; charset=utf-8"],
            body: Data("Payload Too Large".utf8)
        )
    }
}

private final class OrbitCLIBridgeConnection {
    private enum ParseResult {
        case needMore
        case request(OrbitCLIBridgeRequest)
        case invalid(OrbitCLIBridgeResponse)
    }

    private struct LineBreak {
        let lineEnd: Int
        let nextIndex: Int
    }

    private let connection: NWConnection
    private let queue: DispatchQueue
    private let maxHeaderBytes: Int
    private let maxBodyBytes: Int
    private let requestHandler: @Sendable (OrbitCLIBridgeRequest, @escaping @Sendable (OrbitCLIBridgeResponse) -> Void) -> Void
    private let onFinish: (() -> Void)?
    private var buffer = Data()
    private var hasResponded = false
    private var didFinish = false

    init(
        connection: NWConnection,
        queue: DispatchQueue,
        maxHeaderBytes: Int,
        maxBodyBytes: Int,
        requestHandler: @escaping @Sendable (OrbitCLIBridgeRequest, @escaping @Sendable (OrbitCLIBridgeResponse) -> Void) -> Void,
        onFinish: (() -> Void)? = nil
    ) {
        self.connection = connection
        self.queue = queue
        self.maxHeaderBytes = maxHeaderBytes
        self.maxBodyBytes = maxBodyBytes
        self.requestHandler = requestHandler
        self.onFinish = onFinish
    }

    func start() {
        connection.start(queue: queue)
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data {
                buffer.append(data)
            }

            if let error {
                log.debug("Orbit CLI bridge connection error: \(error)")
                finish()
                return
            }

            switch parseRequest() {
            case .needMore:
                if isComplete {
                    sendResponse(.badRequest("Incomplete request"))
                } else {
                    receive()
                }
            case .request(let request):
                requestHandler(request) { [weak self] response in
                    guard let self else { return }
                    self.queue.async { [weak self] in
                        self?.sendResponse(response)
                    }
                }
            case .invalid(let response):
                sendResponse(response)
            }
        }
    }

    private func parseRequest() -> ParseResult {
        if buffer.count > maxHeaderBytes + maxBodyBytes {
            return .invalid(.payloadTooLarge())
        }

        guard let headerInfo = headerDelimiter(in: buffer) else {
            if buffer.count > maxHeaderBytes {
                return .invalid(.payloadTooLarge())
            }
            return .needMore
        }

        let headerData = buffer.subdata(in: 0..<headerInfo.headerEnd)
        let headerString = String(decoding: headerData, as: UTF8.self)
        let lines = headerString.split(whereSeparator: \.isNewline)

        guard let requestLine = lines.first else {
            return .invalid(.badRequest("Missing request line"))
        }

        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count >= 2 else {
            return .invalid(.badRequest("Invalid request line"))
        }

        let method = String(requestParts[0])
        let target = String(requestParts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }

        let bodyStart = headerInfo.bodyStart
        let bodyResult = parseBody(from: bodyStart, headers: headers)
        switch bodyResult {
        case .needMore:
            return .needMore
        case .invalid(let response):
            return .invalid(response)
        case .body(let body):
            let (path, query) = parsePathAndQuery(target)
            let request = OrbitCLIBridgeRequest(
                method: method,
                path: path,
                query: query,
                headers: headers,
                body: body
            )
            return .request(request)
        }
    }

    private enum BodyParseResult {
        case needMore
        case body(Data)
        case invalid(OrbitCLIBridgeResponse)
    }

    private func parseBody(from bodyStart: Int, headers: [String: String]) -> BodyParseResult {
        let contentLength = headers["content-length"].flatMap { Int($0) } ?? 0
        if contentLength < 0 || contentLength > maxBodyBytes {
            return .invalid(.payloadTooLarge())
        }

        let expectedLength = bodyStart + contentLength
        guard buffer.count >= expectedLength else {
            return .needMore
        }
        let body = buffer.subdata(in: bodyStart..<expectedLength)
        buffer.removeSubrange(0..<expectedLength)
        return .body(body)
    }

    private func headerDelimiter(in data: Data) -> (headerEnd: Int, bodyStart: Int)? {
        let pattern = [UInt8]("\r\n\r\n".utf8)
        guard let range = data.range(of: Data(pattern)) else { return nil }
        let headerEnd = range.lowerBound
        let bodyStart = range.upperBound
        return (headerEnd, bodyStart)
    }

    private func parsePathAndQuery(_ target: String) -> (String, [String: String]) {
        guard let url = URL(string: target, relativeTo: nil) else {
            return (target, [:])
        }
        let path = url.path.isEmpty ? "/" : url.path
        var query: [String: String] = [:]
        if let components = URLComponents(string: target),
           let items = components.queryItems {
            for item in items {
                if let value = item.value {
                    query[item.name] = value
                }
            }
        }
        return (path, query)
    }

    private func sendResponse(_ response: OrbitCLIBridgeResponse) {
        guard !hasResponded else { return }
        hasResponded = true

        let headerLines = [
            "HTTP/1.1 \(response.statusCode) \(response.reason)",
            "Content-Length: \(response.body.count)"
        ] + response.headers.map { "\($0): \($1)" } + ["", ""]

        var data = Data(headerLines.joined(separator: "\r\n").utf8)
        data.append(response.body)

        connection.send(content: data, completion: .contentProcessed { [weak self] _ in
            self?.finish()
        })
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        connection.cancel()
        onFinish?()
    }
}

private struct OrbitClipboardSummary: Codable {
    let uniqueId: String
    let itemType: String
    let pasteboardType: String
    let title: String
    let subtitle: String?
    let previewText: String?
    let previewImageData: Data?
    let timestamp: Int64
    let appName: String
    let appPath: String
    let filePaths: [String]?
    let urlString: String?
    let isTemporary: Bool
}

private struct OrbitClipboardPayload: Codable {
    let uniqueId: String
    let itemType: String
    let pasteboardType: String
    let text: String?
    let urlString: String?
    let filePaths: [String]?
    let imageData: Data?
}

private struct OrbitDeleteRequest: Codable {
    let uniqueIds: [String]
}

private struct OrbitCopyRequest: Codable {
    let uniqueId: String
}

private extension OrbitCLIBridgeService {
    static func handleRequest(
        _ request: OrbitCLIBridgeRequest,
        respond: @escaping @Sendable (OrbitCLIBridgeResponse) -> Void
    ) {
        guard OrbitBridgeAuth.authorize(headers: request.headers) else {
            respond(.unauthorized("Unauthorized"))
            return
        }

        let method = request.method.uppercased()
        let path = request.path

        switch method {
        case "GET":
            switch path {
            case "/orbit/health":
                respond(.ok("ok"))
            case "/orbit/recent":
                let limit = request.query["limit"].flatMap { Int($0) } ?? 9
                let clamped = max(1, min(limit, 50))
                Task { @MainActor in
                    let items = await DeckDataStore.shared.fetchRecentItems(limit: clamped, types: [])
                    let summaries = items.map { summarize(item: $0) }
                    do {
                        let data = try JSONEncoder().encode(summaries)
                        respond(.okData(data))
                    } catch {
                        respond(.badRequest(error.localizedDescription))
                    }
                }
            case "/orbit/item":
                guard let uniqueId = request.query["uniqueId"] ?? request.query["id"] else {
                    respond(.badRequest("Missing uniqueId"))
                    return
                }
                let trimmed = uniqueId.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    respond(.badRequest("Empty uniqueId"))
                    return
                }
                Task { @MainActor in
                    guard let item = await DeckDataStore.shared.fetchItem(uniqueId: trimmed, loadFullData: true) else {
                        respond(.badRequest("Item not found"))
                        return
                    }
                    let payload = payload(from: item)
                    do {
                        let data = try JSONEncoder().encode(payload)
                        respond(.okData(data))
                    } catch {
                        respond(.badRequest(error.localizedDescription))
                    }
                }
            default:
                respond(.notFound())
            }
        case "POST":
            switch path {
            case "/orbit/delete":
                let ids = decodeDeleteIds(from: request.body)
                guard !ids.isEmpty else {
                    respond(.badRequest("Empty uniqueIds"))
                    return
                }
                Task { @MainActor in
                    for id in ids {
                        _ = await DeckDataStore.shared.deleteItemByUniqueId(id)
                    }
                    respond(.ok("{\"success\":true}", contentType: "application/json; charset=utf-8"))
                }
            case "/orbit/copy":
                guard let uniqueId = decodeCopyId(from: request.body) else {
                    respond(.badRequest("Empty uniqueId"))
                    return
                }
                let trimmed = uniqueId.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    respond(.badRequest("Empty uniqueId"))
                    return
                }
                Task { @MainActor in
                    guard let item = await DeckDataStore.shared.fetchItem(uniqueId: trimmed, loadFullData: true) else {
                        respond(.badRequest("Item not found"))
                        return
                    }
                    ClipboardService.shared.paste(item, asPlainText: false)
                    respond(.ok("{\"success\":true}", contentType: "application/json; charset=utf-8"))
                }
            default:
                respond(.notFound())
            }
        default:
            respond(.methodNotAllowed(allowed: "GET, POST"))
        }
    }

    static func decodeDeleteIds(from body: Data) -> [String] {
        guard !body.isEmpty else { return [] }
        if let request = try? JSONDecoder().decode(OrbitDeleteRequest.self, from: body) {
            return request.uniqueIds
        }
        if let ids = try? JSONDecoder().decode([String].self, from: body) {
            return ids
        }
        return []
    }

    static func decodeCopyId(from body: Data) -> String? {
        guard !body.isEmpty else { return nil }
        if let request = try? JSONDecoder().decode(OrbitCopyRequest.self, from: body) {
            return request.uniqueId
        }
        if let id = String(data: body, encoding: .utf8) {
            return id
        }
        return nil
    }

    static func summarize(item: ClipboardItem) -> OrbitClipboardSummary {
        let itemType = item.itemType
        let preview = item.previewText(maxCharacters: 120)
        let title = summaryTitle(for: item, preview: preview.text)
        let subtitle = item.displayDescription()
        let previewImageData = summaryImageData(for: item)
        let filePaths = item.pasteboardType == .fileURL ? item.filePaths : nil
        let urlString = item.url?.absoluteString

        return OrbitClipboardSummary(
            uniqueId: item.uniqueId,
            itemType: itemType.rawValue,
            pasteboardType: item.pasteboardType.rawValue,
            title: title,
            subtitle: subtitle,
            previewText: itemType == .text || itemType == .richText || itemType == .code ? preview.text : nil,
            previewImageData: previewImageData,
            timestamp: item.timestamp,
            appName: item.appName,
            appPath: item.appPath,
            filePaths: filePaths,
            urlString: urlString,
            isTemporary: item.isTemporary
        )
    }

    static func summaryTitle(for item: ClipboardItem, preview: String) -> String {
        switch item.itemType {
        case .text, .richText, .code:
            return preview.isEmpty ? item.displayDescription() : preview
        case .url:
            return item.url?.absoluteString ?? item.displayDescription()
        case .image, .file, .color:
            return item.displayDescription()
        }
    }

    static func summaryImageData(for item: ClipboardItem) -> Data? {
        guard item.itemType == .image else { return nil }

        if let previewData = item.previewData, !previewData.isEmpty {
            return previewData
        }

        guard item.pasteboardType.isImage(), item.hasFullData else { return nil }
        let data = item.data
        let maxInlineBytes = 5 * 1024 * 1024
        guard data.count <= maxInlineBytes else { return nil }
        return ClipboardItem.generatePreviewThumbnailData(from: data)
    }

    static func payload(from item: ClipboardItem) -> OrbitClipboardPayload {
        var text: String?
        var urlString: String?
        var filePaths: [String]?
        var imageData: Data?

        switch item.itemType {
        case .text, .richText, .code, .color:
            text = item.searchText
        case .url:
            urlString = item.url?.absoluteString ?? item.searchText
        case .file:
            filePaths = item.filePaths
        case .image:
            if item.pasteboardType == .fileURL {
                filePaths = item.filePaths
            } else {
                imageData = item.resolvedData()
            }
        }

        return OrbitClipboardPayload(
            uniqueId: item.uniqueId,
            itemType: item.itemType.rawValue,
            pasteboardType: item.pasteboardType.rawValue,
            text: text,
            urlString: urlString,
            filePaths: filePaths,
            imageData: imageData
        )
    }
}
