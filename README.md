# EventFlowObserve

Passively intercept and observe HTTP/HTTPS network traffic from analytics SDKs in your apps.

## SDKs

| Platform | Location | Status |
|----------|----------|--------|
| iOS/Swift | [sdk/swift](./sdk/swift) | Available |
| Android/Kotlin | sdk/android | Coming soon |
| React Native | sdk/react-native | Coming soon |

## Overview

EventFlowObserve allows you to monitor outgoing network requests from third-party analytics SDKs (Mixpanel, Firebase, Facebook, etc.) without modifying their code. Useful for:

- Debugging analytics implementations
- Auditing what data SDKs are sending
- Building analytics observability dashboards
- QA testing of event tracking

## Quick Start (iOS)

```swift
import EventFlowObserve

// Start observing
EventFlowObserve.shared.start(config: .debug)

// Handle captured requests
EventFlowObserve.shared.onRequestCaptured { request in
    print("Captured: \(request.method) \(request.url)")
}
```

See [sdk/swift/README.md](./sdk/swift/README.md) for full documentation.

## License

MIT
