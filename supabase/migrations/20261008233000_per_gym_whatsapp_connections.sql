create table if not exists private.whatsapp_connections(
 gym_id uuid primary key references public.gyms(id) on delete cascade,
 business_account_id text,
 phone_number_id text not null,
 access_token text not null,
 api_version text not null,
 verify_token text,
 enabled boolean not null default true,
 last_tested_at timestamptz,
 last_test_ok boolean,
 last_error text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
revoke all on table private.whatsapp_connections from public,anon,authenticated;

create or replace function public.get_whatsapp_connection(p_gym_id uuid)
returns table(connected boolean,business_account_id text,phone_number_id text,api_version text,enabled boolean,last_tested_at timestamptz,last_test_ok boolean,last_error text)
language plpgsql security definer set search_path to 'public','private','pg_catalog'
as $function$
begin
 if not private.is_admin(p_gym_id) then raise exception 'Unauthorized'; end if;
 return query
 select true,c.business_account_id,c.phone_number_id,c.api_version,c.enabled,c.last_tested_at,c.last_test_ok,c.last_error
 from private.whatsapp_connections c where c.gym_id=p_gym_id;
 if not found then
   return query select false,null::text,null::text,null::text,false,null::timestamptz,null::boolean,null::text;
 end if;
end
$function$;

create or replace function public.save_whatsapp_connection(
 p_gym_id uuid,p_business_account_id text,p_phone_number_id text,p_access_token text,p_api_version text,p_verify_token text default null
)
returns void
language plpgsql security definer set search_path to 'public','private','pg_catalog'
as $function$
declare existing_token text;
begin
 if not private.is_admin(p_gym_id) then raise exception 'Unauthorized'; end if;
 if nullif(trim(p_phone_number_id),'') is null then raise exception 'Phone Number ID is required'; end if;
 if nullif(trim(p_api_version),'') is null then raise exception 'Graph API version is required'; end if;
 select access_token into existing_token from private.whatsapp_connections where gym_id=p_gym_id;
 if existing_token is null and nullif(trim(coalesce(p_access_token,'')),'') is null then raise exception 'WhatsApp access token is required for the first connection'; end if;
 insert into private.whatsapp_connections(gym_id,business_account_id,phone_number_id,access_token,api_version,verify_token,enabled,last_test_ok,last_error,updated_at)
 values(p_gym_id,nullif(trim(p_business_account_id),''),trim(p_phone_number_id),coalesce(nullif(trim(p_access_token),''),existing_token),trim(p_api_version),nullif(trim(p_verify_token),''),true,null,null,now())
 on conflict(gym_id) do update set business_account_id=excluded.business_account_id,phone_number_id=excluded.phone_number_id,access_token=excluded.access_token,api_version=excluded.api_version,verify_token=excluded.verify_token,enabled=true,last_test_ok=null,last_error=null,updated_at=now();
end
$function$;

create or replace function public.disconnect_whatsapp_connection(p_gym_id uuid)
returns void
language plpgsql security definer set search_path to 'public','private','pg_catalog'
as $function$
begin
 if not private.is_admin(p_gym_id) then raise exception 'Unauthorized'; end if;
 delete from private.whatsapp_connections where gym_id=p_gym_id;
end
$function$;

revoke execute on function public.get_whatsapp_connection(uuid) from public,anon,authenticated;
grant execute on function public.get_whatsapp_connection(uuid) to anon;
revoke execute on function public.save_whatsapp_connection(uuid,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.save_whatsapp_connection(uuid,text,text,text,text,text) to anon;
revoke execute on function public.disconnect_whatsapp_connection(uuid) from public,anon,authenticated;
grant execute on function public.disconnect_whatsapp_connection(uuid) to anon;