import Foundation

/// Custom URLProtocol subclass that intercepts and observes HTTP/HTTPS requests
final class EventFlowObserveProtocol: URLProtocol {
    /// Key used to mark requests that have already been handled to prevent infinite loops
    private static let handledKey = "EventFlowObserveProtocolHandled"

    /// The actual data task that performs the real network request
    private var dataTask: URLSessionDataTask?

    /// Accumulated response data
    private var responseData: Data?

    /// Lazy session to avoid retain cycles
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    // MARK: - URLProtocol Override Methods

    override class func canInit(with request: URLRequest) -> Bool {
        // Check if we've already handled this request
        guard URLProtocol.property(forKey: handledKey, in: request) == nil else {
            return false
        }

        // Check if the scheme is one we want to intercept
        guard let scheme = request.url?.scheme?.lowercased(),
              EventFlowObserve.shared.config.schemes.contains(scheme) else {
            return false
        }

        // Apply domain filtering
        if let host = request.url?.host {
            let config = EventFlowObserve.shared.config

            // Check excluded domains first
            if config.excludedDomains.contains(where: { host.contains($0) }) {
                return false
            }

            // If allowed domains is specified, only allow those
            if !config.allowedDomains.isEmpty {
                guard config.allowedDomains.contains(where: { host.contains($0) }) else {
                    return false
                }
            }
        }

        // Apply sampling rate
        if EventFlowObserve.shared.config.samplingRate < 1.0 {
            guard Double.random(in: 0...1) <= EventFlowObserve.shared.config.samplingRate else {
                return false
            }
        }

        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override class func requestIsCacheEquivalent(_ a: URLRequest, to b: URLRequest) -> Bool {
        return super.requestIsCacheEquivalent(a, to: b)
    }

    override func startLoading() {
        // Capture the request before forwarding
        captureRequest()

        // Mark request as handled to prevent infinite loop
        guard let mutableRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "EventFlowObserve", code: -1))
            return
        }

        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutableRequest)

        // Forward the request using a real URLSession
        dataTask = session.dataTask(with: mutableRequest as URLRequest)
        dataTask?.resume()
    }

    override func stopLoading() {
        dataTask?.cancel()
        dataTask = nil
    }

    // MARK: - Request Capture

    private func captureRequest() {
        guard let url = request.url else { return }

        let config = EventFlowObserve.shared.config
        var body: Data? = nil

        if config.captureRequestBody {
            // Try to get body from httpBody first
            if let httpBody = request.httpBody {
                body = httpBody.prefix(config.maxBodySize)
            }
            // Try httpBodyStream if httpBody is nil
            else if let bodyStream = request.httpBodyStream {
                body = readStream(bodyStream, maxSize: config.maxBodySize)
            }
        }

        // Extract headers
        var headers: [String: String] = [:]
        if let allHeaders = request.allHTTPHeaderFields {
            headers = allHeaders
        }

        let capturedRequest = CapturedRequest(
            url: url,
            method: request.httpMethod ?? "UNKNOWN",
            headers: headers,
            body: body
        )

        // Notify the SDK
        EventFlowObserve.shared.didCapture(request: capturedRequest)
    }

    private func readStream(_ stream: InputStream, maxSize: Int) -> Data? {
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable && data.count < maxSize {
            let bytesRead = stream.read(buffer, maxLength: bufferSize)
            if bytesRead > 0 {
                data.append(buffer, count: bytesRead)
            } else {
                break
            }
        }

        return data.isEmpty ? nil : data
    }
}

// MARK: - URLSessionDataDelegate

extension EventFlowObserveProtocol: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        responseData = Data()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        client?.urlProtocol(self, didLoad: data)
        responseData?.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}

// MARK: - Data Extension

private extension Data {
    func prefix(_ maxLength: Int) -> Data {
        if count <= maxLength {
            return self
        }
        return self.prefix(maxLength)
    }
}
