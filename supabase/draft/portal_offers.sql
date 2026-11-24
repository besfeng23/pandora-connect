-- Internal portal offers only. No external delivery, exports, spending or network identification.
create table pandora_connect.portal_offers (
 tenant_id uuid not null,
 campaign_id uuid not null,
 headline text not null check(char_length(headline) between 1 and 100),
 message text not null check(char_length(message) between 1 and 500),
 starts_at timestamptz not null default now(),
 ends_at timestamptz not null,
 approved_by uuid not null,
 revoked_at timestamptz,
 primary key(tenant_id,campaign_id),
 foreign key(tenant_id,campaign_id) references pandora_connect.campaign_drafts(tenant_id,id) on delete cascade,
 check(ends_at>starts_at and ends_at<=starts_at+interval '30 days')
);
alter table pandora_connect.portal_offers enable row level security;
revoke all on pandora_connect.portal_offers from public,anon,authenticated,service_role;
create function pandora_connect.portal_offer_action(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); tid uuid; cid uuid; d pandora_connect.campaign_drafts%rowtype; title_text text; body_text text; duration integer; 
begin
 if actor is null or coalesce(auth.jwt()->>'is_anonymous','false')<>'false' or not exists(select 1 from auth.users u where u.id=actor and u.email_confirmed_at is not null and not coalesce(u.is_anonymous,false) and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now())) then raise exception 'Verified account required' using errcode='42501';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or pg_column_size(p_data)>8192 then raise exception 'Invalid request' using errcode='22023';end if;
 if p_action='guest_list' then
  return coalesce((with eligible as (
   select a.tenant_id,a.customer_id,t.name,r.recorded_at as since
   from pandora_connect.guest_access a join pandora_connect.customers c on c.tenant_id=a.tenant_id and c.id=a.customer_id join pandora_connect.tenants t on t.id=a.tenant_id
   cross join lateral(select granted,recorded_at from pandora_connect.consent_receipts where tenant_id=a.tenant_id and customer_id=a.customer_id and purpose='analytics' order by recorded_at desc,id desc limit 1) r
   cross join lateral(select granted from pandora_connect.consent_receipts where tenant_id=a.tenant_id and customer_id=a.customer_id and purpose='portal' order by recorded_at desc,id desc limit 1) p
   where a.user_id=actor and a.enabled and a.adult_verified and c.adult_verified and r.granted and p.granted
  ),counts as (
   select a.tenant_id,a.name,count(e.id) filter(where e.occurred_at>=now()-interval '30 days') recent,count(e.id) total
   from eligible a left join pandora_connect.events e on e.tenant_id=a.tenant_id and e.customer_id=a.customer_id and e.kind='visit' and e.occurred_at>=greatest(a.since,now()-interval '90 days') and e.occurred_at<=now()
   group by a.tenant_id,a.name
  ) select jsonb_agg(jsonb_build_object('business',q.name,'headline',q.headline,'message',q.message,'endsAt',q.ends_at) order by q.ends_at) from (
   select a.name,o.headline,o.message,o.ends_at from counts a join pandora_connect.portal_offers o on o.tenant_id=a.tenant_id
   join pandora_connect.campaign_drafts d on d.tenant_id=o.tenant_id and d.id=o.campaign_id
   where o.revoked_at is null and o.starts_at<=now() and o.ends_at>now() and d.channel='portal' and d.status='draft'
   and ((d.objective='welcome' and a.recent=1) or (d.objective='loyalty' and a.recent>=3) or (d.objective='winback' and a.recent=0 and a.total>0))
   order by o.ends_at limit 50
  ) q),'[]'::jsonb);
 end if;
 tid:=(p_data->>'tenantId')::uuid;
 if not exists(select 1 from pandora_connect.memberships m where m.tenant_id=tid and m.user_id=actor and m.role='owner') then raise exception 'Owner required' using errcode='42501';end if;
 if p_action='owner_list' then
  return coalesce((select jsonb_agg(jsonb_build_object('campaignId',o.campaign_id,'headline',o.headline,'endsAt',o.ends_at,'status',case when o.revoked_at is not null or d.status<>'draft' then 'stopped' when o.ends_at<=now() then 'expired' else 'active' end) order by o.starts_at desc) from (select * from pandora_connect.portal_offers where tenant_id=tid order by starts_at desc limit 100) o join pandora_connect.campaign_drafts d on d.tenant_id=o.tenant_id and d.id=o.campaign_id),'[]'::jsonb);
 end if;
 cid:=(p_data->>'campaignId')::uuid;
 if p_action='stop' then
  update pandora_connect.portal_offers set revoked_at=coalesce(revoked_at,clock_timestamp()) where tenant_id=tid and campaign_id=cid;
  if not found then raise exception 'Offer unavailable' using errcode='42501';end if;
  return jsonb_build_object('stopped',true);
 end if;
 if p_action is distinct from 'publish' or p_data->'confirm' is distinct from 'true'::jsonb then raise exception 'Explicit owner approval required' using errcode='22023';end if;
 select * into d from pandora_connect.campaign_drafts where tenant_id=tid and id=cid and channel='portal' and status='draft' for update;
 if not found then raise exception 'Portal draft required' using errcode='42501';end if;
 title_text:=btrim(p_data->>'headline');body_text:=btrim(p_data->>'message');duration:=(p_data->>'days')::integer;
 if title_text is null or char_length(title_text) not between 1 and 100 or body_text is null or char_length(body_text) not between 1 and 500 or duration is null or duration not between 1 and 30 then raise exception 'Invalid offer' using errcode='22023';end if;
 insert into pandora_connect.portal_offers(tenant_id,campaign_id,headline,message,starts_at,ends_at,approved_by) values(tid,cid,title_text,body_text,now(),now()+duration*interval '1 day',actor)
 on conflict(tenant_id,campaign_id) do nothing;
 if not found then raise exception 'Offer already exists; create a new draft for another publication' using errcode='22023';end if;
 return jsonb_build_object('published',true);
end;
$$;
revoke all on function pandora_connect.portal_offer_action(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function pandora_connect.portal_offer_action(text,jsonb) to authenticated;
create function public.pandora_connect_portal_offer(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$ select pandora_connect.portal_offer_action(p_action,p_data); $$;
revoke all on function public.pandora_connect_portal_offer(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.pandora_connect_portal_offer(text,jsonb) to authenticated;
