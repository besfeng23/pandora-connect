-- Read-only, permission-qualified portal cohort preview. No recipient identifiers, exports or sends.
create function pandora_connect.audience_preview(p_tenant uuid,p_campaign uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=auth.uid(); d pandora_connect.campaign_drafts%rowtype; n bigint;
begin
 if actor is null or coalesce(auth.jwt()->>'is_anonymous','false')<>'false' or not exists(select 1 from pandora_connect.memberships m where m.tenant_id=p_tenant and m.user_id=actor and m.role in ('owner','operator','analyst')) then raise exception 'Workspace access required' using errcode='42501';end if;
 select * into d from pandora_connect.campaign_drafts where tenant_id=p_tenant and id=p_campaign and status='draft';
 if not found then raise exception 'Draft unavailable' using errcode='42501';end if;
 if d.channel<>'portal' then return jsonb_build_object('eligibleCount',null,'status','blocked','reason','External channel permissions and provider approval are not enabled');end if;
 with allowed as (
 select a.customer_id,r.recorded_at as since from pandora_connect.guest_access a join pandora_connect.customers c on c.tenant_id=a.tenant_id and c.id=a.customer_id join auth.users u on u.id=a.user_id
 cross join lateral(select granted,recorded_at from pandora_connect.consent_receipts where tenant_id=a.tenant_id and customer_id=a.customer_id and purpose='analytics' order by recorded_at desc,id desc limit 1) r
 cross join lateral(select granted from pandora_connect.consent_receipts where tenant_id=a.tenant_id and customer_id=a.customer_id and purpose='portal' order by recorded_at desc,id desc limit 1) p
 where a.tenant_id=p_tenant and a.enabled and a.adult_verified and c.adult_verified and u.email_confirmed_at is not null and not coalesce(u.is_anonymous,false) and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now()) and r.granted and p.granted
 ), counts as (
 select a.customer_id,count(e.id) filter(where e.occurred_at>=now()-interval '30 days') recent,count(e.id) total from allowed a left join pandora_connect.events e on e.tenant_id=p_tenant and e.customer_id=a.customer_id and e.kind='visit' and e.occurred_at>=greatest(a.since,now()-interval '90 days') and e.occurred_at<=now() group by a.customer_id
 )
 select count(*) into n from counts where (d.objective='welcome' and recent=1) or (d.objective='loyalty' and recent>=3) or (d.objective='winback' and recent=0 and total>0);
 return jsonb_build_object('eligibleCount',n,'status','preview_only','reason','Current consent-qualified portal cohort; delivery remains disabled');
end;
$$;
revoke all on function pandora_connect.audience_preview(uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function pandora_connect.audience_preview(uuid,uuid) to authenticated;
create function public.pandora_connect_audience_preview(p_tenant uuid,p_campaign uuid) returns jsonb language sql stable security invoker set search_path='' as $$ select pandora_connect.audience_preview(p_tenant,p_campaign); $$;
revoke all on function public.pandora_connect_audience_preview(uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.pandora_connect_audience_preview(uuid,uuid) to authenticated;
