-- Live consent-qualified aggregates, no customer identifiers returned.
create or replace function public.pandora_connect_overview() returns jsonb language sql stable security invoker set search_path='' as $$
with allowed as (
 select t.id,t.name,m.role from pandora_connect.tenants t join pandora_connect.memberships m on m.tenant_id=t.id and m.user_id=(select auth.uid())
), eligible as (
 select c.tenant_id,c.id,r.recorded_at as consent_at from pandora_connect.customers c join allowed a on a.id=c.tenant_id
 cross join lateral (select granted,recorded_at from pandora_connect.consent_receipts r where r.tenant_id=c.tenant_id and r.customer_id=c.id and r.purpose='analytics' order by r.recorded_at desc,r.id desc limit 1) r
 where c.adult_verified and r.granted
), permitted as (
 select e.tenant_id,e.customer_id,e.kind,e.occurred_at from pandora_connect.events e join eligible c on c.tenant_id=e.tenant_id and c.id=e.customer_id
 where e.occurred_at>=greatest(c.consent_at,now()-interval '90 days') and e.occurred_at<=now()
), visits as (
 select tenant_id,customer_id,count(*) filter(where occurred_at>=now()-interval '30 days') as recent,count(*) as total from permitted where kind='visit' group by tenant_id,customer_id
), days as (
 select (now() at time zone 'UTC')::date-i as day from generate_series(6,0,-1) i
)
select coalesce(jsonb_agg(jsonb_build_object(
 'id',a.id,'name',a.name,'role',a.role,
 'customers',(select count(*) from pandora_connect.customers c where c.tenant_id=a.id),
 'sites',(select count(*) from pandora_connect.sites s where s.tenant_id=a.id),
 'visits30d',(select count(*) from permitted e where e.tenant_id=a.id and e.kind='visit' and e.occurred_at>=now()-interval '30 days'),
 'purchases30d',(select count(*) from permitted e where e.tenant_id=a.id and e.kind='purchase' and e.occurred_at>=now()-interval '30 days'),
 'networkWindows24h',(select count(*) from pandora_connect.network_windows w where w.tenant_id=a.id and w.window_start>=now()-interval '24 hours'),
 'connections24h',(select coalesce(sum(w.connection_count),0) from pandora_connect.network_windows w where w.tenant_id=a.id and w.window_start>=now()-interval '24 hours'),
 'analyticsOptIns',(select count(*) from eligible c where c.tenant_id=a.id),
 'activity7d',(select jsonb_agg(jsonb_build_object('date',d.day,'visits',(select count(*) from permitted e where e.tenant_id=a.id and e.kind='visit' and (e.occurred_at at time zone 'UTC')::date=d.day)) order by d.day) from days d),
 'frequentVisitors',(select count(*) from visits v where v.tenant_id=a.id and v.recent>=3),
 'inactiveVisitors',(select count(*) from visits v where v.tenant_id=a.id and v.recent=0 and v.total>0),
 'purchasingCustomers',(select count(distinct e.customer_id) from permitted e where e.tenant_id=a.id and e.kind='purchase' and e.occurred_at>=now()-interval '30 days')
) order by a.name,a.id),'[]'::jsonb) from allowed a;
$$;
revoke all on function public.pandora_connect_overview() from public,anon,service_role;
grant execute on function public.pandora_connect_overview() to authenticated;
