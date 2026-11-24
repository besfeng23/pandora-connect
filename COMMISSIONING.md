# Production commissioning gates

Verified on November 25, 2026 PHT. The Supabase project is shared with other workloads; do not change global authentication or grant existing accounts automatically.

## First owner
The project currently contains no Auth users, tenants or memberships. Confirm the exact intended owner email with the owner. Create the account using the approved Supabase Auth workflow, then require the person to verify and sign in. Do not use a default password, reuse another application's user, expose a service credential, or assign a guessed email.

An authorized database administrator must bootstrap only the verified account's explicit UUID and intended business name. The following is a template, not an executed migration. Replace both values with owner-approved inputs using safe bound parameters or SQL literals:
```sql
begin;
do $$
declare owner_id uuid := '<VERIFIED_OWNER_UUID>'; business_name text := '<APPROVED_BUSINESS_NAME>'; tid uuid;
begin
 if not exists(select 1 from auth.users u where u.id=owner_id and u.email_confirmed_at is not null and not coalesce(u.is_anonymous,false) and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now())) then raise exception 'Verified owner required';end if;
 if exists(select 1 from pandora_connect.memberships m where m.user_id=owner_id) then raise exception 'Owner already has a workspace; review existing record';end if;
 insert into pandora_connect.tenants(name) values(business_name) returning id into tid;
 insert into pandora_connect.memberships(tenant_id,user_id,role) values(tid,owner_id,'owner');
end $$;
commit;
```
Sign in at the owner dashboard and verify only the intended business appears. Use System setup to create the location. Invite only verified adults who have agreed to take part in the pilot, and create separate dedicated verified accounts for gateway and first-party writer. No automatic marketing.

## Physical Wi-Fi
Identify hardware model and firmware, establish admin authorization, verify compatible local interfaces and network segmentation, configure gateway bridge (gateway/README.md). Measure windows and check database totals against the device. A real captive access controller, access redirect and internet authorization flow depend on the chosen router. Keep guest access independent of marketing.

## First-party customer events
The invited guest signs in and chooses analytics separately from portal offers. A voluntary customer reference appears only while analytics permission is current. Use it for explicitly linked first-party checkout/booking activity; never associate it with MAC or IP data. Use separate site-bound event writer and stable transaction event ID. Test opt-out, reference removal and data erasure. Approve guest notices, retention, age assurance and deletion policy before real collection.

## AI and marketing
Local aggregate recommendations work without external services. Gemini adapter is implemented but disabled; only enable CONNECT_GEMINI_ENABLED after approved processor terms, verified vault-backed server credential GEMINI_API_KEY, confirmed GEMINI_MODEL and spend/rate limits. Owner must explicitly request each analysis; minimum 50 analytics opt-ins, counts under 10 suppressed, remaining counts rounded down to tens, no names, IDs, private traffic or raw events sent. No Gemini request was made during verification.

Campaign studio stores drafts and portal audience counts only; email, SMS and advertising preview is blocked. Actual Meta/Google ads and email/SMS delivery require eligible accounts, channel-specific notices and verified opt-ins, approved provider access, secure identifiers, suppression/withdrawal, reviewed exports, rate limits and spending approval. Do not connect or execute live campaigns before those are in place. Portal offer delivery itself requires physical captive portal commissioning.

## Acceptance
Run npm test, verify production deployment and HTTP/browser/mobile access, test actual owner and guest sign-in and physical gateway, review security advisories and monitoring. Only then authorize a limited pilot. Do not claim commercial launch readiness from build status.
