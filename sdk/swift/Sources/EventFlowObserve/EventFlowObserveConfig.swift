import Foundation

/// Configuration options for the EventFlowObserve SDK
public struct EventFlowObserveConfig: Sendable {
    /// Whether to enable debug logging to console
    public var debugMode: Bool

    /// Optional list of domains to monitor. If empty, all domains are monitored.
    public var allowedDomains: [String]

    /// Optional list of domains to exclude from monitoring
    public var excludedDomains: [String]

    /// Whether to capture request bodies
    public var captureRequestBody: Bool

    /// Maximum body size to capture (in bytes). Bodies larger than this will be truncated.
    public var maxBodySize: Int

    /// Sampling rate (0.0 to 1.0). 1.0 means capture all requests.
    public var samplingRate: Double

    /// URL schemes to intercept
    public var schemes: Set<String>

    /// Whether to swizzle URLSessionConfiguration to intercept requests from third-party SDKs.
    /// When enabled, all URLSession instances (including those created by SDKs like Mixpanel,
    /// Firebase, etc.) will have their requests intercepted.
    public var swizzleSessionConfiguration: Bool

    /// Optional configuration for sending captured requests to a remote endpoint.
    /// When set, all captured requests will be batched and sent to the specified URL.
    public var remoteLogging: RemoteLoggerConfig?

    /// Optional configuration for sending captured requests to TinyBird.
    /// When set, all captured requests will be batched and sent to your TinyBird datasource.
    public var tinyBirdLogging: TinyBirdLoggerConfig?

    public init(
        debugMode: Bool = false,
        allowedDomains: [String] = [],
        excludedDomains: [String] = [],
        captureRequestBody: Bool = true,
        maxBodySize: Int = 1024 * 1024, // 1MB default
        samplingRate: Double = 1.0,
        schemes: Set<String> = ["http", "https"],
        swizzleSessionConfiguration: Bool = true,
        remoteLogging: RemoteLoggerConfig? = nil,
        tinyBirdLogging: TinyBirdLoggerConfig? = nil
    ) {
        self.debugMode = debugMode
        self.allowedDomains = allowedDomains
        self.excludedDomains = excludedDomains
        self.captureRequestBody = captureRequestBody
        self.maxBodySize = maxBodySize
        self.samplingRate = min(1.0, max(0.0, samplingRate))
        self.schemes = schemes
        self.swizzleSessionConfiguration = swizzleSessionConfiguration
        self.remoteLogging = remoteLogging
        self.tinyBirdLogging = tinyBirdLogging
    }

    /// Default configuration that captures all HTTP/HTTPS traffic including from third-party SDKs
    public static let `default` = EventFlowObserveConfig()

    /// Debug configuration with console logging enabled
    public static let debug = EventFlowObserveConfig(debugMode: true)
}
