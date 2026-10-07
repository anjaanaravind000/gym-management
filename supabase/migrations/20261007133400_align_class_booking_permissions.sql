
create or replace function public.book_class(p_gym_id uuid,p_session_id uuid,p_member_id uuid)
returns jsonb language plpgsql security definer set search_path='public','private','pg_catalog' as $$
declare s record;m record;v_tz text;v_local_date date;v_capacity integer;v_booked integer;v_wait_position integer;
begin
 if not (private.has_permission(p_gym_id,'classes.book') or private.has_permission(p_gym_id,'classes.manage')) then raise exception 'Unauthorized'; end if;
 select timezone into v_tz from public.gyms where id=p_gym_id; if v_tz is null then raise exception 'Gym timezone is not configured'; end if;
 select s1.*,coalesce(s1.capacity,c1.capacity) effective_capacity into s
 from public.class_sessions s1 join public.gym_classes c1 on c1.id=s1.class_id where s1.id=p_session_id and s1.gym_id=p_gym_id for update;
 if not found then raise exception 'Class session not found'; end if;
 if s.status<>'scheduled' then raise exception 'This class session is not available for booking'; end if;
 if s.start_at<=now() then raise exception 'This class session has already started'; end if;
 select * into m from public.members where id=p_member_id and gym_id=p_gym_id and status='active'; if not found then raise exception 'Active member not found'; end if;
 v_local_date=(s.start_at at time zone v_tz)::date;
 if not exists(select 1 from public.memberships ms where ms.member_id=p_member_id and ms.gym_id=p_gym_id and ms.start_date<=v_local_date and ms.end_date>=v_local_date and ms.status in ('active','expiring_soon','grace_period')) then raise exception 'Member does not have a valid membership for this class date'; end if;
 if exists(select 1 from public.class_bookings b join public.class_sessions os on os.id=b.session_id where b.member_id=p_member_id and b.status='booked' and os.status='scheduled' and os.start_at<s.end_at and os.end_at>s.start_at) then raise exception 'Member is already booked in another class at this time'; end if;
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
 if not (private.has_permission(p_gym_id,'classes.book') or private.has_permission(p_gym_id,'classes.manage')) then raise exception 'Unauthorized'; end if;
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