create or replace function public.verify_whatsapp_webhook_token_internal(p_verify_token text)
returns boolean
language sql
security definer
set search_path to 'private','pg_catalog'
as $function$
 select exists(
   select 1 from private.whatsapp_connections
   where enabled=true and verify_token is not null and verify_token=p_verify_token
 )
$function$;
revoke all on function public.verify_whatsapp_webhook_token_internal(text) from public,anon,authenticated;
grant execute on function public.verify_whatsapp_webhook_token_internal(text) to service_role;