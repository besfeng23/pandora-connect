-- First-party loyalty: tenant-specific portal offers, one claim per eligible customer.
-- No payments, monetary balance, contact exports or external messages.
create table pandora_connect.loyalty_offers(
 tenant_id uuid not null references pandora_connect.tenants(id) on delete cascade,
 id uuid not null default gen_random_uuid(),
 title text not null check(length(trim(title)) between 1 and 80),
 terms text not null check(length(trim(terms)) between 1 and 400),
 min_visits integer not null check(min_visits between 1 and 30),
 state text not null default 'draft' check(state in ('draft','published','closed')),
 created_at timestamptz not null default now(),
 primary key(tenant_id,id)
);
create table pandora_connect.loyalty_claims(
 tenant_id uuid not null,offer_id uuid not null,customer_id uuid not null,
 code uuid not null default gen_random_uuid(),claimed_at timestamptz not null default now(),redeemed_at timestamptz,
 primary key(tenant_id,offer_id,customer_id),unique(tenant_id,code),
 foreign key(tenant_id,offer_id) references pandora_connect.loyalty_offers(tenant_id,id) on delete cascade,
 foreign key(tenant_id,customer_id) references pandora_connect.customers(tenant_id,id) on delete cascade
);
create index connect_claim_customer_idx on pandora_connect.loyalty_claims(tenant_id,customer_id);
alter table pandora_connect.loyalty_offers enable row level security;
alter table pandora_connect.loyalty_claims enable row level security;
revoke all on pandora_connect.loyalty_offers,pandora_connect.loyalty_claims from public,anon,authenticated,service_role;

create function pandora_connect.loyalty_eligible(p_tenant uuid,p_customer uuid,p_min integer) returns boolean language sql stable security invoker set search_path='' as $$
select exists(
 select 1 from pandora_connect.guest_access g
 join pandora_connect.customers c on c.tenant_id=g.tenant_id and c.id=g.customer_id
 join auth.users u on u.id=g.user_id
 cross join lateral(select granted,recorded_at from pandora_connect.consent_receipts r where r.tenant_id=g.tenant_id and r.customer_id=g.customer_id and r.purpose='analytics' order by r.recorded_at desc,r.id desc limit 1) a
 cross join lateral(select granted from pandora_connect.consent_receipts r where r.tenant_id=g.tenant_id and r.customer_id=g.customer_id and r.purpose='portal' order by r.recorded_at desc,r.id desc limit 1) p
 where g.tenant_id=p_tenant and g.customer_id=p_customer and g.enabled and g.adult_verified and c.adult_verified and u.email_confirmed_at is not null and not coalesce(u.is_anonymous,false) and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now()) and a.granted and p.granted
 and (select count(*) from pandora_connect.events e where e.tenant_id=p_tenant and e.customer_id=p_customer and e.kind='visit' and e.occurred_at>=greatest(a.recorded_at,now()-interval '30 days') and e.occurred_at<=clock_timestamp())>=p_min
);
$$;
revoke all on function pandora_connect.loyalty_eligible(uuid,uuid,integer) from public,anon,authenticated,service_role;

create function pandora_connect.loyalty(p_tenant uuid,p_action text,p_id uuid default null,p_title text default null,p_terms text default null,p_min integer default null,p_confirm boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); member_role text; g pandora_connect.guest_access%rowtype; o pandora_connect.loyalty_offers%rowtype; k pandora_connect.loyalty_claims%rowtype; result jsonb;
begin
 if actor is null or coalesce(auth.jwt()->>'is_anonymous','false')<>'false' or not exists(select 1 from auth.users u where u.id=actor and u.email_confirmed_at is not null and not coalesce(u.is_anonymous,false) and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now())) then raise exception 'Verified account required' using errcode='42501';end if;
 if p_action in ('guest_list','claim') then
  select * into g from pandora_connect.guest_access where tenant_id=p_tenant and user_id=actor for update;
  if not found or not g.enabled or not g.adult_verified or g.customer_id is null then return jsonb_build_object('offers','[]'::jsonb);end if;
  if p_action='claim' then
   select * into o from pandora_connect.loyalty_offers where tenant_id=p_tenant and id=p_id and state='published' for update;
   if not found or not pandora_connect.loyalty_eligible(p_tenant,g.customer_id,o.min_visits) then raise exception 'Offer unavailable or permission missing' using errcode='42501';end if;
   insert into pandora_connect.loyalty_claims(tenant_id,offer_id,customer_id) values(p_tenant,o.id,g.customer_id) on conflict(tenant_id,offer_id,customer_id) do nothing;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',o1.id,'title',o1.title,'terms',o1.terms,'minVisits',o1.min_visits,'code',k1.code,'redeemed',k1.redeemed_at is not null) order by o1.created_at desc,o1.id),'[]'::jsonb) into result
  from pandora_connect.loyalty_offers o1 left join pandora_connect.loyalty_claims k1 on k1.tenant_id=o1.tenant_id and k1.offer_id=o1.id and k1.customer_id=g.customer_id
  where o1.tenant_id=p_tenant and o1.state='published' and pandora_connect.loyalty_eligible(p_tenant,g.customer_id,o1.min_visits);
  return jsonb_build_object('offers',result);
 end if;
 select role into member_role from pandora_connect.memberships where tenant_id=p_tenant and user_id=actor;
 if member_role is null then raise exception 'Workspace access required' using errcode='42501';end if;
 if p_action='create' then
  if member_role<>'owner' or p_id is null then raise exception 'Owner required' using errcode='42501';end if;
  insert into pandora_connect.loyalty_offers(tenant_id,id,title,terms,min_visits) values(p_tenant,p_id,trim(p_title),trim(p_terms),p_min) on conflict(tenant_id,id) do nothing;
 elsif p_action in ('publish','close') then
  if member_role<>'owner' or p_confirm is distinct from true then raise exception 'Owner confirmation required' using errcode='42501';end if;
  update pandora_connect.loyalty_offers set state=case when p_action='publish' then 'published' else 'closed' end where tenant_id=p_tenant and id=p_id and ((p_action='publish' and state='draft') or (p_action='close' and state in ('draft','published')));
  if not found then raise exception 'Invalid offer state' using errcode='22023';end if;
 elsif p_action='redeem' then
  if member_role not in ('owner','operator') or p_confirm is distinct from true then raise exception 'Staff confirmation required' using errcode='42501';end if;
  select * into k from pandora_connect.loyalty_claims where tenant_id=p_tenant and code=p_id;
  if not found then raise exception 'Claim unavailable' using errcode='42501';end if;
  -- Lock in the same order as guest claim and consent changes.
  select * into g from pandora_connect.guest_access where tenant_id=p_tenant and customer_id=k.customer_id for update;
  if not found then raise exception 'Claim unavailable' using errcode='42501';end if;
  select * into o from pandora_connect.loyalty_offers where tenant_id=p_tenant and id=k.offer_id and state='published' for update;
  if not found or not pandora_connect.loyalty_eligible(p_tenant,k.customer_id,o.min_visits) then raise exception 'Claim no longer eligible' using errcode='42501';end if;
  update pandora_connect.loyalty_claims set redeemed_at=clock_timestamp() where tenant_id=p_tenant and code=p_id and redeemed_at is null and claimed_at>=now()-interval '7 days';
  if not found then raise exception 'Claim expired or redeemed' using errcode='22023';end if;
  return jsonb_build_object('redeemed',true,'title',o.title);
 elsif p_action is distinct from 'list' then raise exception 'Invalid operation' using errcode='22023';
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',o1.id,'title',o1.title,'terms',o1.terms,'minVisits',o1.min_visits,'state',o1.state,'claims',(select count(*) from pandora_connect.loyalty_claims c where c.tenant_id=p_tenant and c.offer_id=o1.id),'redemptions',(select count(*) from pandora_connect.loyalty_claims c where c.tenant_id=p_tenant and c.offer_id=o1.id and c.redeemed_at is not null)) order by o1.created_at desc,o1.id),'[]'::jsonb) into result from (select * from pandora_connect.loyalty_offers where tenant_id=p_tenant order by created_at desc,id limit 100) o1;
 return jsonb_build_object('offers',result);
end;
$$;
revoke all on function pandora_connect.loyalty(uuid,text,uuid,text,text,integer,boolean) from public,anon,authenticated,service_role;
grant execute on function pandora_connect.loyalty(uuid,text,uuid,text,text,integer,boolean) to authenticated;
create function public.pandora_connect_loyalty(p_tenant uuid,p_action text,p_id uuid default null,p_title text default null,p_terms text default null,p_min integer default null,p_confirm boolean default false) returns jsonb language sql security invoker set search_path='' as $$ select pandora_connect.loyalty(p_tenant,p_action,p_id,p_title,p_terms,p_min,p_confirm); $$;
revoke all on function public.pandora_connect_loyalty(uuid,text,uuid,text,text,integer,boolean) from public,anon,authenticated,service_role;
grant execute on function public.pandora_connect_loyalty(uuid,text,uuid,text,text,integer,boolean) to authenticated;
