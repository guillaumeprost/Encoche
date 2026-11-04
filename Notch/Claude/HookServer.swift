import Foundation
import Network

/// Réponse différée à une requête de hook : la connexion reste ouverte jusqu'à ce que
/// l'utilisateur décide dans l'encoche (ou que Claude Code abandonne).
@MainActor
final class HookReply {
    private let connection: NWConnection
    private(set) var isDone = false
    /// Appelé si Claude Code ferme la connexion avant la réponse (timeout, réponse dans le terminal…).
    var onClosed: (() -> Void)?

    init(connection: NWConnection) {
        self.connection = connection
    }

    /// Envoie le JSON de décision (ou rien : Claude Code poursuit alors son flux normal).
    func send(_ body: Data?) {
        guard !isDone else { return }
        isDone = true
        let payload = body ?? Data()
        var response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
        response += "Content-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(response.utf8) + payload, completion: .contentProcessed { [connection] _ in
            connection.cancel()
        })
    }

    /// Surveille la fermeture côté client.
    func watchForClose() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] _, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, !self.isDone else { return }
                if isComplete || error != nil {
                    self.isDone = true
                    self.connection.cancel()
                    self.onClosed?()
                } else {
                    self.watchForClose()
                }
            }
        }
    }
}

/// Mini-serveur HTTP sur 127.0.0.1 qui reçoit les événements des hooks Claude Code
/// (`curl -X POST --data-binary @-` du JSON que Claude Code passe sur stdin).
/// N'écoute que sur la boucle locale : rien n'est joignable depuis le réseau.
///
/// - `POST /claude-code` : événement simple, réponse immédiate.
/// - `POST /claude-code/permission` : demande de permission, réponse quand tu as décidé.
@MainActor
final class HookServer {
    nonisolated static let port: UInt16 = 47823
    nonisolated static let path = "/claude-code"
    nonisolated static let permissionPath = "/claude-code/permission"

    private var listener: NWListener?
    private let onEvent: ([String: Any]) -> Void
    private let onPermission: ([String: Any], HookReply) -> Void

    init(
        onEvent: @escaping ([String: Any]) -> Void,
        onPermission: @escaping ([String: Any], HookReply) -> Void
    ) {
        self.onEvent = onEvent
        self.onPermission = onPermission
    }

    func start() {
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.accept(connection) }
            }
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state { NSLog("[Encoche] Hook server failed: \(error)") }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            NSLog("[Encoche] Hook server could not start: \(error)")
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                var buffer = buffer
                if let data { buffer.append(data) }

                if let (path, headers, body) = Self.parse(buffer) {
                    self.dispatch(path: path, headers: headers, body: body, connection: connection)
                } else if isComplete || error != nil || buffer.count > 1_000_000 {
                    connection.cancel()
                } else {
                    self.receive(on: connection, buffer: buffer)
                }
            }
        }
    }

    private func dispatch(path: String, headers: [String: String], body: Data, connection: NWConnection) {
        var json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let reply = HookReply(connection: connection)
        if let pid = headers[Self.pidHeader.lowercased()].flatMap(Int32.init) { json?["_claude_pid"] = pid }

        guard let json else {
            reply.send(nil)
            return
        }
        if path == Self.permissionPath {
            reply.watchForClose()
            onPermission(json, reply)
        } else {
            onEvent(json)
            reply.send(nil)
        }
    }

    /// Chemin et corps si la requête HTTP est complète (en-têtes + Content-Length octets).
    /// En-tête ajouté par nos hooks : PID du processus Claude Code (pour retrouver son app).
    nonisolated static let pidHeader = "X-Claude-PID"

    private static func parse(_ buffer: Data) -> (String, [String: String], Data)? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headers = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
        let requestLine = headers.split(separator: "\r\n").first.map(String.init) ?? ""
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "POST" else { return ("", [:], Data()) }

        var fields: [String: String] = [:]
        for line in headers.split(separator: "\r\n").dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            fields[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        let length = headers
            .split(separator: "\r\n")
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
        let body = buffer[headerEnd.upperBound...]
        return body.count >= length ? (String(parts[1]), fields, Data(body.prefix(length))) : nil
    }
}
