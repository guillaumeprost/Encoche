import Foundation
import Network

/// Mini-serveur HTTP sur 127.0.0.1 qui reçoit les événements des hooks Claude Code
/// (`curl -X POST --data-binary @-` du JSON que Claude Code passe sur stdin).
/// N'écoute que sur la boucle locale : rien n'est joignable depuis le réseau.
@MainActor
final class HookServer {
    nonisolated static let port: UInt16 = 47823
    nonisolated static let path = "/claude-code"

    private var listener: NWListener?
    private let onEvent: ([String: Any]) -> Void

    init(onEvent: @escaping ([String: Any]) -> Void) {
        self.onEvent = onEvent
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
                if case .failed(let error) = state { NSLog("[Notch] Hook server failed: \(error)") }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            NSLog("[Notch] Hook server could not start: \(error)")
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

                if let body = Self.completeBody(in: buffer) {
                    if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                        self.onEvent(json)
                    }
                    self.respond(on: connection)
                } else if isComplete || error != nil || buffer.count > 1_000_000 {
                    connection.cancel()
                } else {
                    self.receive(on: connection, buffer: buffer)
                }
            }
        }
    }

    /// Renvoie le corps si la requête HTTP est complète (en-têtes + Content-Length octets).
    private static func completeBody(in buffer: Data) -> Data? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headers = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
        guard headers.hasPrefix("POST \(path)") else { return Data() }

        let length = headers
            .split(separator: "\r\n")
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
        let body = buffer[headerEnd.upperBound...]
        return body.count >= length ? Data(body.prefix(length)) : nil
    }

    private func respond(on connection: NWConnection) {
        let response = "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
