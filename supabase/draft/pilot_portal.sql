-- Invitation-only pilot; no self-assigned owner, no provider delivery.
create table pandora_connect.guest_invitations (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references pandora_connect.tenants(id) on delete cascade,
 guest_user_id uuid not null,
 issued_by uuid not null,
 adult_attested_at timestamptz not null default now(),
 expires_at timestamptz not null default (now()+interval '7 days'),
 accepted_at timestamptz,
 customer_id uuid,
 unique(tenant_id,guest_user_id),
 foreign key(tenant_id,customer_id) references pandora_connect.customers(tenant_id,id) on delete cascade
);
create index connect_invite_guest_idx on pandora_connect.guest_invitations(guest_user_id);
create table pandora_connect.campaign_drafts (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references pandora_connect.tenants(id) on delete cascade,
 name text not null check(char_length(name) between 1 and 80),
 channel text not null check(channel in ('email','sms','ads','portal')),
 segment text not null check(segment in ('frequent_visitor','returning_offer_candidate','existing_customer')),
 created_by uuid not null,
 created_at timestamptz not null default now()
);
create index connect_campaign_tenant_idx on pandora_connect.campaign_drafts(tenant_id,created_at desc);
alter table pandora_connect.guest_invitations enable row level security;
alter table pandora_connect.campaign_drafts enable row level security;
revoke all on pandora_connect.guest_invitations,pandora_connect.campaign_drafts from public,anon,authenticated,service_role;
-- Private privileged implementation: needs to mutate protected records atomically
-- without granting clients unrestricted INSERT/UPDATE/DELETE. All actions check identity.
create function pandora_connect.portal_action(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); tid uuid; sid uuid; iid uuid; cid uuid; target_user uuid; eid uuid; 
  role_name text; title_text text; purpose_text text; kind_text text; granted_value boolean;
  inv pandora_connect.guest_invitations%rowtype; old_event pandora_connect.events%rowtype; last_grant boolean;
begin
 if actor is null or coalesce(auth.jwt()->>'is_anonymous','false')<>'false' then
   raise exception 'Authentication required' using errcode='42501';
 end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or pg_column_size(p_data)>8192 then raise exception 'Invalid request' using errcode='22023';end if;
 if p_action in ('guest_status','guest_accept','guest_consent','guest_erase') then
   if not exists(select 1 from auth.users u where u.id=actor and u.email_confirmed_at is not null and not coalesce(u.is_anonymous,false) and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now())) then
     raise exception 'Verified account required' using errcode='42501';
   end if;
   if p_action='guest_status' then
     return coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'business',t.name,'accepted',i.accepted_at is not null,'customerId',i.customer_id,'analytics',coalesce((select r.granted from pandora_connect.consent_receipts r where r.tenant_id=i.tenant_id and r.customer_id=i.customer_id and r.purpose='analytics' order by r.recorded_at desc,r.id desc limit 1),false),'email',coalesce((select r.granted from pandora_connect.consent_receipts r where r.tenant_id=i.tenant_id and r.customer_id=i.customer_id and r.purpose='email' order by r.recorded_at desc,r.id desc limit 1),false),'portal',coalesce((select r.granted from pandora_connect.consent_receipts r where r.tenant_id=i.tenant_id and r.customer_id=i.customer_id and r.purpose='portal' order by r.recorded_at desc,r.id desc limit 1),false)) order by t.name) from pandora_connect.guest_invitations i join pandora_connect.tenants t on t.id=i.tenant_id where i.guest_user_id=actor and (i.accepted_at is not null or i.expires_at>now())),'[]'::jsonb);
   end if;
   iid:=(p_data->>'invitationId')::uuid;
   select * into inv from pandora_connect.guest_invitations i where i.id=iid and i.guest_user_id=actor and (i.accepted_at is not null or i.expires_at>now()) for update;
   if not found then raise exception 'Invitation unavailable' using errcode='42501';end if;
   if p_action='guest_accept' then
     if p_data->'accept' is distinct from 'true'::jsonb or p_data->>'noticeVersion' is distinct from 'connect-pilot-v1' then raise exception 'Explicit enrollment required' using errcode='22023';end if;
     if inv.customer_id is not null then return jsonb_build_object('customerId',inv.customer_id);end if;
     insert into pandora_connect.customers(tenant_id,adult_verified) values(inv.tenant_id,true) returning id into cid;
     update pandora_connect.guest_invitations set customer_id=cid,accepted_at=now() where id=inv.id;
     return jsonb_build_object('customerId',cid);
   end if;
   if p_action='guest_erase' then
     delete from pandora_connect.guest_invitations where id=inv.id;
     if inv.customer_id is not null then delete from pandora_connect.customers where tenant_id=inv.tenant_id and id=inv.customer_id;end if;
     return jsonb_build_object('erased',true);
   end if;
   if inv.customer_id is null then raise exception 'Enrollment required' using errcode='42501';end if;
   purpose_text:=p_data->>'purpose';
   if purpose_text is null or purpose_text not in ('analytics','email','portal') or jsonb_typeof(p_data->'granted') is distinct from 'boolean' or p_data->>'noticeVersion' is distinct from 'connect-pilot-v1' then raise exception 'Invalid permission request' using errcode='22023';end if;
   granted_value:=(p_data->>'granted')::boolean;
   perform 1 from pandora_connect.customers where tenant_id=inv.tenant_id and id=inv.customer_id for update;
   insert into pandora_connect.consent_receipts(tenant_id,customer_id,purpose,granted,notice_version,evidence_ref,recorded_at)
   values(inv.tenant_id,inv.customer_id,purpose_text,granted_value,'connect-pilot-v1','authenticated-guest:'||inv.id::text,clock_timestamp());
   if purpose_text='analytics' and not granted_value then delete from pandora_connect.events where tenant_id=inv.tenant_id and customer_id=inv.customer_id;end if;
   return jsonb_build_object('purpose',purpose_text,'granted',granted_value);
 end if;
 tid:=(p_data->>'tenantId')::uuid;
 select m.role into role_name from pandora_connect.memberships m where m.tenant_id=tid and m.user_id=actor;
 if role_name is null or role_name not in ('owner','operator') then raise exception 'Workspace access denied' using errcode='42501';end if;
 if p_action='owner_state' then
   return jsonb_build_object(
     'sites',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name) order by s.name) from pandora_connect.sites s where s.tenant_id=tid),'[]'::jsonb),
     'invitations',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'customerId',i.customer_id,'status',case when i.accepted_at is not null then 'accepted' when i.expires_at<=now() then 'expired' else 'pending' end) order by i.adult_attested_at desc) from (select * from pandora_connect.guest_invitations where tenant_id=tid order by adult_attested_at desc limit 100) i),'[]'::jsonb),
     'campaigns',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'channel',c.channel,'segment',c.segment,'status','draft') order by c.created_at desc) from (select * from pandora_connect.campaign_drafts where tenant_id=tid order by created_at desc limit 100) c),'[]'::jsonb));
 elsif p_action='site_create' then
   if role_name<>'owner' then raise exception 'Owner required' using errcode='42501';end if;
   title_text:=btrim(p_data->>'name');if title_text is null or char_length(title_text) not between 1 and 80 then raise exception 'Invalid site name' using errcode='22023';end if;
   insert into pandora_connect.sites(tenant_id,name) values(tid,title_text) returning id into sid;
   return jsonb_build_object('id',sid);
 elsif p_action='guest_invite' then
   if role_name<>'owner' or p_data->'adultVerified' is distinct from 'true'::jsonb then raise exception 'Owner and adult verification required' using errcode='42501';end if;
   target_user:=(p_data->>'userId')::uuid;
   if not exists(select 1 from auth.users u where u.id=target_user and u.email_confirmed_at is not null and not coalesce(u.is_anonymous,false) and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now())) then raise exception 'Verified account unavailable' using errcode='42501';end if;
   insert into pandora_connect.guest_invitations(tenant_id,guest_user_id,issued_by) values(tid,target_user,actor)
   on conflict(tenant_id,guest_user_id) do update set issued_by=actor,adult_attested_at=now(),expires_at=now()+interval '7 days' where pandora_connect.guest_invitations.accepted_at is null returning id into iid;
   if iid is null then raise exception 'Guest already enrolled' using errcode='22023';end if;
   return jsonb_build_object('id',iid);
 elsif p_action='event_record' then
   cid:=(p_data->>'customerId')::uuid;sid:=(p_data->>'siteId')::uuid;eid:=(p_data->>'eventId')::uuid;kind_text:=p_data->>'kind';
   if eid is null or kind_text is null or kind_text not in ('visit','purchase','offer_redeemed') then raise exception 'Invalid event' using errcode='22023';end if;
   if not exists(select 1 from pandora_connect.sites s where s.tenant_id=tid and s.id=sid) then raise exception 'Site unavailable' using errcode='42501';end if;
   perform 1 from pandora_connect.customers c where c.tenant_id=tid and c.id=cid and c.adult_verified for update;
   if not found then raise exception 'Customer unavailable' using errcode='42501';end if;
   select r.granted into last_grant from pandora_connect.consent_receipts r where r.tenant_id=tid and r.customer_id=cid and r.purpose='analytics' order by r.recorded_at desc,r.id desc limit 1;
   if last_grant is distinct from true then raise exception 'Analytics consent required' using errcode='42501';end if;
   insert into pandora_connect.events(tenant_id,customer_id,site_id,id,kind,occurred_at) values(tid,cid,sid,eid,kind_text,clock_timestamp()) on conflict(tenant_id,id) do nothing;
   if not found then select * into old_event from pandora_connect.events where tenant_id=tid and id=eid;if old_event.customer_id<>cid or old_event.site_id<>sid or old_event.kind<>kind_text then raise exception 'Event ID conflict' using errcode='22023';end if;return jsonb_build_object('accepted',true,'duplicate',true);end if;
   return jsonb_build_object('accepted',true,'duplicate',false);
 elsif p_action='campaign_save' then
   title_text:=btrim(p_data->>'name');
   if title_text is null or char_length(title_text) not between 1 and 80 then raise exception 'Invalid campaign name' using errcode='22023';end if;
   insert into pandora_connect.campaign_drafts(tenant_id,name,channel,segment,created_by) values(tid,title_text,p_data->>'channel',p_data->>'segment',actor) returning id into iid;
   return jsonb_build_object('id',iid,'status','draft');
 else raise exception 'Unknown action' using errcode='22023';end if;
end;
$$;
revoke all on function pandora_connect.portal_action(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function pandora_connect.portal_action(text,jsonb) to authenticated;
create function public.pandora_connect_portal(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$ select pandora_connect.portal_action(p_action,p_data); $$;
revoke all on function public.pandora_connect_portal(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.pandora_connect_portal(text,jsonb) to authenticated;
