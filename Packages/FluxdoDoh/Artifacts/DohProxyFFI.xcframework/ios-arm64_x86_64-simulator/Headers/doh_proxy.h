#pragma once

#include <stdint.h>

/// Start the DOH proxy server (legacy API, uses Cloudflare DOH).
/// Returns the port number on success, or -1 on failure.
int32_t doh_proxy_start(int32_t port, int32_t prefer_ipv6);

/// Start the DOH proxy server with a specific DOH server URL.
/// Returns the port number on success, or -1 on failure.
int32_t doh_proxy_start_with_server(int32_t port, int32_t prefer_ipv6, const char *doh_server);

/// Start the DOH proxy server with a JSON configuration payload.
/// Returns the port number on success, or -1 on failure.
int32_t doh_proxy_start_with_config_json(const char *config_json);

/// Stop the DOH proxy server.
void doh_proxy_stop(void);

/// Check if the DOH proxy is running. Returns 1 if running, 0 if not.
int32_t doh_proxy_is_running(void);

/// Get the DOH proxy port. Returns the port number, or 0 if not running.
int32_t doh_proxy_get_port(void);

/// Initialize logging (call once at startup).
void doh_proxy_init_logging(void);

/// Lookup ECH config for a host via DOH DNS HTTPS record.
/// Returns a heap-allocated JSON string; caller must free with doh_proxy_free_string.
char *doh_proxy_lookup_ech_config(const char *host, const char *doh_server);

/// Lookup IP addresses for a host via DOH A/AAAA records.
/// Returns a heap-allocated JSON string; caller must free with doh_proxy_free_string.
char *doh_proxy_lookup_ip(const char *host, const char *doh_server, int32_t prefer_ipv6);

/// Lookup a host in one round-trip and return IPs, ECH config and TTL.
/// Returns a heap-allocated JSON string; caller must free with doh_proxy_free_string.
char *doh_proxy_lookup_host(
    const char *host,
    const char *doh_server,
    const char *doh_server_ech,
    int32_t prefer_ipv6,
    int32_t force_refresh
);

/// Record a successful host->IP preference. Returns 1 on success, 0 on failure.
int32_t doh_proxy_record_host_success(
    const char *host,
    const char *doh_server,
    const char *doh_server_ech,
    int32_t prefer_ipv6,
    const char *ip
);

/// Clear the preferred IP for a host. Returns 1 on success, 0 on failure.
int32_t doh_proxy_clear_preferred_host_ip(
    const char *host,
    const char *doh_server,
    const char *doh_server_ech,
    int32_t prefer_ipv6
);

/// Clear all DNS caches. Returns 1.
int32_t doh_proxy_clear_dns_cache(void);

/// Free a string returned by the lookup functions.
void doh_proxy_free_string(char *ptr);
