# EventFlowObserve - Swift SDK

A Swift package for passively intercepting and observing HTTP/HTTPS network traffic within iOS apps.

## Features

- Passive interception via `URLProtocol` subclass
- URLSessionConfiguration swizzling to capture third-party SDK traffic (Mixpanel, Firebase, etc.)
- Configurable domain filtering (allow/exclude lists)
- Sampling rate support
- Request body capture with size limits
- Remote logging with batching, retries, and persistence
- Thread-safe request storage
- Callback handlers for real-time notifications

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/AcmeCorp/EventFlowObserve.git", from: "1.0.0"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "EventFlowObserve", package: "EventFlowObserve", path: "sdk/swift")
        ]
    )
]
```

Or in Xcode: File → Add Package Dependencies → Enter the repository URL.

## Usage

### Basic Setup

```swift
import EventFlowObserve

// Start with debug mode
EventFlowObserve.shared.start(config: .debug)

// Or with default config
EventFlowObserve.shared.start()
```

### Custom Configuration

```swift
let config = EventFlowObserveConfig(
    debugMode: true,
    allowedDomains: ["api.mixpanel.com", "graph.facebook.com"],
    excludedDomains: ["localhost"],
    captureRequestBody: true,
    maxBodySize: 1024 * 1024,  // 1MB
    samplingRate: 1.0,
    swizzleSessionConfiguration: true
)

EventFlowObserve.shared.start(config: config)
```

### Handling Captured Requests

```swift
EventFlowObserve.shared.onRequestCaptured { request in
    print("Captured: \(request.method) \(request.url)")
    print("Headers: \(request.headers)")
    if let body = request.bodyString {
        print("Body: \(body)")
    }
}
```

### Remote Logging

Send captured requests to your own endpoint:

```swift
let remoteConfig = RemoteLoggerConfig(
    endpointURL: URL(string: "https://your-api.com/logs")!,
    apiKey: "your-secret-api-key",
    batchSize: 10,
    flushInterval: 30,
    persistQueue: true
)

let config = EventFlowObserveConfig(
    debugMode: true,
    remoteLogging: remoteConfig
)

EventFlowObserve.shared.start(config: config)
```

### TinyBird Integration

Send captured requests to TinyBird for real-time analytics:

```swift
let tinyBirdConfig = TinyBirdLoggerConfig(
    datasource: "tracking_events",
    authToken: "p.your_write_only_token",
    region: .eu,  // or .us
    batchSize: 10,
    flushInterval: 30
)

let config = EventFlowObserveConfig(
    debugMode: true,
    tinyBirdLogging: tinyBirdConfig
)

EventFlowObserve.shared.start(config: config)
```

See [tinybird/README.md](../../tinybird/README.md) for TinyBird project setup instructions.

### Accessing Captured Requests

```swift
// Get all captured requests
let requests = EventFlowObserve.shared.capturedRequests

// Filter by domain
let mixpanelRequests = EventFlowObserve.shared.requests(forDomain: "mixpanel.com")

// Filter by method
let postRequests = EventFlowObserve.shared.requests(withMethod: "POST")

// Clear captured requests
EventFlowObserve.shared.clearCapturedRequests()
```

### Stopping the Observer

```swift
EventFlowObserve.shared.stop()
```

## Important Notes

- Start the observer as early as possible in your app lifecycle to ensure swizzling is in place before SDKs initialize
- The observer captures HTTP/HTTPS traffic only (not WebSockets or lower-level connections)
- Remote logging requests to your endpoint are excluded from capture to prevent infinite loops
