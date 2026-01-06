import Foundation

extension URLSessionConfiguration {

    /// Swizzles URLSessionConfiguration to automatically inject EventFlowObserveProtocol
    /// into all session configurations, enabling interception of requests from third-party SDKs
    static func swizzleForEventFlowObserve() {
        guard let defaultGetter = class_getClassMethod(Self.self, #selector(getter: `default`)),
              let swizzledDefaultGetter = class_getClassMethod(Self.self, #selector(getter: swizzled_default)) else {
            return
        }
        method_exchangeImplementations(defaultGetter, swizzledDefaultGetter)

        guard let ephemeralGetter = class_getClassMethod(Self.self, #selector(getter: ephemeral)),
              let swizzledEphemeralGetter = class_getClassMethod(Self.self, #selector(getter: swizzled_ephemeral)) else {
            return
        }
        method_exchangeImplementations(ephemeralGetter, swizzledEphemeralGetter)
    }

    /// Restores original URLSessionConfiguration behavior
    static func unswizzleForEventFlowObserve() {
        // Calling swizzle again swaps them back
        swizzleForEventFlowObserve()
    }

    @objc dynamic class var swizzled_default: URLSessionConfiguration {
        // This actually calls the original because methods are swapped
        let config = Self.swizzled_default // Calls original .default after swizzle
        config.injectEventFlowObserveProtocol()
        return config
    }

    @objc dynamic class var swizzled_ephemeral: URLSessionConfiguration {
        // This actually calls the original because methods are swapped
        let config = Self.swizzled_ephemeral // Calls original .ephemeral after swizzle
        config.injectEventFlowObserveProtocol()
        return config
    }

    private func injectEventFlowObserveProtocol() {
        guard EventFlowObserve.shared.isActive else { return }

        var protocols = self.protocolClasses ?? []

        // Only add if not already present
        if !protocols.contains(where: { $0 == EventFlowObserveProtocol.self }) {
            protocols.insert(EventFlowObserveProtocol.self, at: 0)
            self.protocolClasses = protocols
        }
    }
}
