create or replace function public.get_whatsapp_credentials_internal(p_gym_id uuid)
returns table(phone_number_id text,access_token text,api_version text,enabled boolean)
language sql
security definer
set search_path to 'private','pg_catalog'
as $function$
 select c.phone_number_id,c.access_token,c.api_version,c.enabled
 from private.whatsapp_connections c
 where c.gym_id=p_gym_id
 limit 1
$function$;
revoke all on function public.get_whatsapp_credentials_internal(uuid) from public,anon,authenticated;
grant execute on function public.get_whatsapp_credentials_internal(uuid) to service_role;

create or replace function public.record_whatsapp_test_internal(p_gym_id uuid,p_ok boolean,p_error text default null)
returns void
language plpgsql
security definer
set search_path to 'public','private','pg_catalog'
as $function$
begin
 update private.whatsapp_connections
 set last_tested_at=now(),last_test_ok=p_ok,last_error=case when p_ok then null else left(p_error,4000) end,updated_at=now()
 where gym_id=p_gym_id;
 if not found then raise exception 'WhatsApp connection has not been saved'; end if;
end
$function$;
revoke all on function public.record_whatsapp_test_internal(uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.record_whatsapp_test_internal(uuid,boolean,text) to service_role;