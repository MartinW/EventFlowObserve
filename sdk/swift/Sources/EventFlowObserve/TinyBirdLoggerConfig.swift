import Foundation

/// TinyBird region endpoints
public enum TinyBirdRegion: String, Sendable {
    case us = "api.tinybird.co"
    case euCentral = "api.eu-central-1.tinybird.co"
    case euWest2 = "api.europe-west2.gcp.tinybird.co"
    case euWest3 = "api.europe-west3.gcp.tinybird.co"
}

/// Configuration for TinyBird logging
public struct TinyBirdLoggerConfig: Sendable {
    /// The datasource name in TinyBird (e.g., "tracking_events")
    public let datasource: String

    /// TinyBird auth token (use a write-only token for security)
    public let authToken: String

    /// TinyBird region (US or EU)
    public let region: TinyBirdRegion

    /// How many requests to batch before sending
    public let batchSize: Int

    /// Maximum time (in seconds) to wait before sending a partial batch
    public let flushInterval: TimeInterval

    /// Whether to persist unsent requests to disk for retry
    public let persistQueue: Bool

    /// Maximum number of retry attempts for failed sends
    public let maxRetries: Int

    public init(
        datasource: String,
        authToken: String,
        region: TinyBirdRegion = .euWest2,
        batchSize: Int = 10,
        flushInterval: TimeInterval = 30,
        persistQueue: Bool = true,
        maxRetries: Int = 3
    ) {
        self.datasource = datasource
        self.authToken = authToken
        self.region = region
        self.batchSize = batchSize
        self.flushInterval = flushInterval
        self.persistQueue = persistQueue
        self.maxRetries = maxRetries
    }

    /// The TinyBird Events API endpoint URL
    public var endpointURL: URL {
        URL(string: "https://\(region.rawValue)/v0/events?name=\(datasource)")!
    }
}
