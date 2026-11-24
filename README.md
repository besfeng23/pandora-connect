# Pandora Connect

Reusable customer intelligence module. Workspace v0.2; core package v0.1.0.

Production alias: https://pandora-connect.vercel.app. On Nov 25, 2026 PHT, Vercel reported READY for deployment dpl_8KPCj7WkpvCjSG23hnQAwqG72tVF, source commit 0a93f8564512cee8a37a0f732948a6c2e5d632a2; build logs confirm 15/15 tests passed. Independent HTTP/browser checks could not be completed. Real owner login remains unverified.

Database: project xyefkykwuppbweabvvmk (Memory); isolated pandora_connect schema, eight RLS-enabled tables. Existing public and plp_runtime table counts unchanged. Two namespaced security-invoker RPCs added to public; existing tables and auth configuration not changed. No real tenants, memberships, customers, events, gateways or telemetry created. Rollback tests verified tenant and gateway isolation, duplicate-window replacement, anonymous-session/non-member denial, consent counting and evidence-column restriction.

## Applied migrations
Sources under supabase/draft, in applied order; do not reapply on existing project:
- 20261124192309 pandora_connect_private_foundation: pandora_connect.sql (without explicit transaction wrapper)
- 20261124192605 pandora_connect_owner_dashboard: owner_dashboard.sql
- 20261124192804 pandora_connect_gateway_ingest: gateway_ingest.sql
- 20261124193010 pandora_connect_dashboard_hardening: dashboard_hardening.sql

## Components and limits
Read-only owner dashboard with existing Supabase email/password sign-in, memory-only access token and tenant memberships. Network, customer, campaign and setup screens. In-memory core with consent and segmentation rules is not yet a persistent customer writer. Local authorized OpenWrt inventory and aggregate-only gateway bridge require physical commissioning; no raw device data is uploaded. Guest portal is informational preview only. No live collection, AI provider, ad exports or campaign sends. No actual credentials committed; public repo.

## Commissioning
1. Verify intended owner's existing Supabase Auth email or UUID, then assign explicit tenant/site membership; test login.
2. Confirm first business/site and router make/model/firmware; provision dedicated bound gateway identity and verify measured aggregates, token rotation and physical Wi-Fi access.
3. Complete verified opt-in guest registration, adult eligibility, privacy notices, retention/deletion and server-only event writes before collection. Network access independent of marketing. Never link MAC addresses or private traffic to marketing identity.
4. Connect authorized AI/advertising accounts, consent-gated provider exports, revocation and approval flow. No automatic ad spending or cross-business identity sharing.
5. Verify HTTP/mobile/owner sign-in and monitoring before unrestricted launch.

Run npm test and npm run demo. See gateway/README.md. Pandora Memory connection failed; this record documents verified engineering outcomes, not approved canonical Memory.

## Workspace v0.3 — 2026-11-25 PHT
Production alias assigned to Vercel READY deployment dpl_Exbgwgf3pC1EbgMktN6bdfaLSjPt at ff2efe4b8ef5e8a219686e26ec00d352b7d718bc; build logs show 15/15 tests passed. Premium dark workspace, responsive navigation, redesigned guest preview, explicitly synthetic demo separated from authenticated mode, live seven-day UTC activity chart, retention cohorts and campaign planning. No live audience delivery. Migration 20261124193456 pandora_connect_customer_insights (supabase/draft/customer_insights.sql) replaces overview with consent-qualified aggregate analytics. Rollback SQL verified one authorized tenant, withdrawn consent and nonadult exclusion, frequent visitor count and seven-date series; customers/events returned to zero. Independent URL/browser checks unavailable; do not claim visual acceptance or live owner sign-in. Router commissioning, verified enrollment, admin membership and provider connections remain outstanding. Pandora Memory health returned internal error; this is a repo record only.
