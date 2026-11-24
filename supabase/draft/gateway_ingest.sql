-- Aggregate-only gateway ingest. Each dedicated authenticated gateway must be explicitly bound to a site by an administrator.
create table pandora_connect.gateway_bindings(
 tenant_id uuid not null,site_id uuid not null,user_id uuid not null,
 created_at timestamptz not null default now(),
 primary key(tenant_id,site_id,user_id),
 foreign key(tenant_id,site_id) references pandora_connect.sites(tenant_id,id) on delete cascade
);
alter table pandora_connect.gateway_bindings enable row level security;
revoke all on pandora_connect.gateway_bindings from public,anon,authenticated,service_role;
grant select on pandora_connect.gateway_bindings to authenticated;
create policy connect_gateway_self on pandora_connect.gateway_bindings for select to authenticated using(user_id=(select auth.uid()) and coalesce((select auth.jwt())->>'is_anonymous','false')='false');
grant insert on pandora_connect.network_windows to authenticated;
grant update(connection_count,bytes_transferred) on pandora_connect.network_windows to authenticated;
create policy connect_gateway_window_read on pandora_connect.network_windows for select to authenticated using(exists(select 1 from pandora_connect.gateway_bindings b where b.tenant_id=network_windows.tenant_id and b.site_id=network_windows.site_id));
create policy connect_gateway_window_insert on pandora_connect.network_windows for insert to authenticated with check(exists(select 1 from pandora_connect.gateway_bindings b where b.tenant_id=network_windows.tenant_id and b.site_id=network_windows.site_id) and window_start>=now()-interval '24 hours' and window_start<=now() and connection_count<=1000000 and bytes_transferred<=1000000000000000);
create policy connect_gateway_window_update on pandora_connect.network_windows for update to authenticated using(exists(select 1 from pandora_connect.gateway_bindings b where b.tenant_id=network_windows.tenant_id and b.site_id=network_windows.site_id)) with check(exists(select 1 from pandora_connect.gateway_bindings b where b.tenant_id=network_windows.tenant_id and b.site_id=network_windows.site_id) and window_start>=now()-interval '24 hours' and window_start<=now() and connection_count<=1000000 and bytes_transferred<=1000000000000000);
create function public.pandora_connect_ingest_network(p_tenant uuid,p_site uuid,p_window timestamptz,p_connections bigint,p_bytes bigint) returns void language plpgsql security invoker set search_path='' as $$
begin
 if (select auth.uid()) is null or not exists(select 1 from pandora_connect.gateway_bindings b where b.tenant_id=p_tenant and b.site_id=p_site) then raise exception 'Gateway not authorized' using errcode='42501'; end if;
 if p_window is null or p_window<>date_trunc('hour',p_window)+(floor(extract(minute from p_window)/5)::int*interval '5 minutes') or p_window<now()-interval '24 hours' or p_window>now() or p_connections is null or p_connections not between 0 and 1000000 or p_bytes is null or p_bytes not between 0 and 1000000000000000 then raise exception 'Invalid aggregate window' using errcode='22023'; end if;
 insert into pandora_connect.network_windows(tenant_id,site_id,window_start,connection_count,bytes_transferred) values(p_tenant,p_site,p_window,p_connections,p_bytes) on conflict(tenant_id,site_id,window_start) do update set connection_count=excluded.connection_count,bytes_transferred=excluded.bytes_transferred;
end;
$$;
revoke all on function public.pandora_connect_ingest_network(uuid,uuid,timestamptz,bigint,bigint) from public,anon,authenticated,service_role;
grant execute on function public.pandora_connect_ingest_network(uuid,uuid,timestamptz,bigint,bigint) to authenticated;
