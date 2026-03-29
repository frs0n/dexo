import Foundation
import CDohProxy

/// A Swift wrapper around the Rust DOH proxy FFI.
public final class DohProxy {

    public static let shared = DohProxy()

    private init() {}

    // MARK: - Proxy lifecycle

    /// Start the proxy. Returns the bound port, or throws on failure.
    @discardableResult
    public func start(port: Int32 = 0, preferIPv6: Bool = false) throws -> Int32 {
        doh_proxy_init_logging()
        let result = doh_proxy_start(port, preferIPv6 ? 1 : 0)
        guard result > 0 else { throw DohProxyError.startFailed }
        return result
    }

    /// Start the proxy with a specific DOH server URL. Returns the bound port.
    @discardableResult
    public func start(port: Int32 = 0, preferIPv6: Bool = false, dohServer: String) throws -> Int32 {
        doh_proxy_init_logging()
        let result = dohServer.withCString { ptr in
            doh_proxy_start_with_server(port, preferIPv6 ? 1 : 0, ptr)
        }
        guard result > 0 else { throw DohProxyError.startFailed }
        return result
    }

    /// Start the proxy with a JSON config string. Returns the bound port.
    @discardableResult
    public func start(configJSON: String) throws -> Int32 {
        doh_proxy_init_logging()
        let result = configJSON.withCString { ptr in
            doh_proxy_start_with_config_json(ptr)
        }
        guard result > 0 else { throw DohProxyError.startFailed }
        return result
    }

    /// Stop the proxy.
    public func stop() {
        doh_proxy_stop()
    }

    /// Whether the proxy is currently running.
    public var isRunning: Bool {
        doh_proxy_is_running() != 0
    }

    /// The port the proxy is bound to, or 0 if not running.
    public var port: Int32 {
        doh_proxy_get_port()
    }

    // MARK: - DNS lookups

    /// Look up IP addresses for a host via DOH.
    public func lookupIP(host: String, dohServer: String? = nil, preferIPv6: Bool = false) throws -> [String] {
        let json = try callLookup { hostPtr in
            if let server = dohServer {
                return server.withCString { serverPtr in
                    doh_proxy_lookup_ip(hostPtr, serverPtr, preferIPv6 ? 1 : 0)
                }
            } else {
                return doh_proxy_lookup_ip(hostPtr, nil, preferIPv6 ? 1 : 0)
            }
        }(host)
        let result = try parseJSON(json)
        guard let data = result["data"] as? [String] else {
            throw DohProxyError.unexpectedResponse
        }
        return data
    }

    /// Look up ECH config for a host via DOH DNS HTTPS record.
    public func lookupECHConfig(host: String, dohServer: String? = nil) throws -> Data? {
        let json = try callLookup { hostPtr in
            if let server = dohServer {
                return server.withCString { serverPtr in
                    doh_proxy_lookup_ech_config(hostPtr, serverPtr)
                }
            } else {
                return doh_proxy_lookup_ech_config(hostPtr, nil)
            }
        }(host)
        let result = try parseJSON(json)
        guard let b64 = result["data"] as? String else { return nil }
        return Data(base64Encoded: b64)
    }

    /// Look up a host and return IPs, optional ECH config, and TTL.
    public func lookupHost(
        host: String,
        dohServer: String? = nil,
        dohServerECH: String? = nil,
        preferIPv6: Bool = false,
        forceRefresh: Bool = false
    ) throws -> HostLookupResult {
        let rawJSON = host.withCString { hostPtr -> String in
            let ptr: UnsafeMutablePointer<CChar>?
            if let server = dohServer {
                ptr = server.withCString { serverPtr -> UnsafeMutablePointer<CChar>? in
                    if let ech = dohServerECH {
                        return ech.withCString { echPtr in
                            doh_proxy_lookup_host(hostPtr, serverPtr, echPtr, preferIPv6 ? 1 : 0, forceRefresh ? 1 : 0)
                        }
                    } else {
                        return doh_proxy_lookup_host(hostPtr, serverPtr, nil, preferIPv6 ? 1 : 0, forceRefresh ? 1 : 0)
                    }
                }
            } else {
                ptr = doh_proxy_lookup_host(hostPtr, nil, nil, preferIPv6 ? 1 : 0, forceRefresh ? 1 : 0)
            }
            defer { if let p = ptr { doh_proxy_free_string(p) } }
            guard let p = ptr else { return "{\"ok\":false,\"error\":\"null pointer\"}" }
            return String(cString: p)
        }
        let dict = try parseJSONString(rawJSON)
        guard let ips = dict["ips"] as? [String] else {
            throw DohProxyError.unexpectedResponse
        }
        let echB64 = dict["ech"] as? String
        let echData = echB64.flatMap { Data(base64Encoded: $0) }
        let ttl = (dict["ttl_secs"] as? Double).map { UInt64($0) } ?? 0
        let preferredIP = dict["preferred_ip"] as? String
        return HostLookupResult(ips: ips, echConfig: echData, preferredIP: preferredIP, ttlSeconds: ttl)
    }

    /// Clear all DNS caches.
    public func clearDNSCache() {
        doh_proxy_clear_dns_cache()
    }

    // MARK: - Private helpers

    private func callLookup(
        _ block: @escaping (UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
    ) -> (String) throws -> [String: Any] {
        return { host in
            let rawJSON = host.withCString { hostPtr -> String in
                let ptr = block(hostPtr)
                defer { if let p = ptr { doh_proxy_free_string(p) } }
                guard let p = ptr else { return "{\"ok\":false,\"error\":\"null pointer\"}" }
                return String(cString: p)
            }
            return try self.parseJSONString(rawJSON)
        }
    }

    private func parseJSON(_ dict: [String: Any]) throws -> [String: Any] {
        guard let ok = dict["ok"] as? Bool, ok else {
            let msg = dict["error"] as? String ?? "unknown error"
            throw DohProxyError.lookupFailed(msg)
        }
        return dict
    }

    private func parseJSONString(_ json: String) throws -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DohProxyError.unexpectedResponse
        }
        return try parseJSON(obj)
    }
}

// MARK: - Supporting types

public struct HostLookupResult {
    public let ips: [String]
    public let echConfig: Data?
    public let preferredIP: String?
    public let ttlSeconds: UInt64
}

public enum DohProxyError: Error, LocalizedError {
    case startFailed
    case lookupFailed(String)
    case unexpectedResponse

    public var errorDescription: String? {
        switch self {
        case .startFailed:            return "Failed to start DOH proxy"
        case .lookupFailed(let msg): return "DOH lookup failed: \(msg)"
        case .unexpectedResponse:    return "Unexpected response from DOH proxy"
        }
    }
}
