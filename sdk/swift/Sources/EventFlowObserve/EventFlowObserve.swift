import Foundation

/// Callback type for receiving captured requests
public typealias RequestCaptureHandler = @Sendable (CapturedRequest) -> Void

/// Main interface for the EventFlowObserve SDK
/// Intercepts and observes HTTP/HTTPS network traffic within the app
public final class EventFlowObserve: @unchecked Sendable {
    /// Shared singleton instance
    public static let shared = EventFlowObserve()

    /// Current configuration
    public private(set) var config: EventFlowObserveConfig = .default

    /// Whether the observer is currently active
    public private(set) var isActive: Bool = false

    /// Queue for thread-safe operations
    private let queue = DispatchQueue(label: "com.eventflowobserve.queue", attributes: .concurrent)

    /// Stored captured requests (limited buffer)
    private var _capturedRequests: [CapturedRequest] = []
    private let maxStoredRequests = 1000

    /// Registered handlers for captured requests
    private var handlers: [UUID: RequestCaptureHandler] = [:]

    /// Lock for handler management
    private let handlerLock = NSLock()

    /// Remote logger for sending captured requests to an endpoint
    private var remoteLogger: RemoteLogger?

    private init() {}

    // MARK: - Public API

    /// Initialize and start the observer with the given configuration
    /// - Parameter config: Configuration options for the observer
    public func start(config: EventFlowObserveConfig = .default) {
        guard !isActive else {
            log("EventFlowObserve is already active")
            return
        }

        self.config = config
        URLProtocol.registerClass(EventFlowObserveProtocol.self)

        // Enable swizzling to intercept requests from third-party SDKs
        if config.swizzleSessionConfiguration {
            URLSessionConfiguration.swizzleForEventFlowObserve()
            log("URLSessionConfiguration swizzling enabled")
        }

        // Initialize remote logger if configured
        if let remoteConfig = config.remoteLogging {
            remoteLogger = RemoteLogger(config: remoteConfig)
            log("Remote logging enabled to: \(remoteConfig.endpointURL)")
        }

        isActive = true

        log("EventFlowObserve started with config: debugMode=\(config.debugMode), schemes=\(config.schemes), swizzle=\(config.swizzleSessionConfiguration)")
    }

    /// Stop the observer
    public func stop() {
        guard isActive else {
            log("EventFlowObserve is not active")
            return
        }

        // Flush any pending remote logs
        remoteLogger?.flush()
        remoteLogger = nil

        URLProtocol.unregisterClass(EventFlowObserveProtocol.self)

        // Restore original URLSessionConfiguration behavior
        if config.swizzleSessionConfiguration {
            URLSessionConfiguration.unswizzleForEventFlowObserve()
        }

        isActive = false

        log("EventFlowObserve stopped")
    }

    /// Manually flush any pending requests to the remote endpoint
    public func flushRemoteLogs() {
        remoteLogger?.flush()
    }

    /// Register a handler to receive captured requests
    /// - Parameter handler: Closure called for each captured request
    /// - Returns: A token that can be used to unregister the handler
    @discardableResult
    public func onRequestCaptured(_ handler: @escaping RequestCaptureHandler) -> UUID {
        let token = UUID()
        handlerLock.lock()
        handlers[token] = handler
        handlerLock.unlock()
        return token
    }

    /// Unregister a previously registered handler
    /// - Parameter token: The token returned from `onRequestCaptured`
    public func removeHandler(token: UUID) {
        handlerLock.lock()
        handlers.removeValue(forKey: token)
        handlerLock.unlock()
    }

    /// Get all captured requests
    public var capturedRequests: [CapturedRequest] {
        queue.sync { _capturedRequests }
    }

    /// Clear all captured requests
    public func clearCapturedRequests() {
        queue.async(flags: .barrier) { [weak self] in
            self?._capturedRequests.removeAll()
        }
    }

    /// Get captured requests filtered by domain
    public func requests(forDomain domain: String) -> [CapturedRequest] {
        capturedRequests.filter { $0.host.contains(domain) }
    }

    /// Get captured requests filtered by HTTP method
    public func requests(withMethod method: String) -> [CapturedRequest] {
        capturedRequests.filter { $0.method.uppercased() == method.uppercased() }
    }

    // MARK: - Internal

    /// Called by EventFlowObserveProtocol when a request is captured
    func didCapture(request: CapturedRequest) {
        // Store the request
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self._capturedRequests.append(request)

            // Trim if exceeding max
            if self._capturedRequests.count > self.maxStoredRequests {
                self._capturedRequests.removeFirst(self._capturedRequests.count - self.maxStoredRequests)
            }
        }

        // Log if debug mode
        log("Captured: \(request)")

        // Send to remote endpoint if configured
        remoteLogger?.log(request)

        // Notify handlers
        handlerLock.lock()
        let currentHandlers = handlers
        handlerLock.unlock()

        for (_, handler) in currentHandlers {
            handler(request)
        }
    }

    private func log(_ message: String) {
        guard config.debugMode else { return }
        print("[EventFlowObserve] \(message)")
    }
}

// MARK: - Convenience Extensions

public extension EventFlowObserve {
    /// Create a URLSession configured to work with the observer
    /// Note: The default URLSession already works, but this provides explicit configuration
    static func createSession(configuration: URLSessionConfiguration = .default) -> URLSession {
        // Insert our protocol at the beginning
        var protocolClasses = configuration.protocolClasses ?? []
        if !protocolClasses.contains(where: { $0 == EventFlowObserveProtocol.self }) {
            protocolClasses.insert(EventFlowObserveProtocol.self, at: 0)
        }
        configuration.protocolClasses = protocolClasses

        return URLSession(configuration: configuration)
    }
}
