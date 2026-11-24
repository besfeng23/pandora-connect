-- REVIEW ONLY: not applied; do not expose via Data API.
-- Intended for owner-approved project xyefkykwuppbweabvvmk.
-- No changes to public, auth or other application schemas.
begin;
create schema pandora_connect;
revoke all on schema pandora_connect from public, anon, authenticated, service_role;
create table pandora_connect.tenants (
 id uuid primary key default gen_random_uuid(),
 name text not null,
 created_at timestamptz not null default now()
);
create table pandora_connect.memberships (
 tenant_id uuid not null references pandora_connect.tenants(id) on delete cascade,
 user_id uuid not null,
 role text not null check (role in ('owner','operator','analyst')),
 primary key (tenant_id,user_id)
);
create table pandora_connect.sites (
 tenant_id uuid not null references pandora_connect.tenants(id) on delete cascade,
 id uuid not null default gen_random_uuid(),
 name text not null,
 primary key (tenant_id,id)
);
create table pandora_connect.customers (
 tenant_id uuid not null references pandora_connect.tenants(id) on delete cascade,
 id uuid not null default gen_random_uuid(),
 adult_verified boolean not null default false,
 created_at timestamptz not null default now(),
 primary key (tenant_id,id)
);
create table pandora_connect.consent_receipts (
 tenant_id uuid not null,
 customer_id uuid not null,
 id uuid not null default gen_random_uuid(),
 purpose text not null check (purpose in ('analytics','email','sms','ads','portal')),
 granted boolean not null,
 notice_version text not null,
 evidence_ref text not null,
 recorded_at timestamptz not null default now(),
 primary key (tenant_id,id),
 foreign key (tenant_id,customer_id) references pandora_connect.customers(tenant_id,id) on delete cascade
);
create table pandora_connect.events (
 tenant_id uuid not null,
 customer_id uuid not null,
 site_id uuid not null,
 id uuid not null,
 kind text not null check (kind in ('visit','purchase','offer_redeemed')),
 occurred_at timestamptz not null,
 primary key (tenant_id,id),
 foreign key (tenant_id,customer_id) references pandora_connect.customers(tenant_id,id) on delete cascade,
 foreign key (tenant_id,site_id) references pandora_connect.sites(tenant_id,id)
);
create table pandora_connect.network_windows (
 tenant_id uuid not null,
 site_id uuid not null,
 window_start timestamptz not null,
 connection_count bigint not null check (connection_count >= 0),
 bytes_transferred bigint not null check (bytes_transferred >= 0),
 primary key (tenant_id,site_id,window_start),
 foreign key (tenant_id,site_id) references pandora_connect.sites(tenant_id,id) on delete cascade
);
create index connect_events_customer_time on pandora_connect.events(tenant_id,customer_id,occurred_at);
create index connect_consent_customer_time on pandora_connect.consent_receipts(tenant_id,customer_id,purpose,recorded_at desc);
alter table pandora_connect.tenants enable row level security;
alter table pandora_connect.memberships enable row level security;
alter table pandora_connect.sites enable row level security;
alter table pandora_connect.customers enable row level security;
alter table pandora_connect.consent_receipts enable row level security;
alter table pandora_connect.events enable row level security;
alter table pandora_connect.network_windows enable row level security;
revoke all on all tables in schema pandora_connect from public, anon, authenticated, service_role;
-- Intentionally no API grants or policies until authenticated adapter and access tests are reviewed.
-- Consent enforcement, transaction ordering, retention, deletion, server role and provider suppression remain pending.
commit;
