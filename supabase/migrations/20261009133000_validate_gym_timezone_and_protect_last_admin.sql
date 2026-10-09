-- Validate timezone and settings fields before applying them; preserve an active administrator for recovery.
create or replace function public.save_gym_profile(
 p_gym_id uuid,p_name text,p_address text default null,p_phone text default null,p_whatsapp text default null,p_email text default null,
 p_gst_number text default null,p_currency text default 'INR',p_timezone text default 'Asia/Kolkata',p_opening_time time default null,p_closing_time time default null,
 p_weekly_holidays smallint[] default '{}',p_member_id_prefix text default 'GYM',p_renewal_grace_days integer default 7
)
returns public.gyms language plpgsql security definer
set search_path to 'public','private','pg_catalog'
as $$
declare v public.gyms%rowtype;
begin
 if not private.is_admin(p_gym_id) then raise exception 'Unauthorized'; end if;
 if nullif(trim(p_name),'') is null then raise exception 'Gym name is required'; end if;
 if p_renewal_grace_days is null or p_renewal_grace_days<0 or p_renewal_grace_days>365 then raise exception 'Grace period must be between 0 and 365 days'; end if;
 if nullif(trim(p_currency),'') is null or length(trim(p_currency))<>3 or trim(p_currency)!~'^[A-Za-z]{3}$' then raise exception 'Currency must be a 3-letter code'; end if;
 if nullif(trim(p_timezone),'') is null or not exists(select 1 from pg_timezone_names where name=trim(p_timezone)) then raise exception 'Choose a valid IANA timezone'; end if;
 if p_weekly_holidays is null or exists(select 1 from unnest(p_weekly_holidays) d where d<0 or d>6) then raise exception 'Weekly holidays must use day numbers from 0 to 6'; end if;
 if nullif(trim(p_member_id_prefix),'') is not null and trim(p_member_id_prefix)!~'^[A-Za-z0-9_-]{1,12}$' then raise exception 'Member ID prefix must be 1-12 letters, numbers, hyphens or underscores'; end if;
 if p_opening_time is not null and p_closing_time is not null and p_closing_time<=p_opening_time then raise exception 'Closing time must be after opening time'; end if;
 update public.gyms set name=trim(p_name),address=nullif(trim(p_address),''),phone=nullif(trim(p_phone),''),whatsapp=nullif(trim(p_whatsapp),''),email=nullif(trim(p_email),''),
  gst_number=nullif(trim(p_gst_number),''),currency=upper(trim(p_currency)),timezone=trim(p_timezone),opening_time=p_opening_time,closing_time=p_closing_time,
  weekly_holidays=coalesce(p_weekly_holidays,'{}'),member_id_prefix=upper(coalesce(nullif(trim(p_member_id_prefix),''),'GYM')),
  renewal_grace_days=p_renewal_grace_days,updated_at=now()
 where id=p_gym_id returning * into v;
 if not found then raise exception 'Gym not found'; end if;
 return v;
end
$$;

create or replace function public.set_staff_role(p_gym_id uuid,p_user_id uuid,p_role public.user_role,p_status text default 'active')
returns void language plpgsql security definer
set search_path to 'public','private','pg_catalog'
as $$
declare v_old_role public.user_role;v_old_status text;v_admin_count integer;
begin
 if not private.has_permission(p_gym_id,'staff.manage') then raise exception 'Unauthorized'; end if;
 if p_status not in('active','inactive','suspended') then raise exception 'Invalid staff status'; end if;
 select role,status into v_old_role,v_old_status from public.users where id=p_user_id and gym_id=p_gym_id for update;
 if not found then raise exception 'Staff member not found'; end if;
 if v_old_role='admin' and v_old_status='active' and (p_role<>'admin' or p_status<>'active') then
   select count(*) into v_admin_count from public.users where gym_id=p_gym_id and role='admin' and status='active' and id<>p_user_id;
   if v_admin_count=0 then raise exception 'A gym must keep at least one active admin'; end if;
 end if;
 if p_user_id=private.current_app_user_id() and (p_role<>'admin' or p_status<>'active') then raise exception 'You cannot deactivate or remove your own admin access'; end if;
 update public.users set role=p_role,status=p_status,updated_at=now() where id=p_user_id and gym_id=p_gym_id;
 update public.login_accounts set role=p_role::text,status=p_status,updated_at=now() where id=p_user_id and gym_id=p_gym_id;
 if not found then raise exception 'Login account not found'; end if;
end
$$;
