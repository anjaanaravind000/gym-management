create table if not exists public.gym_classes (
  id uuid primary key default gen_random_uuid(), gym_id uuid not null references public.gyms(id),
  name text not null, description text, duration_minutes integer not null default 60 check (duration_minutes between 15 and 240),
  capacity integer not null default 20 check (capacity between 1 and 1000),
  status text not null default 'active' check (status in ('active','inactive')),
  created_by uuid references public.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check (length(trim(name)) >= 2)
);
create index if not exists gym_classes_gym_status_idx on public.gym_classes(gym_id,status,name);
create index if not exists gym_classes_created_by_idx on public.gym_classes(created_by);

create table if not exists public.class_sessions (
  id uuid primary key default gen_random_uuid(), gym_id uuid not null references public.gyms(id),
  class_id uuid not null references public.gym_classes(id), instructor_id uuid not null references public.users(id),
  start_at timestamptz not null, end_at timestamptz not null, capacity integer,
  status text not null default 'scheduled' check (status in ('scheduled','cancelled','completed')),
  cancellation_reason text, created_by uuid references public.users(id), created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(), check (end_at > start_at), check (capacity is null or capacity between 1 and 1000)
);
create index if not exists class_sessions_gym_start_idx on public.class_sessions(gym_id,start_at);
create index if not exists class_sessions_class_start_idx on public.class_sessions(class_id,start_at);
create index if not exists class_sessions_instructor_start_idx on public.class_sessions(instructor_id,start_at);
create index if not exists class_sessions_status_start_idx on public.class_sessions(gym_id,status,start_at);

create table if not exists public.class_bookings (
  id uuid primary key default gen_random_uuid(), gym_id uuid not null references public.gyms(id),
  session_id uuid not null references public.class_sessions(id), member_id uuid not null references public.members(id),
  status text not null default 'booked' check (status in ('booked','waitlisted','cancelled','attended','no_show')),
  waitlist_position integer, booked_at timestamptz not null default now(), cancelled_at timestamptz, notes text,
  updated_at timestamptz not null default now(),
  check ((status='waitlisted' and waitlist_position is not null and waitlist_position>0) or status<>'waitlisted')
);
create index if not exists class_bookings_session_status_idx on public.class_bookings(session_id,status,booked_at);
create index if not exists class_bookings_member_status_idx on public.class_bookings(member_id,status,booked_at desc);
create index if not exists class_bookings_gym_booked_idx on public.class_bookings(gym_id,status,booked_at desc);
create unique index if not exists class_bookings_active_member_uq on public.class_bookings(session_id,member_id) where status in ('booked','waitlisted');
create unique index if not exists class_bookings_waitlist_position_uq on public.class_bookings(session_id,waitlist_position) where status='waitlisted';

alter table public.gym_classes enable row level security;
alter table public.class_sessions enable row level security;
alter table public.class_bookings enable row level security;
grant select on public.gym_classes,public.class_sessions,public.class_bookings to anon,authenticated;
drop policy if exists gym_classes_select on public.gym_classes;
create policy gym_classes_select on public.gym_classes for select to anon,authenticated
using (private.has_permission(gym_id,'classes.view') or private.has_permission(gym_id,'classes.manage') or private.has_permission(gym_id,'classes.book'));
drop policy if exists class_sessions_select on public.class_sessions;
create policy class_sessions_select on public.class_sessions for select to anon,authenticated
using (private.has_permission(gym_id,'classes.view') or private.has_permission(gym_id,'classes.manage') or private.has_permission(gym_id,'classes.book'));
drop policy if exists class_bookings_select on public.class_bookings;
create policy class_bookings_select on public.class_bookings for select to anon,authenticated
using (private.has_permission(gym_id,'classes.view') or private.has_permission(gym_id,'classes.manage') or private.has_permission(gym_id,'classes.book'));
revoke insert,update,delete,truncate,references,trigger on public.gym_classes,public.class_sessions,public.class_bookings from anon,authenticated;

insert into public.permissions(key,description) values
('classes.view','View classes, timetable and bookings'),
('classes.manage','Create classes, schedule sessions and manage instructors'),
('classes.book','Book and cancel members in classes') on conflict(key) do update set description=excluded.description;

create or replace view public.class_timetable_report with (security_invoker=true) as
select s.id,s.gym_id,s.class_id,c.name class_name,c.description class_description,c.duration_minutes,
coalesce(s.capacity,c.capacity) capacity,s.instructor_id,u.name instructor_name,s.start_at,s.end_at,s.status,s.cancellation_reason,
coalesce(b.booked_count,0)::bigint booked_count,coalesce(b.waitlist_count,0)::bigint waitlist_count
from public.class_sessions s join public.gym_classes c on c.id=s.class_id join public.users u on u.id=s.instructor_id
left join lateral (select count(*) filter(where cb.status in ('booked','attended')) booked_count,count(*) filter(where cb.status='waitlisted') waitlist_count
from public.class_bookings cb where cb.session_id=s.id) b on true;
grant select on public.class_timetable_report to anon,authenticated;

create or replace view public.member_class_bookings_report with (security_invoker=true) as
select b.id,b.gym_id,b.member_id,b.session_id,b.status,b.waitlist_position,b.booked_at,b.cancelled_at,
s.start_at,s.end_at,s.status session_status,c.name class_name,u.name instructor_name,coalesce(s.capacity,c.capacity) capacity
from public.class_bookings b join public.class_sessions s on s.id=b.session_id join public.gym_classes c on c.id=s.class_id join public.users u on u.id=s.instructor_id;
grant select on public.member_class_bookings_report to anon,authenticated;

create or replace function public.save_class(p_gym_id uuid,p_class_id uuid default null,p_name text default '',p_description text default null,p_duration_minutes integer default 60,p_capacity integer default 20,p_status text default 'active')
returns uuid language plpgsql security definer set search_path='public','private','pg_catalog' as $$
declare v_id uuid;
begin
 if not private.has_permission(p_gym_id,'classes.manage') then raise exception 'Unauthorized'; end if;
 if length(trim(coalesce(p_name,'')))<2 then raise exception 'Class name must be at least 2 characters'; end if;
 if p_duration_minutes not between 15 and 240 then raise exception 'Class duration must be between 15 and 240 minutes'; end if;
 if p_capacity not between 1 and 1000 then raise exception 'Class capacity must be between 1 and 1000'; end if;
 if p_status not in ('active','inactive') then raise exception 'Invalid class status'; end if;
 if p_class_id is null then
  insert into public.gym_classes(gym_id,name,description,duration_minutes,capacity,status,created_by)
  values(p_gym_id,trim(p_name),nullif(trim(p_description),''),p_duration_minutes,p_capacity,p_status,private.current_app_user_id()) returning id into v_id;
 else
  update public.gym_classes set name=trim(p_name),description=nullif(trim(p_description),''),duration_minutes=p_duration_minutes,capacity=p_capacity,status=p_status,updated_at=now()
  where id=p_class_id and gym_id=p_gym_id;
  if not found then raise exception 'Class not found'; end if; v_id:=p_class_id;
 end if; return v_id;
end $$;

create or replace function public.save_class_session(p_gym_id uuid,p_session_id uuid default null,p_class_id uuid default null,p_instructor_id uuid default null,p_start_local timestamp default null,p_end_local timestamp default null,p_capacity integer default null,p_repeat_weeks integer default 1)
returns uuid[] language plpgsql security definer set search_path='public','private','pg_catalog' as $$
declare v_ids uuid[]:=array[]::uuid[];v_id uuid;v_tz text;v_start timestamptz;v_end timestamptz;i integer;
begin
 if not private.has_permission(p_gym_id,'classes.manage') then raise exception 'Unauthorized'; end if;
 if p_start_local is null or p_end_local is null or p_end_local<=p_start_local then raise exception 'End time must be after start time'; end if;
 if p_repeat_weeks not between 1 and 52 then raise exception 'Repeat weeks must be between 1 and 52'; end if;
 if p_session_id is not null and p_repeat_weeks<>1 then raise exception 'Edit one session at a time'; end if;
 select timezone into v_tz from public.gyms where id=p_gym_id; if v_tz is null then raise exception 'Gym timezone is not configured'; end if;
 if not exists(select 1 from public.gym_classes where id=p_class_id and gym_id=p_gym_id and status='active') then raise exception 'Active class not found'; end if;
 if not exists(select 1 from public.users where id=p_instructor_id and gym_id=p_gym_id and status='active') then raise exception 'Active instructor not found'; end if;
 if p_capacity is not null and p_capacity<1 then raise exception 'Session capacity must be positive'; end if;
 if p_session_id is not null then
  update public.class_sessions set class_id=p_class_id,instructor_id=p_instructor_id,start_at=(p_start_local at time zone v_tz),end_at=(p_end_local at time zone v_tz),capacity=p_capacity,updated_at=now()
  where id=p_session_id and gym_id=p_gym_id and status='scheduled';
  if not found then raise exception 'Scheduled session not found'; end if;
  v_start=p_start_local at time zone v_tz;v_end=p_end_local at time zone v_tz;
  if exists(select 1 from public.class_sessions where gym_id=p_gym_id and instructor_id=p_instructor_id and status='scheduled' and id<>p_session_id and start_at<v_end and end_at>v_start) then
   raise exception 'Instructor is already scheduled for another class at this time';
  end if;
  v_ids=array[p_session_id];
 else
  perform pg_advisory_xact_lock(hashtextextended(p_gym_id::text||':'||p_instructor_id::text,0));
  for i in 0..p_repeat_weeks-1 loop
   v_start=(p_start_local+(i*interval '7 days')) at time zone v_tz;v_end=(p_end_local+(i*interval '7 days')) at time zone v_tz;
   if exists(select 1 from public.class_sessions where gym_id=p_gym_id and instructor_id=p_instructor_id and status='scheduled' and start_at<v_end and end_at>v_start) then raise exception 'Instructor is already scheduled during one of the requested sessions'; end if;
   insert into public.class_sessions(gym_id,class_id,instructor_id,start_at,end_at,capacity,created_by) values(p_gym_id,p_class_id,p_instructor_id,v_start,v_end,p_capacity,private.current_app_user_id()) returning id into v_id;
   v_ids=array_append(v_ids,v_id);
  end loop;
 end if; return v_ids;
end $$;

create or replace function public.cancel_class_session(p_gym_id uuid,p_session_id uuid,p_reason text)
returns void language plpgsql security definer set search_path='public','private','pg_catalog' as $$
begin
 if not private.has_permission(p_gym_id,'classes.manage') then raise exception 'Unauthorized'; end if;
 if trim(coalesce(p_reason,''))='' then raise exception 'Cancellation reason is required'; end if;
 update public.class_sessions set status='cancelled',cancellation_reason=trim(p_reason),updated_at=now() where id=p_session_id and gym_id=p_gym_id and status='scheduled';
 if not found then raise exception 'Scheduled session not found'; end if;
 update public.class_bookings set status='cancelled',cancelled_at=now(),updated_at=now() where session_id=p_session_id and status in ('booked','waitlisted');
end $$;

create or replace function public.book_class(p_gym_id uuid,p_session_id uuid,p_member_id uuid)
returns jsonb language plpgsql security definer set search_path='public','private','pg_catalog' as $$
declare s record;m record;v_tz text;v_local_date date;v_capacity integer;v_booked integer;v_wait_position integer;
begin
 if not private.has_permission(p_gym_id,'classes.book') then raise exception 'Unauthorized'; end if;
 select timezone into v_tz from public.gyms where id=p_gym_id; if v_tz is null then raise exception 'Gym timezone is not configured'; end if;
 select s1.*,coalesce(s1.capacity,c1.capacity) effective_capacity into s from public.class_sessions s1 join public.gym_classes c1 on c1.id=s1.class_id where s1.id=p_session_id and s1.gym_id=p_gym_id for update;
 if not found then raise exception 'Class session not found'; end if;
 if s.status<>'scheduled' then raise exception 'This class session is not available for booking'; end if;
 if s.start_at<=now() then raise exception 'This class session has already started'; end if;
 select * into m from public.members where id=p_member_id and gym_id=p_gym_id and status='active'; if not found then raise exception 'Active member not found'; end if;
 v_local_date=(s.start_at at time zone v_tz)::date;
 if not exists(select 1 from public.memberships ms where ms.member_id=p_member_id and ms.gym_id=p_gym_id and ms.start_date<=v_local_date and ms.end_date>=v_local_date and ms.status in ('active','expiring_soon','grace_period')) then raise exception 'Member does not have a valid membership for this class date'; end if;
 if exists(select 1 from public.class_bookings b join public.class_sessions os on os.id=b.session_id where b.member_id=p_member_id and b.status in ('booked','attended') and os.status='scheduled' and os.start_at<s.end_at and os.end_at>s.start_at) then raise exception 'Member is already booked in another class at this time'; end if;
 if exists(select 1 from public.class_bookings b where b.session_id=p_session_id and b.member_id=p_member_id and b.status in ('booked','waitlisted')) then raise exception 'Member is already booked or waitlisted for this class'; end if;
 select count(*)::integer into v_booked from public.class_bookings b where b.session_id=p_session_id and b.status='booked';
 v_capacity=s.effective_capacity;
 if v_booked<v_capacity then
  insert into public.class_bookings(gym_id,session_id,member_id,status) values(p_gym_id,p_session_id,p_member_id,'booked');
  return jsonb_build_object('status','booked','waitlist_position',null);
 end if;
 select coalesce(max(waitlist_position),0)+1 into v_wait_position from public.class_bookings where session_id=p_session_id and status='waitlisted';
 insert into public.class_bookings(gym_id,session_id,member_id,status,waitlist_position) values(p_gym_id,p_session_id,p_member_id,'waitlisted',v_wait_position);
 return jsonb_build_object('status','waitlisted','waitlist_position',v_wait_position);
end $$;

create or replace function public.cancel_class_booking(p_gym_id uuid,p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path='public','private','pg_catalog' as $$
declare b record;s record;next_id uuid;v_promoted boolean:=false;
begin
 if not private.has_permission(p_gym_id,'classes.book') then raise exception 'Unauthorized'; end if;
 select b1.* into b from public.class_bookings b1 where b1.id=p_booking_id and b1.gym_id=p_gym_id for update; if not found then raise exception 'Booking not found'; end if;
 if b.status not in ('booked','waitlisted') then raise exception 'Booking is already cancelled or closed'; end if;
 select * into s from public.class_sessions where id=b.session_id and gym_id=p_gym_id for update;
 update public.class_bookings set status='cancelled',cancelled_at=now(),updated_at=now(),waitlist_position=null where id=b.id;
 if b.status='booked' and s.status='scheduled' then
  select id into next_id from public.class_bookings where session_id=s.id and status='waitlisted' order by waitlist_position,booked_at,id limit 1;
  if next_id is not null then
   update public.class_bookings set status='booked',waitlist_position=null,updated_at=now() where id=next_id;v_promoted=true;
   with ranked as (select id,row_number() over(order by booked_at,id) rn from public.class_bookings where session_id=s.id and status='waitlisted')
   update public.class_bookings cb set waitlist_position=ranked.rn,updated_at=now() from ranked where cb.id=ranked.id;
  end if;
 end if;
 if b.status='waitlisted' then
  with ranked as (select id,row_number() over(order by booked_at,id) rn from public.class_bookings where session_id=s.id and status='waitlisted')
  update public.class_bookings cb set waitlist_position=ranked.rn,updated_at=now() from ranked where cb.id=ranked.id;
 end if;
 return jsonb_build_object('cancelled',true,'promoted',v_promoted);
end $$;

create or replace function public.set_class_booking_attendance(p_gym_id uuid,p_booking_id uuid,p_status text)
returns void language plpgsql security definer set search_path='public','private','pg_catalog' as $$
begin
 if not private.has_permission(p_gym_id,'classes.manage') then raise exception 'Unauthorized'; end if;
 if p_status not in ('attended','no_show') then raise exception 'Invalid attendance status'; end if;
 update public.class_bookings set status=p_status,waitlist_position=null,updated_at=now() where id=p_booking_id and gym_id=p_gym_id and status='booked';
 if not found then raise exception 'Active booking not found'; end if;
end $$;

grant execute on function public.save_class(uuid,uuid,text,text,integer,integer,text) to anon,authenticated;
grant execute on function public.save_class_session(uuid,uuid,uuid,uuid,timestamp,timestamp,integer,integer) to anon,authenticated;
grant execute on function public.cancel_class_session(uuid,uuid,text) to anon,authenticated;
grant execute on function public.book_class(uuid,uuid,uuid) to anon,authenticated;
grant execute on function public.cancel_class_booking(uuid,uuid) to anon,authenticated;
grant execute on function public.set_class_booking_attendance(uuid,uuid,text) to anon,authenticated;