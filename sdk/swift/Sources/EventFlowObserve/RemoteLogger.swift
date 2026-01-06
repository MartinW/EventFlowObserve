import Foundation

/// Configuration for remote logging
public struct RemoteLoggerConfig: Sendable {
    /// The endpoint URL to send captured requests to
    public let endpointURL: URL

    /// API key for authentication (sent as Bearer token)
    public let apiKey: String?

    /// Custom headers to include in requests to the endpoint
    public let customHeaders: [String: String]

    /// How many requests to batch before sending
    public let batchSize: Int

    /// Maximum time (in seconds) to wait before sending a partial batch
    public let flushInterval: TimeInterval

    /// Whether to persist unsent requests to disk for retry
    public let persistQueue: Bool

    /// Maximum number of retry attempts for failed sends
    public let maxRetries: Int

    public init(
        endpointURL: URL,
        apiKey: String? = nil,
        customHeaders: [String: String] = [:],
        batchSize: Int = 10,
        flushInterval: TimeInterval = 30,
        persistQueue: Bool = true,
        maxRetries: Int = 3
    ) {
        self.endpointURL = endpointURL
        self.apiKey = apiKey
        self.customHeaders = customHeaders
        self.batchSize = batchSize
        self.flushInterval = flushInterval
        self.persistQueue = persistQueue
        self.maxRetries = maxRetries
    }
}

/// Payload structure sent to the remote endpoint
public struct CapturedRequestPayload: Codable, Sendable {
    public let id: String
    public let timestamp: String
    public let url: String
    public let method: String
    public let host: String
    public let path: String
    public let headers: [String: String]
    public let body: String?
    public let appInfo: AppInfo

    public struct AppInfo: Codable, Sendable {
        public let bundleId: String
        public let version: String
        public let build: String
        public let deviceModel: String
        public let osVersion: String
    }

    init(from request: CapturedRequest) {
        self.id = request.id.uuidString
        self.timestamp = ISO8601DateFormatter().string(from: request.timestamp)
        self.url = request.url.absoluteString
        self.method = request.method
        self.host = request.host
        self.path = request.path
        self.headers = request.headers
        self.body = request.bodyString
        self.appInfo = AppInfo(
            bundleId: Bundle.main.bundleIdentifier ?? "unknown",
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            deviceModel: Self.deviceModel,
            osVersion: Self.osVersion
        )
    }

    private static var deviceModel: String {
        #if os(iOS)
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        return machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        #else
        return "macOS"
        #endif
    }

    private static var osVersion: String {
        #if os(iOS)
        return "iOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        #else
        return "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        #endif
    }
}

/// Handles batching and sending captured requests to a remote endpoint
final class RemoteLogger: @unchecked Sendable {
    private let config: RemoteLoggerConfig
    private var queue: [CapturedRequestPayload] = []
    private let lock = NSLock()
    private var flushTimer: Timer?
    private let session: URLSession
    private let fileManager = FileManager.default
    private var persistenceURL: URL?

    init(config: RemoteLoggerConfig) {
        self.config = config

        // Create a session that bypasses our protocol to avoid infinite loops
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [] // No custom protocols
        self.session = URLSession(configuration: sessionConfig)

        if config.persistQueue {
            setupPersistence()
            loadPersistedQueue()
        }

        startFlushTimer()
    }

    deinit {
        flushTimer?.invalidate()
    }

    /// Add a captured request to the queue
    func log(_ request: CapturedRequest) {
        // Don't log requests to our own endpoint
        if request.url.host == config.endpointURL.host {
            return
        }

        let payload = CapturedRequestPayload(from: request)

        lock.lock()
        queue.append(payload)
        let shouldFlush = queue.count >= config.batchSize
        lock.unlock()

        if shouldFlush {
            flush()
        }
    }

    /// Immediately send all queued requests
    func flush() {
        lock.lock()
        guard !queue.isEmpty else {
            lock.unlock()
            return
        }
        let batch = queue
        queue.removeAll()
        lock.unlock()

        sendBatch(batch, retryCount: 0)
    }

    private func sendBatch(_ batch: [CapturedRequestPayload], retryCount: Int) {
        var request = URLRequest(url: config.endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let apiKey = config.apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        for (key, value) in config.customHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            request.httpBody = try encoder.encode(batch)
        } catch {
            log("Failed to encode batch: \(error)")
            return
        }

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                self.log("Failed to send batch: \(error)")
                self.handleFailedBatch(batch, retryCount: retryCount)
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                if (200...299).contains(httpResponse.statusCode) {
                    self.log("Successfully sent \(batch.count) requests to remote endpoint")
                    self.clearPersistedQueue()
                } else {
                    self.log("Remote endpoint returned status \(httpResponse.statusCode)")
                    self.handleFailedBatch(batch, retryCount: retryCount)
                }
            }
        }.resume()
    }

    private func handleFailedBatch(_ batch: [CapturedRequestPayload], retryCount: Int) {
        if retryCount < config.maxRetries {
            // Retry with exponential backoff
            let delay = pow(2.0, Double(retryCount))
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.sendBatch(batch, retryCount: retryCount + 1)
            }
        } else {
            // Re-queue for later if persistence is enabled
            if config.persistQueue {
                lock.lock()
                queue.insert(contentsOf: batch, at: 0)
                persistQueue()
                lock.unlock()
            }
            log("Failed to send batch after \(config.maxRetries) retries")
        }
    }

    private func startFlushTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.flushTimer = Timer.scheduledTimer(
                withTimeInterval: self.config.flushInterval,
                repeats: true
            ) { [weak self] _ in
                self?.flush()
            }
        }
    }

    // MARK: - Persistence

    private func setupPersistence() {
        guard let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }
        persistenceURL = cacheDir.appendingPathComponent("EventFlowObserveQueue.json")
    }

    private func persistQueue() {
        guard let url = persistenceURL else { return }
        do {
            let data = try JSONEncoder().encode(queue)
            try data.write(to: url)
        } catch {
            log("Failed to persist queue: \(error)")
        }
    }

    private func loadPersistedQueue() {
        guard let url = persistenceURL,
              fileManager.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let persisted = try JSONDecoder().decode([CapturedRequestPayload].self, from: data)
            lock.lock()
            queue.append(contentsOf: persisted)
            lock.unlock()
            log("Loaded \(persisted.count) persisted requests")
        } catch {
            log("Failed to load persisted queue: \(error)")
        }
    }

    private func clearPersistedQueue() {
        guard let url = persistenceURL else { return }
        try? fileManager.removeItem(at: url)
    }

    private func log(_ message: String) {
        if EventFlowObserve.shared.config.debugMode {
            print("[EventFlowObserve.RemoteLogger] \(message)")
        }
    }
}
