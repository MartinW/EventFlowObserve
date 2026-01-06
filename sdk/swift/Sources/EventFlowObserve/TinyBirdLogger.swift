import Foundation

/// Payload structure sent to TinyBird (flattened for easier querying)
struct TinyBirdPayload: Codable, Sendable {
    let id: String
    let timestamp: String
    let url: String
    let method: String
    let host: String
    let path: String
    let headers: String  // JSON-encoded string
    let body: String?
    let bundle_id: String
    let app_version: String
    let app_build: String
    let device_model: String
    let os_version: String

    init(from request: CapturedRequest) {
        self.id = request.id.uuidString
        self.timestamp = ISO8601DateFormatter().string(from: request.timestamp)
        self.url = request.url.absoluteString
        self.method = request.method
        self.host = request.host
        self.path = request.path

        // Encode headers as JSON string
        if let headersData = try? JSONSerialization.data(withJSONObject: request.headers, options: []),
           let headersString = String(data: headersData, encoding: .utf8) {
            self.headers = headersString
        } else {
            self.headers = "{}"
        }

        self.body = request.bodyString
        self.bundle_id = Bundle.main.bundleIdentifier ?? "unknown"
        self.app_version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        self.app_build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        self.device_model = Self.deviceModel
        self.os_version = Self.osVersion
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

/// Handles batching and sending captured requests to TinyBird
final class TinyBirdLogger: @unchecked Sendable {
    private let config: TinyBirdLoggerConfig
    private var queue: [TinyBirdPayload] = []
    private let lock = NSLock()
    private var flushTimer: Timer?
    private let session: URLSession
    private let fileManager = FileManager.default
    private var persistenceURL: URL?

    init(config: TinyBirdLoggerConfig) {
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
        // Don't log requests to TinyBird itself
        if let host = request.url.host, host.contains("tinybird.co") {
            return
        }

        let payload = TinyBirdPayload(from: request)

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

    private func sendBatch(_ batch: [TinyBirdPayload], retryCount: Int) {
        var request = URLRequest(url: config.endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.authToken)", forHTTPHeaderField: "Authorization")

        // Encode as NDJSON (newline-delimited JSON)
        do {
            let encoder = JSONEncoder()
            let ndjsonLines = try batch.map { payload -> String in
                let data = try encoder.encode(payload)
                guard let line = String(data: data, encoding: .utf8) else {
                    throw NSError(domain: "TinyBirdLogger", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode payload as UTF-8"])
                }
                return line
            }
            let ndjsonBody = ndjsonLines.joined(separator: "\n")
            request.httpBody = ndjsonBody.data(using: .utf8)
        } catch {
            log("Failed to encode batch: \(error)")
            return
        }

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                self.log("Failed to send batch to TinyBird: \(error)")
                self.handleFailedBatch(batch, retryCount: retryCount)
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                if (200...299).contains(httpResponse.statusCode) {
                    self.log("Successfully sent \(batch.count) events to TinyBird")
                    self.clearPersistedQueue()
                } else {
                    // Log response body for debugging
                    if let data = data, let body = String(data: data, encoding: .utf8) {
                        self.log("TinyBird returned status \(httpResponse.statusCode): \(body)")
                    } else {
                        self.log("TinyBird returned status \(httpResponse.statusCode)")
                    }
                    self.handleFailedBatch(batch, retryCount: retryCount)
                }
            }
        }.resume()
    }

    private func handleFailedBatch(_ batch: [TinyBirdPayload], retryCount: Int) {
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
            log("Failed to send batch to TinyBird after \(config.maxRetries) retries")
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
        persistenceURL = cacheDir.appendingPathComponent("EventFlowObserveTinyBirdQueue.json")
    }

    private func persistQueue() {
        guard let url = persistenceURL else { return }
        do {
            let data = try JSONEncoder().encode(queue)
            try data.write(to: url)
        } catch {
            log("Failed to persist TinyBird queue: \(error)")
        }
    }

    private func loadPersistedQueue() {
        guard let url = persistenceURL,
              fileManager.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let persisted = try JSONDecoder().decode([TinyBirdPayload].self, from: data)
            lock.lock()
            queue.append(contentsOf: persisted)
            lock.unlock()
            log("Loaded \(persisted.count) persisted TinyBird events")
        } catch {
            log("Failed to load persisted TinyBird queue: \(error)")
        }
    }

    private func clearPersistedQueue() {
        guard let url = persistenceURL else { return }
        try? fileManager.removeItem(at: url)
    }

    private func log(_ message: String) {
        if EventFlowObserve.shared.config.debugMode {
            print("[EventFlowObserve.TinyBird] \(message)")
        }
    }
}
