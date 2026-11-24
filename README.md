# Pandora Connect — foundation v0.1.0

Reusable Node.js domain module for opt-in guest Wi-Fi customer retention. Synthetic demo only; not installed on any network. No dependencies, secrets, advertising SDKs, device fingerprints or packet inspection.

Run `npm test` and `npm run demo`. Import `Connect` from `index.mjs` to exercise the reference domain model. Do not expose its methods directly over HTTP. The in-memory adapter is intentionally nonpersistent and is not a security boundary. Server-side authentication, tenant binding, verified registration, evidence validation, durable RLS storage, audit policies and rate limiting are required before use with real people. Inputs asserting age, identity or consent are trusted-server inputs, not browser-supplied facts. Visit IDs must be issued once per authenticated visit by the production adapter, not each page view.

## Proposed integration
- Router adapter: managed gateway returns anonymous per-site traffic summaries; network security telemetry stays separate and local, governed by a separate retention/access policy.
- Captive portal: guest access remains available without marketing consent. Optional verified enrollment and separate analytics/email/SMS/ads/portal choices; no prechecked boxes. Identity never inferred from MAC or private traffic. Marketing requires adult eligibility.
- Supabase: tenant-scoped customer IDs, channel consent receipts, allowlisted first-party events, separate aggregate network windows; RLS and server-only writes with tenant membership checks. Keep contact addresses in a separately protected vault. Define legally appropriate retention and data rights before rollout. Current demo deletes event history on analytics withdrawal and deletes demo records on erasure; production must handle backups, consent audit evidence and provider suppression.
- Vercel dashboard: roles, permissioned aggregates, consent/segment review, no raw network data in customer profiles. AI analyzes aggregate cohorts; use rules as baseline, validate any predictive score, avoid sensitive inferences. No automatic transmission to ad providers; recheck eligibility, provider policy and consent immediately before approved sends and handle revocation at providers.
- Roadmap: visit frequency, loyalty and rewards, booking/POS integration, campaign attribution and holdout tests, capacity analytics, service feedback, business-specific adapters, tenant-bounded offers. No cross-business profile sharing by default.

## Not implemented
Router integration, durable persistence, authentication, real contact verification, UI, provider integrations, AI inference, legal review and live deployment. Reference tests cover domain behavior only, not security of an integrated system. 90-day event/aggregate retention is a proposed configurable default, not an approved legal retention policy. No real customer data collected.
