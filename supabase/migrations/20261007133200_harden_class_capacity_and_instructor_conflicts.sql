create or replace function public.save_class(p_gym_id uuid,p_class_id uuid default null,p_name text default '',p_description text default null,p_duration_minutes integer default 60,p_capacity integer default 20,p_status text default 'active')
returns uuid language plpgsql security definer set search_path='public','private','pg_catalog' as $$
declare v_id uuid;
begin
 if not private.has_permission(p_gym_id,'classes.manage') then raise exception 'Unauthorized'; end if;
 if length(trim(coalesce(p_name,'')))<2 then raise exception 'Class name must be at least 2 characters'; end if;
 if p_duration_minutes not between 15 and 240 then raise exception 'Class duration must be between 15 and 240 minutes'; end if;
 if p_capacity not between 1 and 1000 then raise exception 'Class capacity must be between 1 and 1000'; end if;
 if p_status not in ('active','inactive') then raise exception 'Invalid class status'; end if;
 if p_class_id is not null and not exists(select 1 from public.gym_classes where id=p_class_id and gym_id=p_gym_id) then raise exception 'Class not found'; end if;
 if p_class_id is not null and exists(
   select 1 from public.class_sessions s
   where s.class_id=p_class_id and s.gym_id=p_gym_id and s.status='scheduled' and s.capacity is null
   and (select count(*) from public.class_bookings b where b.session_id=s.id and b.status in ('booked','attended'))>p_capacity
 ) then raise exception 'Capacity cannot be reduced below already booked spots'; end if;
 if p_class_id is null then
  insert into public.gym_classes(gym_id,name,description,duration_minutes,capacity,status,created_by)
  values(p_gym_id,trim(p_name),nullif(trim(p_description),''),p_duration_minutes,p_capacity,p_status,private.current_app_user_id())
  returning id into v_id;
 else
  update public.gym_classes set name=trim(p_name),description=nullif(trim(p_description),''),duration_minutes=p_duration_minutes,
    capacity=p_capacity,status=p_status,updated_at=now()
  where id=p_class_id and gym_id=p_gym_id;
  v_id=p_class_id;
 end if;
 return v_id;
end $$;

create or replace function public.save_class_session(p_gym_id uuid,p_session_id uuid default null,p_class_id uuid default null,p_instructor_id uuid default null,
 p_start_local timestamp default null,p_end_local timestamp default null,p_capacity integer default null,p_repeat_weeks integer default 1)
returns uuid[] language plpgsql security definer set search_path='public','private','pg_catalog' as $$
declare v_ids uuid[]:=array[]::uuid[];v_id uuid;v_tz text;v_start timestamptz;v_end timestamptz;v_class_capacity integer;v_existing_booked integer;i integer;
begin
 if not private.has_permission(p_gym_id,'classes.manage') then raise exception 'Unauthorized'; end if;
 if p_start_local is null or p_end_local is null or p_end_local<=p_start_local then raise exception 'End time must be after start time'; end if;
 if p_repeat_weeks not between 1 and 52 then raise exception 'Repeat weeks must be between 1 and 52'; end if;
 if p_session_id is not null and p_repeat_weeks<>1 then raise exception 'Edit one session at a time'; end if;
 select timezone into v_tz from public.gyms where id=p_gym_id; if v_tz is null then raise exception 'Gym timezone is not configured'; end if;
 if not exists(select 1 from public.gym_classes where id=p_class_id and gym_id=p_gym_id and status='active') then raise exception 'Active class not found'; end if;
 if not exists(select 1 from public.users where id=p_instructor_id and gym_id=p_gym_id and status='active') then raise exception 'Active instructor not found'; end if;
 if p_capacity is not null and p_capacity<1 then raise exception 'Session capacity must be positive'; end if;
 if (p_start_local at time zone v_tz)<=now() then raise exception 'Class session must start in the future'; end if;
 select capacity into v_class_capacity from public.gym_classes where id=p_class_id;
 if p_session_id is not null then
  select count(*)::integer into v_existing_booked from public.class_bookings where session_id=p_session_id and status in ('booked','attended');
  if coalesce(p_capacity,v_class_capacity)<v_existing_booked then raise exception 'Session capacity cannot be below already booked spots'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_gym_id::text||':'||p_instructor_id::text,0));
  v_start=p_start_local at time zone v_tz;v_end=p_end_local at time zone v_tz;
  if exists(select 1 from public.class_sessions where gym_id=p_gym_id and instructor_id=p_instructor_id and status='scheduled' and id<>p_session_id and start_at<v_end and end_at>v_start)
    then raise exception 'Instructor is already scheduled for another class at this time'; end if;
  update public.class_sessions set class_id=p_class_id,instructor_id=p_instructor_id,start_at=v_start,end_at=v_end,capacity=p_capacity,updated_at=now()
  where id=p_session_id and gym_id=p_gym_id and status='scheduled';
  if not found then raise exception 'Scheduled session not found'; end if;
  v_ids=array[p_session_id];
 else
  perform pg_advisory_xact_lock(hashtextextended(p_gym_id::text||':'||p_instructor_id::text,0));
  for i in 0..p_repeat_weeks-1 loop
   v_start=(p_start_local+(i*interval '7 days')) at time zone v_tz;v_end=(p_end_local+(i*interval '7 days')) at time zone v_tz;
   if v_start<=now() then raise exception 'All repeated sessions must start in the future'; end if;
   if exists(select 1 from public.class_sessions where gym_id=p_gym_id and instructor_id=p_instructor_id and status='scheduled' and start_at<v_end and end_at>v_start)
    then raise exception 'Instructor is already scheduled during one of the requested sessions'; end if;
   insert into public.class_sessions(gym_id,class_id,instructor_id,start_at,end_at,capacity,created_by)
   values(p_gym_id,p_class_id,p_instructor_id,v_start,v_end,p_capacity,private.current_app_user_id())
   returning id into v_id;
   v_ids=array_append(v_ids,v_id);
  end loop;
 end if;
 return v_ids;
end $$;