-- Restrict dashboard reads and remove duplicate SELECT policy evaluation.
create index connect_events_site_idx on pandora_connect.events(tenant_id,site_id);
create index connect_memberships_user_idx on pandora_connect.memberships(user_id,tenant_id);
create index connect_gateway_user_idx on pandora_connect.gateway_bindings(user_id,tenant_id,site_id);
alter policy connect_network_read on pandora_connect.network_windows using (
 exists(select 1 from pandora_connect.memberships m where m.tenant_id=network_windows.tenant_id)
 or exists(select 1 from pandora_connect.gateway_bindings b where b.tenant_id=network_windows.tenant_id and b.site_id=network_windows.site_id)
);
drop policy connect_gateway_window_read on pandora_connect.network_windows;
alter table pandora_connect.network_windows add constraint connect_five_minute_window check (mod(extract(epoch from window_start),300)=0);
revoke select on pandora_connect.consent_receipts from authenticated;
grant select(tenant_id,customer_id,id,purpose,granted,recorded_at) on pandora_connect.consent_receipts to authenticated;
