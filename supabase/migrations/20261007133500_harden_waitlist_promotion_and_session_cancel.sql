create or replace function public.cancel_class_session(p_gym_id uuid,p_session_id uuid,p_reason text)
returns void language plpgsql security definer set search_path='public','private','pg_catalog' as $$
begin
 if not private.has_permission(p_gym_id,'classes.manage') then raise exception 'Unauthorized'; end if;
 if trim(coalesce(p_reason,''))='' then raise exception 'Cancellation reason is required'; end if;
 update public.class_sessions set status='cancelled',cancellation_reason=trim(p_reason),updated_at=now()
 where id=p_session_id and gym_id=p_gym_id and status='scheduled';
 if not found then raise exception 'Scheduled session not found'; end if;
 update public.class_bookings set status='cancelled',cancelled_at=now(),updated_at=now(),waitlist_position=null
 where session_id=p_session_id and status in ('booked','waitlisted');
end $$;

create or replace function public.cancel_class_booking(p_gym_id uuid,p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path='public','private','pg_catalog' as $$
declare b record;s record;next_row record;v_promoted boolean:=false;v_tz text;v_local_date date;
begin
 if not (private.has_permission(p_gym_id,'classes.book') or private.has_permission(p_gym_id,'classes.manage')) then raise exception 'Unauthorized'; end if;
 select b1.* into b from public.class_bookings b1 where b1.id=p_booking_id and b1.gym_id=p_gym_id for update;
 if not found then raise exception 'Booking not found'; end if;
 if b.status not in ('booked','waitlisted') then raise exception 'Booking is already cancelled or closed'; end if;
 select * into s from public.class_sessions where id=b.session_id and gym_id=p_gym_id for update;
 select timezone into v_tz from public.gyms where id=p_gym_id;
 update public.class_bookings set status='cancelled',cancelled_at=now(),updated_at=now(),waitlist_position=null where id=b.id;
 if b.status='booked' and s.status='scheduled' then
   v_local_date=(s.start_at at time zone v_tz)::date;
   for next_row in
     select cb.id,cb.member_id
     from public.class_bookings cb
     where cb.session_id=s.id and cb.status='waitlisted'
     order by cb.waitlist_position,cb.booked_at,cb.id
   loop
     if not exists(select 1 from public.members m where m.id=next_row.member_id and m.gym_id=p_gym_id and m.status='active')
        or not exists(select 1 from public.memberships ms where ms.member_id=next_row.member_id and ms.gym_id=p_gym_id
                      and ms.start_date<=v_local_date and ms.end_date>=v_local_date
                      and ms.status in ('active','expiring_soon','grace_period')) then
       update public.class_bookings set status='cancelled',cancelled_at=now(),updated_at=now(),waitlist_position=null,
         notes=concat_ws(E'\n',notes,'Removed from waitlist: membership/member is no longer eligible.')
       where id=next_row.id;
       continue;
     end if;
     if exists(select 1 from public.class_bookings wb join public.class_sessions os on os.id=wb.session_id
               where wb.member_id=next_row.member_id and wb.status='booked' and os.status='scheduled'
                 and os.start_at<s.end_at and os.end_at>s.start_at) then
       continue;
     end if;
     update public.class_bookings set status='booked',waitlist_position=null,updated_at=now() where id=next_row.id;
     v_promoted=true;
     exit;
   end loop;
   with ranked as (
     select id,row_number() over(order by booked_at,id) rn
     from public.class_bookings where session_id=s.id and status='waitlisted'
   )
   update public.class_bookings cb set waitlist_position=ranked.rn,updated_at=now() from ranked where cb.id=ranked.id;
 end if;
 if b.status='waitlisted' then
   with ranked as (
     select id,row_number() over(order by booked_at,id) rn
     from public.class_bookings where session_id=s.id and status='waitlisted'
   )
   update public.class_bookings cb set waitlist_position=ranked.rn,updated_at=now() from ranked where cb.id=ranked.id;
 end if;
 return jsonb_build_object('cancelled',true,'promoted',v_promoted);
end $$;