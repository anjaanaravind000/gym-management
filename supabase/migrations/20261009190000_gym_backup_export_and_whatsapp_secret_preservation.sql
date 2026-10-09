-- Admin-only business-data export for off-site backups.
-- Deliberately excludes auth hashes/sessions, integration credentials, and file binaries.
alter table private.whatsapp_connections
  add column if not exists meta_app_secret text;

create or replace function public.save_whatsapp_connection(
 p_gym_id uuid,
 p_business_account_id text,
 p_phone_number_id text,
 p_access_token text,
 p_api_version text,
 p_verify_token text default null,
 p_meta_app_secret text default null
)
returns void
language plpgsql
security definer
set search_path to 'public','private','pg_catalog'
as $function$
declare
 existing_token text;
 existing_app_secret text;
 existing_verify_token text;
begin
 if not private.is_admin(p_gym_id) then raise exception 'Unauthorized'; end if;
 if nullif(trim(p_phone_number_id),'') is null then raise exception 'Phone Number ID is required'; end if;
 if nullif(trim(p_api_version),'') is null or trim(p_api_version) !~ '^v[0-9]+\.[0-9]+$' then
   raise exception 'Use a valid Meta Graph API version such as vXX.X';
 end if;
 select access_token,meta_app_secret,verify_token
 into existing_token,existing_app_secret,existing_verify_token
 from private.whatsapp_connections where gym_id=p_gym_id;
 if existing_token is null and nullif(trim(coalesce(p_access_token,'')),'') is null then
   raise exception 'WhatsApp access token is required for the first connection';
 end if;
 if existing_app_secret is null and nullif(trim(coalesce(p_meta_app_secret,'')),'') is null then
   raise exception 'Meta App Secret is required for webhook security';
 end if;
 if existing_verify_token is null and nullif(trim(coalesce(p_verify_token,'')),'') is null then
   raise exception 'Webhook verify token is required for the first connection';
 end if;
 insert into private.whatsapp_connections(
   gym_id,business_account_id,phone_number_id,access_token,api_version,verify_token,meta_app_secret,enabled,last_test_ok,last_error,updated_at
 )
 values(
   p_gym_id,nullif(trim(p_business_account_id),''),trim(p_phone_number_id),
   coalesce(nullif(trim(p_access_token),''),existing_token),trim(p_api_version),
   coalesce(nullif(trim(p_verify_token),''),existing_verify_token),
   coalesce(nullif(trim(p_meta_app_secret),''),existing_app_secret),
   true,null,null,now()
 )
 on conflict(gym_id) do update set
   business_account_id=excluded.business_account_id,
   phone_number_id=excluded.phone_number_id,
   access_token=excluded.access_token,
   api_version=excluded.api_version,
   verify_token=excluded.verify_token,
   meta_app_secret=excluded.meta_app_secret,
   enabled=true,last_test_ok=null,last_error=null,updated_at=now();
end
$function$;

create or replace function public.export_gym_backup(p_gym_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_catalog'
as $function$
declare v_backup jsonb;v_gym_name text;
begin
 if not private.is_admin(p_gym_id) then raise exception 'Only a gym admin can export a backup'; end if;
 select name into v_gym_name from public.gyms where id=p_gym_id;
 if not found then raise exception 'Gym not found'; end if;
 select jsonb_build_object(
  'format','gym-management-backup',
  'schema_version',1,
  'exported_at',clock_timestamp(),
  'gym_id',p_gym_id,
  'gym_name',v_gym_name,
  'data',jsonb_build_object(
    'gyms',coalesce((select jsonb_agg(to_jsonb(x)) from public.gyms x where x.id=p_gym_id),'[]'::jsonb),
    'gym_settings',coalesce((select jsonb_agg(to_jsonb(x)) from public.gym_settings x where x.gym_id=p_gym_id),'[]'::jsonb),
    'payment_method_settings',coalesce((select jsonb_agg(to_jsonb(x)) from public.payment_method_settings x where x.gym_id=p_gym_id),'[]'::jsonb),
    'users',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'gym_id',x.gym_id,'name',x.name,'email',x.email,'phone',x.phone,'role',x.role,'status',x.status,'created_at',x.created_at,'updated_at',x.updated_at)) from public.users x where x.gym_id=p_gym_id),'[]'::jsonb),
    'user_permissions',coalesce((select jsonb_agg(to_jsonb(x)) from public.user_permissions x join public.users u on u.id=x.user_id where u.gym_id=p_gym_id),'[]'::jsonb),
    'login_accounts',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'username',x.username,'display_name',x.display_name,'role',x.role,'status',x.status,'gym_id',x.gym_id,'email',x.email,'phone',x.phone,'created_at',x.created_at,'updated_at',x.updated_at)) from public.login_accounts x where x.gym_id=p_gym_id),'[]'::jsonb),
    'membership_packages',coalesce((select jsonb_agg(to_jsonb(x)) from public.membership_packages x where x.gym_id=p_gym_id),'[]'::jsonb),
    'members',coalesce((select jsonb_agg(to_jsonb(x)) from public.members x where x.gym_id=p_gym_id),'[]'::jsonb),
    'memberships',coalesce((select jsonb_agg(to_jsonb(x)) from public.memberships x where x.gym_id=p_gym_id),'[]'::jsonb),
    'membership_freezes',coalesce((select jsonb_agg(to_jsonb(x)) from public.membership_freezes x where x.gym_id=p_gym_id),'[]'::jsonb),
    'membership_cancellations',coalesce((select jsonb_agg(to_jsonb(x)) from public.membership_cancellations x where x.gym_id=p_gym_id),'[]'::jsonb),
    'payments',coalesce((select jsonb_agg(to_jsonb(x)) from public.payments x where x.gym_id=p_gym_id),'[]'::jsonb),
    'refunds',coalesce((select jsonb_agg(to_jsonb(x)) from public.refunds x where x.gym_id=p_gym_id),'[]'::jsonb),
    'attendance',coalesce((select jsonb_agg(to_jsonb(x)) from public.attendance x where x.gym_id=p_gym_id),'[]'::jsonb),
    'expenses',coalesce((select jsonb_agg(to_jsonb(x)) from public.expenses x where x.gym_id=p_gym_id),'[]'::jsonb),
    'leads',coalesce((select jsonb_agg(to_jsonb(x)) from public.leads x where x.gym_id=p_gym_id),'[]'::jsonb),
    'gym_classes',coalesce((select jsonb_agg(to_jsonb(x)) from public.gym_classes x where x.gym_id=p_gym_id),'[]'::jsonb),
    'class_sessions',coalesce((select jsonb_agg(to_jsonb(x)) from public.class_sessions x where x.gym_id=p_gym_id),'[]'::jsonb),
    'class_bookings',coalesce((select jsonb_agg(to_jsonb(x)) from public.class_bookings x where x.gym_id=p_gym_id),'[]'::jsonb),
    'notification_templates',coalesce((select jsonb_agg(to_jsonb(x)) from public.notification_templates x where x.gym_id=p_gym_id),'[]'::jsonb),
    'notifications',coalesce((select jsonb_agg(to_jsonb(x)) from public.notifications x where x.gym_id=p_gym_id),'[]'::jsonb),
    'notification_logs',coalesce((select jsonb_agg(to_jsonb(l)) from public.notification_logs l join public.notifications n on n.id=l.notification_id where n.gym_id=p_gym_id),'[]'::jsonb),
    'audit_logs',coalesce((select jsonb_agg(to_jsonb(x)) from public.audit_logs x where x.gym_id=p_gym_id),'[]'::jsonb)
  ),
  'excluded_for_security_or_file_size',jsonb_build_array(
    'Password hashes and login sessions',
    'WhatsApp access token, Meta App Secret, webhook verify token, and worker secrets',
    'Stored image/file binaries in Supabase Storage (member photo paths are included in the member records)'
  ),
  'restore_note','This JSON is an off-site data export, not a one-click database restore. Keep it securely outside Supabase; restoring requires a reviewed import process and reconfiguration of excluded credentials.'
 ) into v_backup;
 return v_backup;
end
$function$;
revoke all on function public.export_gym_backup(uuid) from public,authenticated,anon;
grant execute on function public.export_gym_backup(uuid) to anon,authenticated;
