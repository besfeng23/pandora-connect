# Gateway and first-party event bridges

Physical installation is not verified. Use only on an administrator-controlled network with explicit authorization. No raw station identifiers, IP addresses, hostnames, private traffic, or browsing history are uploaded or linked to marketing.

## Local inventory
Run `sh gateway/openwrt-local-inventory.sh` on a supported OpenWrt router to inspect local DHCP leases and wireless station information. Leases do not necessarily mean connected devices. Randomized MAC addresses are not stable identities. Keep output local and access restricted.

## Measured network window
On a compatible Linux device with Node 20+, iw, and access to the configured wireless interfaces, set CONNECT_WIFI_INTERFACES to a comma-separated list of managed interfaces. Start `node gateway/station-window.mjs` within 15 seconds of a five-minute UTC boundary. It samples station counters for one window; identifiers exist only in process memory. Output is aggregate JSON: windowStart, connections (station observations at final sample, not unique people), bytes (known nonnegative counter deltas), samples. Counter resets and newly seen stations are not fabricated; traffic may be undercounted when devices disconnect between samples. Validate against real hardware before use. Do not run overlapping windows or multiple reporters for the same site.

A dedicated verified Auth account must be bound by the owner to the intended site. Use a protected local environment with NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, CONNECT_GATEWAY_ACCESS_TOKEN, CONNECT_TENANT_ID, CONNECT_SITE_ID. Submit a measured window with `node gateway/send-window.mjs <connections> <bytes> <windowStart-UTC>`. Retry with the exact same measured window and totals. No service-role credentials. Scheduling, token rotation and physical commissioning require local administrator setup.

## Trusted checkout / booking event
Use a separate verified Auth account bound as a site event writer, not a gateway or owner account. Provide CONNECT_EVENT_ACCESS_TOKEN instead of the gateway token. After the customer voluntarily presents their current tenant-specific reference in an authorized first-party transaction, submit `node gateway/send-event.mjs <customer-uuid> <event-uuid> <visit|purchase|offer_redeemed> <occurred-at-ISO>`. Use a stable event UUID and exact original timestamp for retries. Never generate events from network device observations or upload unconsented contacts. The database checks the active invitation, current analytics consent, timestamp, site and idempotency. No live POS or gateway has been enrolled.

Actual cloud accounts, hardware permissions, credential rotation, and operational acceptance remain commissioning requirements. No automatic advertisements or messages.
