-- Invite-only guest consent and internal campaign drafts; delivery remains impossible.
create table pandora_connect.guest_access (
 tenant_id uuid not null references pandora_connect.tenants(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 customer_id uuid,
 enabled boolean not null default false,
 adult_verified boolean not null default false,
 created_at timestamptz not null default now(),
 primary key(tenant_id,user_id),
 unique(tenant_id,customer_id),
 foreign key(tenant_id,customer_id) references pandora_connect.customers(tenant_id,id)
);
alter table pandora_connect.guest_access enable row level security;
revoke all on pandora_connect.guest_access from public,anon,authenticated,service_role;
create index connect_guest_user_idx on pandora_connect.guest_access(user_id,tenant_id);

-- Narrow private helper: verifies identity, locks only the caller's invitation,
-- creates a pseudonymous customer only after an explicit opt-in, and records
-- choices separately. No contact addresses, device identifiers, events or ads.
create function pandora_connect.guest_preferences(p_tenant uuid,p_analytics boolean,p_portal boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare caller uuid:=auth.uid(); g pandora_connect.guest_access%rowtype; cid uuid; purpose_name text; choice boolean; last_choice boolean;
begin
 if caller is null or coalesce(auth.jwt()->>'is_anonymous','false')='true' or not exists(select 1 from auth.users u where u.id=caller and u.email_confirmed_at is not null and not coalesce(u.is_anonymous,false)) then raise exception 'Verified account required' using errcode='42501'; end if;
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
 return coalesce((select jsonb_agg(jsonb_build_object('tenantId',a.tenant_id,'name',t.name,'eligible',a.enabled and a.adult_verified,'enrolled',a.customer_id is not null,'analytics',coalesce((select r.granted from pandora_connect.consent_receipts r where r.tenant_id=a.tenant_id and r.customer_id=a.customer_id and r.purpose='analytics' order by r.recorded_at desc,r.id desc limit 1),false),'portal',coalesce((select r.granted from pandora_connect.consent_receipts r where r.tenant_id=a.tenant_id and r.customer_id=a.customer_id and r.purpose='portal' order by r.recorded_at desc,r.id desc limit 1),false)) order by t.name,t.id) from pandora_connect.guest_access a join pandora_connect.tenants t on t.id=a.tenant_id where a.user_id=caller),'[]'::jsonb);
end;
$$;
revoke all on function pandora_connect.guest_preferences(uuid,boolean,boolean) from public,anon,authenticated,service_role;
grant execute on function pandora_connect.guest_preferences(uuid,boolean,boolean) to authenticated;
create function public.pandora_connect_guest_preferences(p_tenant uuid default null,p_analytics boolean default null,p_portal boolean default null) returns jsonb language sql security invoker set search_path='' as $$ select pandora_connect.guest_preferences(p_tenant,p_analytics,p_portal); $$;
revoke all on function public.pandora_connect_guest_preferences(uuid,boolean,boolean) from public,anon,authenticated,service_role;
grant execute on function public.pandora_connect_guest_preferences(uuid,boolean,boolean) to authenticated;

create table pandora_connect.campaign_drafts(
 tenant_id uuid not null references pandora_connect.tenants(id) on delete cascade,
 id uuid not null default gen_random_uuid(),
 title text not null check (length(trim(title)) between 1 and 100),
 objective text not null check (objective in ('welcome','loyalty','winback')),
 channel text not null check (channel in ('email','sms','ads','portal')),
 status text not null default 'draft' check (status in ('draft','archived')),
 created_at timestamptz not null default now(),
 primary key(tenant_id,id)
);
alter table pandora_connect.campaign_drafts enable row level security;
revoke all on pandora_connect.campaign_drafts from public,anon,authenticated,service_role;
grant select on pandora_connect.campaign_drafts to authenticated;
grant insert(tenant_id,id,title,objective,channel) on pandora_connect.campaign_drafts to authenticated;
grant update(status) on pandora_connect.campaign_drafts to authenticated;
create policy connect_campaign_read on pandora_connect.campaign_drafts for select to authenticated using(exists(select 1 from pandora_connect.memberships m where m.tenant_id=campaign_drafts.tenant_id));
create policy connect_campaign_insert on pandora_connect.campaign_drafts for insert to authenticated with check(status='draft' and exists(select 1 from pandora_connect.memberships m where m.tenant_id=campaign_drafts.tenant_id and m.role in ('owner','operator')));
create policy connect_campaign_archive on pandora_connect.campaign_drafts for update to authenticated using(status='draft' and exists(select 1 from pandora_connect.memberships m where m.tenant_id=campaign_drafts.tenant_id and m.role in ('owner','operator'))) with check(status='archived' and exists(select 1 from pandora_connect.memberships m where m.tenant_id=campaign_drafts.tenant_id and m.role in ('owner','operator')));
create function public.pandora_connect_campaigns(p_tenant uuid,p_action text default 'list',p_id uuid default null,p_title text default null,p_objective text default null,p_channel text default null) returns jsonb language plpgsql security invoker set search_path='' as $$
begin
 if not exists(select 1 from pandora_connect.memberships m where m.tenant_id=p_tenant and m.user_id=(select auth.uid())) then raise exception 'Workspace access required' using errcode='42501';end if;
 if p_action='create' then
  if p_id is null then raise exception 'Draft ID required' using errcode='22023';end if;
  insert into pandora_connect.campaign_drafts(tenant_id,id,title,objective,channel) values(p_tenant,p_id,trim(p_title),p_objective,p_channel) on conflict(tenant_id,id) do nothing;
 elsif p_action='archive' then
  update pandora_connect.campaign_drafts set status='archived' where tenant_id=p_tenant and id=p_id and status='draft';
  if not found then raise exception 'Draft not available for archive' using errcode='42501';end if;
 elsif p_action<>'list' or p_action is null then raise exception 'Invalid action' using errcode='22023';
 end if;
 return coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at desc,d.id) from (select id,title,objective,channel,status,created_at from pandora_connect.campaign_drafts where tenant_id=p_tenant and status='draft' order by created_at desc,id limit 100) d),'[]'::jsonb);
end;
$$;
revoke all on function public.pandora_connect_campaigns(uuid,text,uuid,text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.pandora_connect_campaigns(uuid,text,uuid,text,text,text) to authenticated;
