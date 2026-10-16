-- Password-protected kiosk lock for the Members Check In / Check Out screen.
-- Password hashes stay in the unexposed private schema and are never returned to the browser.
create table if not exists private.attendance_screen_locks (
  gym_id uuid primary key references public.gyms(id) on delete cascade,
  password_hash text not null,
  failed_attempts integer not null default 0 check (failed_attempts >= 0),
  locked_until timestamptz,
  updated_at timestamptz not null default now(),
  updated_by uuid
);

alter table private.attendance_screen_locks enable row level security;
revoke all on table private.attendance_screen_locks from public, anon, authenticated;

create or replace function private.attendance_screen_lock_status(p_gym_id uuid)
returns boolean language plpgsql stable security definer
set search_path to 'public', 'private', 'pg_catalog'
as $function$
declare v_user_id uuid;
begin
  v_user_id := private.current_app_user_id();
  if v_user_id is null or not exists (
    select 1 from public.users u where u.id=v_user_id and u.gym_id=p_gym_id and u.status='active'
  ) then raise exception 'Unauthorized'; end if;
  return exists(select 1 from private.attendance_screen_locks l where l.gym_id=p_gym_id);
end
$function$;

create or replace function private.save_attendance_screen_password(p_gym_id uuid, p_password text)
returns boolean language plpgsql security definer
set search_path to 'public', 'private', 'pg_catalog'
as $function$
declare v_user_id uuid := private.current_app_user_id();
begin
  if not private.is_admin(p_gym_id) then raise exception 'Unauthorized'; end if;
  if p_password is null then
    delete from private.attendance_screen_locks where gym_id=p_gym_id;
    return false;
  end if;
  if length(p_password)<8 or octet_length(p_password)>72 or p_password !~ '[^[:space:]]' then
    raise exception 'Kiosk password must be 8 to 72 bytes and cannot be blank';
  end if;
  insert into private.attendance_screen_locks(gym_id,password_hash,failed_attempts,locked_until,updated_at,updated_by)
  values(p_gym_id,extensions.crypt(p_password,extensions.gen_salt('bf',12)),0,null,now(),v_user_id)
  on conflict(gym_id) do update set password_hash=excluded.password_hash,failed_attempts=0,locked_until=null,updated_at=now(),updated_by=v_user_id;
  return true;
end
$function$;

create or replace function private.verify_attendance_screen_password(p_gym_id uuid, p_password text)
returns boolean language plpgsql security definer
set search_path to 'public', 'private', 'pg_catalog'
as $function$
declare
  v_user_id uuid := private.current_app_user_id();
  v_lock private.attendance_screen_locks%rowtype;
  v_now timestamptz := clock_timestamp();
  v_failed integer;
begin
  if v_user_id is null or not exists(
    select 1 from public.users u where u.id=v_user_id and u.gym_id=p_gym_id and u.status='active'
  ) then return false; end if;
  select * into v_lock from private.attendance_screen_locks l where l.gym_id=p_gym_id for update;
  if not found then return false; end if;
  if v_lock.locked_until is not null and v_lock.locked_until>v_now then return false;
  elsif v_lock.locked_until is not null then
    update private.attendance_screen_locks set failed_attempts=0,locked_until=null where gym_id=p_gym_id;
    v_lock.failed_attempts:=0;
    v_lock.locked_until:=null;
  end if;
  if p_password is not null and v_lock.password_hash=extensions.crypt(p_password,v_lock.password_hash) then
    update private.attendance_screen_locks set failed_attempts=0,locked_until=null where gym_id=p_gym_id;
    return true;
  end if;
  v_failed:=v_lock.failed_attempts+1;
  update private.attendance_screen_locks set failed_attempts=v_failed,locked_until=case when v_failed>=5 then v_now+interval '15 minutes' else null end where gym_id=p_gym_id;
  return false;
end
$function$;

revoke all on function private.attendance_screen_lock_status(uuid) from public,anon,authenticated;
revoke all on function private.save_attendance_screen_password(uuid,text) from public,anon,authenticated;
revoke all on function private.verify_attendance_screen_password(uuid,text) from public,anon,authenticated;
grant execute on function private.attendance_screen_lock_status(uuid) to anon,authenticated;
grant execute on function private.save_attendance_screen_password(uuid,text) to anon,authenticated;
grant execute on function private.verify_attendance_screen_password(uuid,text) to anon,authenticated;

create or replace function public.attendance_screen_lock_status(p_gym_id uuid)
returns boolean language sql security invoker set search_path to ''
as $function$ select private.attendance_screen_lock_status($1) $function$;

create or replace function public.save_attendance_screen_password(p_gym_id uuid,p_password text)
returns boolean language sql security invoker set search_path to ''
as $function$ select private.save_attendance_screen_password($1,$2) $function$;

create or replace function public.verify_attendance_screen_password(p_gym_id uuid,p_password text)
returns boolean language sql security invoker set search_path to ''
as $function$ select private.verify_attendance_screen_password($1,$2) $function$;

revoke all on function public.attendance_screen_lock_status(uuid) from public,anon,authenticated;
revoke all on function public.save_attendance_screen_password(uuid,text) from public,anon,authenticated;
revoke all on function public.verify_attendance_screen_password(uuid,text) from public,anon,authenticated;
grant execute on function public.attendance_screen_lock_status(uuid) to anon,authenticated;
grant execute on function public.save_attendance_screen_password(uuid,text) to anon,authenticated;
grant execute on function public.verify_attendance_screen_password(uuid,text) to anon,authenticated;
notify pgrst,'reload schema';
