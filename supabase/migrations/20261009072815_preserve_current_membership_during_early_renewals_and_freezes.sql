
-- Keep an old membership usable through its remaining dates when a renewal is
-- booked early. It transitions to "renewed" only once the replacement starts.
do $$
declare v_sql text; v_old text; v_new text;
begin
 v_sql:=pg_get_functiondef('public.create_renewal(uuid,uuid,uuid,integer,date,numeric,numeric,numeric,payment_method,text,text,date)'::regprocedure);
 v_old:='update public.memberships set status=''renewed'' where id=v_old.id;';
 v_new:='if v_start<=v_today then update public.memberships set status=''renewed'' where id=v_old.id; end if;';
 if position(v_old in v_sql)=0 then raise exception 'Could not locate renewal status transition; migration stopped'; end if;
 execute replace(v_sql,v_old,v_new);
end $$;

-- Future freezes stay scheduled without disabling attendance before their start.
do $$
declare v_sql text; v_old text; v_new text;
begin
 v_sql:=pg_get_functiondef('public.freeze_membership(uuid,uuid,date,date,text)'::regprocedure);
 v_old:='update public.memberships set end_date=end_date+v_days,status=''frozen''::membership_status where id=p_membership_id;';
 v_new:='update public.memberships set end_date=end_date+v_days,status=case when p_start_date<=v_today then ''frozen''::membership_status else v_m.status end where id=p_membership_id;';
 if position(v_old in v_sql)=0 then raise exception 'Could not locate freeze status transition; migration stopped'; end if;
 execute replace(v_sql,v_old,v_new);
end $$;

create or replace function public.record_attendance(p_gym_id uuid,p_member_id uuid,p_method text default 'manual')
returns uuid language plpgsql security definer
set search_path to 'public','private','pg_catalog'
as $function$
declare v_id uuid;v_tz text;v_today date;v_member_status public.member_status;
begin
 if not private.has_permission(p_gym_id,'attendance.manage') then raise exception 'Unauthorized'; end if;
 select m.status into v_member_status from public.members m where m.id=p_member_id and m.gym_id=p_gym_id;
 if v_member_status is null then raise exception 'Member not found'; end if;
 if v_member_status<>'active' then raise exception 'Only active members can check in'; end if;
 select g.timezone into v_tz from public.gyms g where g.id=p_gym_id;
 if v_tz is null then raise exception 'Gym timezone is not configured'; end if;
 v_today:=(now() at time zone v_tz)::date;
 if not exists(
   select 1 from public.memberships ms
   where ms.member_id=p_member_id and ms.gym_id=p_gym_id
     and ms.start_date<=v_today and ms.end_date>=v_today
     and ms.status<>'cancelled'
     and not exists(select 1 from public.membership_freezes f where f.membership_id=ms.id and v_today between f.start_date and f.end_date)
 ) then raise exception 'A current, unfrozen membership is required for attendance'; end if;
 insert into public.attendance(gym_id,member_id,method)
 values(p_gym_id,p_member_id,coalesce(nullif(trim(p_method),''),'manual'))
 returning id into v_id;
 return v_id;
exception when unique_violation then raise exception 'Member is already checked in';
end
$function$;

-- Class booking and waitlist promotion use date-aware eligibility and exclude freezes.
do $$
declare v_sql text; v_old text; v_new text;
begin
 v_sql:=pg_get_functiondef('public.book_class(uuid,uuid,uuid)'::regprocedure);
 v_old:='and ms.status in (''active'',''expiring_soon'',''grace_period'')';
 v_new:='and ms.status<>''cancelled'' and not exists(select 1 from public.membership_freezes mf where mf.membership_id=ms.id and v_local_date between mf.start_date and mf.end_date)';
 if position(v_old in v_sql)=0 then raise exception 'Could not locate class booking membership check; migration stopped'; end if;
 execute replace(v_sql,v_old,v_new);
end $$;

do $$
declare v_sql text; v_old text; v_new text;
begin
 v_sql:=pg_get_functiondef('public.cancel_class_booking(uuid,uuid)'::regprocedure);
 v_old:='and ms.status in (''active'',''expiring_soon'',''grace_period'')';
 v_new:='and ms.status<>''cancelled'' and not exists(select 1 from public.membership_freezes mf where mf.membership_id=ms.id and v_local_date between mf.start_date and mf.end_date)';
 if position(v_old in v_sql)=0 then raise exception 'Could not locate waitlist membership check; migration stopped'; end if;
 execute replace(v_sql,v_old,v_new);
end $$;

create or replace function public.sync_membership_statuses()
returns void language plpgsql security definer
set search_path to 'public','private','pg_catalog'
as $function$
declare v_gym_id uuid;v_tz text;v_today date;
begin
 select u.gym_id,g.timezone into v_gym_id,v_tz
 from public.users u join public.gyms g on g.id=u.gym_id
 where u.id=private.current_app_user_id() and u.status='active'
   and (u.role='admin' or exists(
     select 1 from public.user_permissions up
     where up.user_id=u.id and up.allowed=true
       and up.permission in ('members.view'::permission_key,'analytics.view'::permission_key)
   ))
 limit 1;
 if v_gym_id is null then raise exception 'Unauthorized'; end if;
 v_today:=(now() at time zone v_tz)::date;
 update public.memberships m set status=case
   when m.status in ('cancelled','renewed') then m.status
   when exists(select 1 from public.memberships later where later.previous_membership_id=m.id and later.membership_type='renewal' and later.start_date<=v_today) then 'renewed'::membership_status
   when exists(select 1 from public.membership_freezes f where f.membership_id=m.id and v_today between f.start_date and f.end_date) then 'frozen'::membership_status
   when v_today>m.end_date then
     case when v_today<=m.end_date+(select g.renewal_grace_days from public.gyms g where g.id=m.gym_id)
       then 'grace_period'::membership_status else 'did_not_renew'::membership_status end
   when m.end_date-v_today<=10 then 'expiring_soon'::membership_status
   else 'active'::membership_status
 end
 where m.gym_id=v_gym_id and m.status not in ('cancelled','renewed');
end
$function$;

create or replace view public.member_report
with (security_invoker=true)
as
select m.id,m.gym_id,m.member_id,m.name,m.phone,m.email,m.dob,m.gender,m.address,m.emergency_contact,m.emergency_phone,m.photo_url,
 m.status as member_status,m.allow_duplicate_phone,m.created_by,m.assigned_coach_id,m.join_date,
 s.id as membership_uuid,mp.name as package_name,s.membership_type,s.start_date,s.end_date,s.duration_months,
 case
   when s.id is null then null::public.membership_status
   when s.status='cancelled'::public.membership_status then 'cancelled'::public.membership_status
   when exists(select 1 from public.membership_freezes f where f.membership_id=s.id and (now() at time zone g.timezone)::date between f.start_date and f.end_date) then 'frozen'::public.membership_status
   when (now() at time zone g.timezone)::date>s.end_date then
     case when (now() at time zone g.timezone)::date<=s.end_date+g.renewal_grace_days then 'grace_period'::public.membership_status else 'did_not_renew'::public.membership_status end
   when s.end_date-(now() at time zone g.timezone)::date<=10 then 'expiring_soon'::public.membership_status
   else 'active'::public.membership_status
 end as membership_status,
 greatest(s.end_date-(now() at time zone g.timezone)::date,0) as days_remaining,
 s.price,s.discount,s.final_amount,coalesce(sps.paid_amount,0) as paid_amount,coalesce(sps.balance_amount,0) as balance_amount,
 coalesce(sps.payment_status,'pending') as payment_status,u.name as assigned_coach_name
from public.members m
join public.gyms g on g.id=m.gym_id
left join lateral (
 select x.*
 from public.memberships x
 where x.member_id=m.id
 order by
   case
     when x.start_date<=(now() at time zone g.timezone)::date
      and (x.end_date>=(now() at time zone g.timezone)::date
       or (now() at time zone g.timezone)::date<=x.end_date+g.renewal_grace_days) then 0
     when x.start_date<=(now() at time zone g.timezone)::date then 1
     else 2
   end,
   case when x.start_date<=(now() at time zone g.timezone)::date and x.end_date>=(now() at time zone g.timezone)::date then x.start_date end desc,
   case when x.start_date>(now() at time zone g.timezone)::date then x.start_date end asc,
   x.created_at desc,x.end_date desc
 limit 1
) s on true
left join public.membership_packages mp on mp.id=s.package_id
left join public.membership_payment_summary sps on sps.membership_id=s.id
left join public.users u on u.id=m.assigned_coach_id;
