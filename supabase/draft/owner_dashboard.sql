-- Read-only, tenant-bound owner dashboard. No service-role key required.
-- No existing public tables or auth configuration are changed.
grant usage on schema pandora_connect to authenticated;
grant select on pandora_connect.tenants, pandora_connect.memberships, pandora_connect.sites, pandora_connect.customers, pandora_connect.consent_receipts, pandora_connect.events, pandora_connect.network_windows to authenticated;
create policy connect_membership_self on pandora_connect.memberships for select to authenticated using (user_id=(select auth.uid()) and coalesce((select auth.jwt())->>'is_anonymous','false')='false');
create policy connect_tenant_read on pandora_connect.tenants for select to authenticated using (exists(select 1 from pandora_connect.memberships m where m.tenant_id=tenants.id));
create policy connect_site_read on pandora_connect.sites for select to authenticated using (exists(select 1 from pandora_connect.memberships m where m.tenant_id=sites.tenant_id));
create policy connect_customer_read on pandora_connect.customers for select to authenticated using (exists(select 1 from pandora_connect.memberships m where m.tenant_id=customers.tenant_id));
create policy connect_consent_read on pandora_connect.consent_receipts for select to authenticated using (exists(select 1 from pandora_connect.memberships m where m.tenant_id=consent_receipts.tenant_id));
create policy connect_events_read on pandora_connect.events for select to authenticated using (exists(select 1 from pandora_connect.memberships m where m.tenant_id=events.tenant_id));
create policy connect_network_read on pandora_connect.network_windows for select to authenticated using (exists(select 1 from pandora_connect.memberships m where m.tenant_id=network_windows.tenant_id));
create function public.pandora_connect_overview() returns jsonb language sql stable security invoker set search_path='' as $$
select coalesce(jsonb_agg(jsonb_build_object(
 'id',t.id,'name',t.name,'role',m.role,
 'customers',(select count(*) from pandora_connect.customers c where c.tenant_id=t.id),
 'sites',(select count(*) from pandora_connect.sites s where s.tenant_id=t.id),
 'visits30d',(select count(*) from pandora_connect.events e where e.tenant_id=t.id and e.kind='visit' and e.occurred_at>=now()-interval '30 days'),
 'purchases30d',(select count(*) from pandora_connect.events e where e.tenant_id=t.id and e.kind='purchase' and e.occurred_at>=now()-interval '30 days'),
 'networkWindows24h',(select count(*) from pandora_connect.network_windows w where w.tenant_id=t.id and w.window_start>=now()-interval '24 hours'),
 'connections24h',(select coalesce(sum(w.connection_count),0) from pandora_connect.network_windows w where w.tenant_id=t.id and w.window_start>=now()-interval '24 hours'),
 'analyticsOptIns',(select count(*) from pandora_connect.customers c where c.tenant_id=t.id and c.adult_verified and (select r.granted from pandora_connect.consent_receipts r where r.tenant_id=c.tenant_id and r.customer_id=c.id and r.purpose='analytics' order by r.recorded_at desc,r.id desc limit 1) is true)
) order by t.name,t.id),'[]'::jsonb) from pandora_connect.tenants t join pandora_connect.memberships m on m.tenant_id=t.id and m.user_id=(select auth.uid());
$$;
revoke all on function public.pandora_connect_overview() from public, anon, authenticated, service_role;
grant execute on function public.pandora_connect_overview() to authenticated;
