-- Use wall-clock event bounds consistently with consent timestamps; deny inactive guest accounts.
create or replace function pandora_connect.record_first_party(p_tenant uuid,p_site uuid,p_customer uuid,p_event uuid,p_kind text,p_at timestamptz)
returns jsonb language plpgsql security definer set search_path='' as $$
declare caller uuid:=auth.uid(); allowed_at timestamptz; allowed boolean; g pandora_connect.guest_access%rowtype; old pandora_connect.events%rowtype;
begin
 if caller is null or coalesce(auth.jwt()->>'is_anonymous','false')='true' or not exists(select 1 from pandora_connect.event_writer_bindings b where b.user_id=caller and b.tenant_id=p_tenant and b.site_id=p_site) then raise exception 'Writer not authorized' using errcode='42501';end if;
 if p_event is null or p_customer is null or p_kind is null or p_kind not in ('visit','purchase','offer_redeemed') or p_at is null or p_at>clock_timestamp() or p_at<clock_timestamp()-interval '24 hours' then raise exception 'Invalid event' using errcode='22023';end if;
 -- Serialize event writes with opt-out; no events accepted after withdrawal.
 select * into g from pandora_connect.guest_access where tenant_id=p_tenant and customer_id=p_customer for update;
 if not found or not g.enabled or not g.adult_verified or not exists(select 1 from auth.users u where u.id=g.user_id and u.email_confirmed_at is not null and not coalesce(u.is_anonymous,false) and u.deleted_at is null and (u.banned_until is null or u.banned_until<=clock_timestamp())) then return jsonb_build_object('accepted',false);end if;
 if not exists(select 1 from pandora_connect.customers c where c.tenant_id=p_tenant and c.id=p_customer and c.adult_verified) then return jsonb_build_object('accepted',false);end if;
 select granted,recorded_at into allowed,allowed_at from pandora_connect.consent_receipts where tenant_id=p_tenant and customer_id=p_customer and purpose='analytics' order by recorded_at desc,id desc limit 1;
 if allowed is distinct from true or p_at<allowed_at then return jsonb_build_object('accepted',false);end if;
 insert into pandora_connect.events(tenant_id,customer_id,site_id,id,kind,occurred_at) values(p_tenant,p_customer,p_site,p_event,p_kind,p_at) on conflict(tenant_id,id) do nothing;
 if found then return jsonb_build_object('accepted',true,'duplicate',false);end if;
 select * into old from pandora_connect.events where tenant_id=p_tenant and id=p_event;
 if old.customer_id is distinct from p_customer or old.site_id is distinct from p_site or old.kind is distinct from p_kind or old.occurred_at is distinct from p_at then raise exception 'Event ID conflict' using errcode='22023';end if;
 return jsonb_build_object('accepted',true,'duplicate',true);
end;
$$;
