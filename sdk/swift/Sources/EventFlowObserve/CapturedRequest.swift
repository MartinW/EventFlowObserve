import Foundation

/// Represents a captured HTTP/HTTPS network request
public struct CapturedRequest: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let url: URL
    public let method: String
    public let headers: [String: String]
    public let body: Data?
    public let bodyString: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        url: URL,
        method: String,
        headers: [String: String],
        body: Data?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.bodyString = body.flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Returns the host component of the URL
    public var host: String {
        url.host ?? "unknown"
    }

    /// Returns the path component of the URL
    public var path: String {
        url.path
    }

    /// Attempts to parse the body as JSON
    public var bodyJSON: Any? {
        guard let body = body else { return nil }
        return try? JSONSerialization.jsonObject(with: body, options: [])
    }

    /// Pretty-printed JSON body if available
    public var prettyBodyJSON: String? {
        guard let json = bodyJSON,
              let data = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
}

extension CapturedRequest: CustomStringConvertible {
    public var description: String {
        var desc = "[\(method)] \(url.absoluteString)"
        if let bodyString = bodyString {
            desc += "\nBody: \(bodyString.prefix(200))"
            if bodyString.count > 200 {
                desc += "..."
            }
        }
        return desc
    }
}
