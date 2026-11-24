-- Self-service reference and module-only erasure. Shared auth account is never deleted.
create or replace function pandora_connect.guest_preferences(p_tenant uuid,p_analytics boolean,p_portal boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare caller uuid:=auth.uid(); g pandora_connect.guest_access%rowtype; cid uuid; purpose_name text; choice boolean; last_choice boolean;
begin
 if caller is null or coalesce(auth.jwt()->>'is_anonymous','false')='true' or not exists(select 1 from auth.users u where u.id=caller and u.email_confirmed_at is not null and not coalesce(u.is_anonymous,false) and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now())) then raise exception 'Verified account required' using errcode='42501'; end if;
 if p_tenant is not null then
  if p_analytics is null or p_portal is null then raise exception 'Explicit choices required' using errcode='22023'; end if;
  select * into g from pandora_connect.guest_access where tenant_id=p_tenant and user_id=caller for update;
  if not found then raise exception 'Invitation required' using errcode='42501'; end if;
  if (p_analytics or p_portal) and (not g.enabled or not g.adult_verified) then raise exception 'Enrollment not enabled' using errcode='42501'; end if;
  cid:=g.customer_id;
  if cid is null and (p_analytics or p_portal) then
   insert into pandora_connect.customers(tenant_id,adult_verified) values(p_tenant,true) returning id into cid;
   update pandora_connect.guest_access set customer_id=cid where tenant_id=p_tenant and user_id=caller;
  end if;
  if cid is not null then
   foreach purpose_name in array array['analytics','portal'] loop
    choice:=case when purpose_name='analytics' then p_analytics else p_portal end;
    select r.granted into last_choice from pandora_connect.consent_receipts r where r.tenant_id=p_tenant and r.customer_id=cid and r.purpose=purpose_name order by r.recorded_at desc,r.id desc limit 1;
    if last_choice is distinct from choice then
     insert into pandora_connect.consent_receipts(tenant_id,customer_id,purpose,granted,notice_version,evidence_ref,recorded_at) values(p_tenant,cid,purpose_name,choice,'connect-guest-v1','authenticated-guest-choice',clock_timestamp());
    end if;
   end loop;
   if not p_analytics then delete from pandora_connect.events where tenant_id=p_tenant and customer_id=cid; end if;
  end if;
 end if;
 return coalesce((select jsonb_agg(jsonb_build_object('tenantId',a.tenant_id,'name',t.name,'eligible',a.enabled and a.adult_verified,'enrolled',a.customer_id is not null,'customerId',case when a.enabled and a.adult_verified and (select r.granted from pandora_connect.consent_receipts r where r.tenant_id=a.tenant_id and r.customer_id=a.customer_id and r.purpose='analytics' order by r.recorded_at desc,r.id desc limit 1) is true then a.customer_id else null end,'analytics',coalesce((select r.granted from pandora_connect.consent_receipts r where r.tenant_id=a.tenant_id and r.customer_id=a.customer_id and r.purpose='analytics' order by r.recorded_at desc,r.id desc limit 1),false),'portal',coalesce((select r.granted from pandora_connect.consent_receipts r where r.tenant_id=a.tenant_id and r.customer_id=a.customer_id and r.purpose='portal' order by r.recorded_at desc,r.id desc limit 1),false)) order by t.name,t.id) from pandora_connect.guest_access a join pandora_connect.tenants t on t.id=a.tenant_id where a.user_id=caller),'[]'::jsonb);
end;
$$;

create function pandora_connect.erase_guest(p_tenant uuid,p_confirm boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare caller uuid:=auth.uid(); g pandora_connect.guest_access%rowtype;
begin
 if caller is null or coalesce(auth.jwt()->>'is_anonymous','false')<>'false' or p_confirm is distinct from true or not exists(select 1 from auth.users u where u.id=caller and u.email_confirmed_at is not null and not coalesce(u.is_anonymous,false) and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now())) then raise exception 'Verified account and explicit confirmation required' using errcode='42501';end if;
 select * into g from pandora_connect.guest_access where tenant_id=p_tenant and user_id=caller for update;
 if not found then raise exception 'Guest record unavailable' using errcode='42501';end if;
 delete from pandora_connect.guest_access where tenant_id=p_tenant and user_id=caller;
 if g.customer_id is not null then delete from pandora_connect.customers where tenant_id=p_tenant and id=g.customer_id;end if;
 return jsonb_build_object('erased',true);
end;
$$;
revoke all on function pandora_connect.erase_guest(uuid,boolean) from public,anon,authenticated,service_role;
grant execute on function pandora_connect.erase_guest(uuid,boolean) to authenticated;
create function public.pandora_connect_erase_guest(p_tenant uuid,p_confirm boolean) returns jsonb language sql security invoker set search_path='' as $$ select pandora_connect.erase_guest(p_tenant,p_confirm); $$;
revoke all on function public.pandora_connect_erase_guest(uuid,boolean) from public,anon,authenticated,service_role;
grant execute on function public.pandora_connect_erase_guest(uuid,boolean) to authenticated;
