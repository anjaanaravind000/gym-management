-- Prevent parallel sends from the scheduled worker and manual send endpoint.
-- A short lease expires automatically if a worker crashes; only the service role can claim/release it.
create table if not exists private.whatsapp_notification_claims(
 notification_id uuid primary key references public.notifications(id) on delete cascade,
 locked_until timestamptz not null,
 claimed_at timestamptz not null default now()
);
revoke all on table private.whatsapp_notification_claims from public,anon,authenticated,service_role;
grant select,insert,update,delete on table private.whatsapp_notification_claims to service_role;

drop function if exists public.get_whatsapp_credentials_internal(uuid);
create function public.get_whatsapp_credentials_internal(p_gym_id uuid)
returns table(phone_number_id text,access_token text,api_version text,enabled boolean,last_test_ok boolean)
language sql security definer
set search_path to 'private','pg_catalog'
as $$
 select c.phone_number_id,c.access_token,c.api_version,c.enabled,c.last_test_ok
 from private.whatsapp_connections c where c.gym_id=p_gym_id limit 1
$$;
revoke all on function public.get_whatsapp_credentials_internal(uuid) from public,anon,authenticated;
grant execute on function public.get_whatsapp_credentials_internal(uuid) to service_role;

create or replace function public.claim_whatsapp_notification_internal(p_notification_id uuid)
returns boolean language plpgsql security definer
set search_path to 'public','private','pg_catalog'
as $$
declare v_id uuid;
begin
 insert into private.whatsapp_notification_claims(notification_id,locked_until,claimed_at)
 select n.id,now()+interval '5 minutes',now()
 from public.notifications n
 where n.id=p_notification_id and n.channel='whatsapp'
   and n.status in('queued','failed') and coalesce(n.retry_count,0)<3
 on conflict(notification_id) do update
   set locked_until=excluded.locked_until,claimed_at=now()
   where private.whatsapp_notification_claims.locked_until<=now()
 returning notification_id into v_id;
 return v_id is not null;
end
$$;
revoke all on function public.claim_whatsapp_notification_internal(uuid) from public,anon,authenticated;
grant execute on function public.claim_whatsapp_notification_internal(uuid) to service_role;

create or replace function public.release_whatsapp_notification_internal(p_notification_id uuid)
returns void language sql security definer
set search_path to 'private','pg_catalog'
as $$
 delete from private.whatsapp_notification_claims where notification_id=p_notification_id
$$;
revoke all on function public.release_whatsapp_notification_internal(uuid) from public,anon,authenticated;
grant execute on function public.release_whatsapp_notification_internal(uuid) to service_role;
