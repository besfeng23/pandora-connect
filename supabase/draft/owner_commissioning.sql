-- Owner-only commissioning on existing v0.4 schema. No new auth users.
-- The private implementation is not a public security-definer RPC.
alter table pandora_connect.gateway_bindings add constraint connect_gateway_auth_fk foreign key(user_id) references auth.users(id) on delete cascade;
create function pandora_connect.commission(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); tid uuid; sid uuid; uid uuid; site_name text; g pandora_connect.guest_access%rowtype; purpose_name text; previous_choice boolean;
begin
 if actor is null or coalesce(auth.jwt()->>'is_anonymous','false')<>'false' then raise exception 'Authentication required' using errcode='42501';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or pg_column_size(p_data)>4096 then raise exception 'Invalid request' using errcode='22023';end if;
 tid:=(p_data->>'tenantId')::uuid;
 if not exists(select 1 from pandora_connect.memberships m where m.tenant_id=tid and m.user_id=actor and m.role='owner') then raise exception 'Owner membership required' using errcode='42501';end if;
 if p_action='status' then
 return jsonb_build_object(
 'sites',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name) order by s.name,s.id) from pandora_connect.sites s where s.tenant_id=tid),'[]'::jsonb),
 'guests',coalesce((select jsonb_agg(jsonb_build_object('userId',a.user_id,'enabled',a.enabled,'adultVerified',a.adult_verified,'enrolled',a.customer_id is not null) order by a.created_at desc) from (select * from pandora_connect.guest_access where tenant_id=tid order by created_at desc limit 100) a),'[]'::jsonb),
 'gateways',coalesce((select jsonb_agg(jsonb_build_object('siteId',b.site_id,'userId',b.user_id)) from pandora_connect.gateway_bindings b where b.tenant_id=tid),'[]'::jsonb),
 'writers',coalesce((select jsonb_agg(jsonb_build_object('siteId',b.site_id,'userId',b.user_id)) from pandora_connect.event_writer_bindings b where b.tenant_id=tid),'[]'::jsonb));
 elsif p_action='site_create' then
 site_name:=btrim(p_data->>'name');
 if site_name is null or char_length(site_name) not between 1 and 80 then raise exception 'Invalid location name' using errcode='22023';end if;
 sid:=(p_data->>'siteId')::uuid;
 if sid is null then raise exception 'Location ID required' using errcode='22023';end if;
 insert into pandora_connect.sites(tenant_id,id,name) values(tid,sid,site_name) on conflict(tenant_id,id) do nothing;
 if not exists(select 1 from pandora_connect.sites s where s.tenant_id=tid and s.id=sid and s.name=site_name) then raise exception 'Location ID conflict' using errcode='22023';end if;
 return jsonb_build_object('id',sid);
 end if;
 uid:=(p_data->>'userId')::uuid;
 if uid is null then raise exception 'Account ID required' using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended('pandora-connect-account:'||uid::text,0));
 if p_action='guest_disable' then
 select * into g from pandora_connect.guest_access where tenant_id=tid and user_id=uid for update;
 if not found then raise exception 'Invitation unavailable' using errcode='42501';end if;
 update pandora_connect.guest_access set enabled=false,adult_verified=false where tenant_id=tid and user_id=uid;
 if g.customer_id is not null then
  update pandora_connect.customers set adult_verified=false where tenant_id=tid and id=g.customer_id;
  foreach purpose_name in array array['analytics','portal','email','sms','ads'] loop
   select r.granted into previous_choice from pandora_connect.consent_receipts r where r.tenant_id=tid and r.customer_id=g.customer_id and r.purpose=purpose_name order by r.recorded_at desc,r.id desc limit 1;
   if previous_choice is true then insert into pandora_connect.consent_receipts(tenant_id,customer_id,purpose,granted,notice_version,evidence_ref,recorded_at) values(tid,g.customer_id,purpose_name,false,'connect-guest-v1','owner-access-revocation',clock_timestamp());end if;
  end loop;
  delete from pandora_connect.events where tenant_id=tid and customer_id=g.customer_id;
 end if;
 return jsonb_build_object('disabled',true);
 end if;
 if p_action in ('gateway_revoke','writer_revoke','gateway_bind','writer_bind') then
 sid:=(p_data->>'siteId')::uuid;
 if not exists(select 1 from pandora_connect.sites s where s.tenant_id=tid and s.id=sid) then raise exception 'Location unavailable' using errcode='42501';end if;
 if p_action='gateway_revoke' then delete from pandora_connect.gateway_bindings where tenant_id=tid and site_id=sid and user_id=uid;return jsonb_build_object('revoked',true);end if;
 if p_action='writer_revoke' then delete from pandora_connect.event_writer_bindings where tenant_id=tid and site_id=sid and user_id=uid;return jsonb_build_object('revoked',true);end if;
 end if;
 if p_action not in ('guest_invite','gateway_bind','writer_bind') or p_action is null then raise exception 'Unknown action' using errcode='22023';end if;
 if not exists(select 1 from auth.users u where u.id=uid and u.email_confirmed_at is not null and not coalesce(u.is_anonymous,false) and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now())) then raise exception 'Verified existing account required' using errcode='42501';end if;
 if exists(select 1 from pandora_connect.memberships m where m.user_id=uid) then raise exception 'Use a separate account without workspace privileges' using errcode='42501';end if;
 if p_action='guest_invite' then
  if p_data->'adultVerified' is distinct from 'true'::jsonb then raise exception 'Independent adult verification required' using errcode='22023';end if;
  if exists(select 1 from pandora_connect.gateway_bindings b where b.user_id=uid) or exists(select 1 from pandora_connect.event_writer_bindings b where b.user_id=uid) then raise exception 'Integration accounts cannot be guests' using errcode='42501';end if;
  insert into pandora_connect.guest_access(tenant_id,user_id,enabled,adult_verified) values(tid,uid,true,true) on conflict(tenant_id,user_id) do update set enabled=true,adult_verified=true;
  update pandora_connect.customers c set adult_verified=true where c.tenant_id=tid and c.id=(select a.customer_id from pandora_connect.guest_access a where a.tenant_id=tid and a.user_id=uid);
  return jsonb_build_object('invited',true);
 end if;
 if p_data->'dedicatedAccount' is distinct from 'true'::jsonb or exists(select 1 from pandora_connect.guest_access a where a.user_id=uid) then raise exception 'Dedicated integration account required' using errcode='42501';end if;
 if p_action='gateway_bind' then
  if exists(select 1 from pandora_connect.event_writer_bindings b where b.user_id=uid) or exists(select 1 from pandora_connect.gateway_bindings b where b.user_id=uid and (b.tenant_id<>tid or b.site_id<>sid)) then raise exception 'Account already bound' using errcode='42501';end if;
  insert into pandora_connect.gateway_bindings(tenant_id,site_id,user_id) values(tid,sid,uid) on conflict do nothing;
 else
  if exists(select 1 from pandora_connect.gateway_bindings b where b.user_id=uid) or exists(select 1 from pandora_connect.event_writer_bindings b where b.user_id=uid and (b.tenant_id<>tid or b.site_id<>sid)) then raise exception 'Account already bound' using errcode='42501';end if;
  insert into pandora_connect.event_writer_bindings(tenant_id,site_id,user_id) values(tid,sid,uid) on conflict do nothing;
 end if;
 return jsonb_build_object('bound',true);
end;
$$;
revoke all on function pandora_connect.commission(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function pandora_connect.commission(text,jsonb) to authenticated;
create function public.pandora_connect_commission(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$ select pandora_connect.commission(p_action,p_data); $$;
revoke all on function public.pandora_connect_commission(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.pandora_connect_commission(text,jsonb) to authenticated;
