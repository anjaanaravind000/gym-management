create or replace function public.get_class_timetable(p_gym_id uuid,p_from_local date,p_to_local date,p_instructor_id uuid default null,p_class_id uuid default null)
returns setof public.class_timetable_report
language plpgsql security definer
set search_path='public','private','pg_catalog' as $$
declare v_tz text;
begin
 if not (private.has_permission(p_gym_id,'classes.view') or private.has_permission(p_gym_id,'classes.manage') or private.has_permission(p_gym_id,'classes.book')) then
  raise exception 'Unauthorized';
 end if;
 if p_to_local<=p_from_local then raise exception 'Invalid timetable date range'; end if;
 select timezone into v_tz from public.gyms where id=p_gym_id;
 if v_tz is null then raise exception 'Gym timezone is not configured'; end if;
 return query
 select r.*
 from public.class_timetable_report r
 where r.gym_id=p_gym_id
   and (r.start_at at time zone v_tz)::date>=p_from_local
   and (r.start_at at time zone v_tz)::date<p_to_local
   and (p_instructor_id is null or p_instructor_id=r.instructor_id)
   and (p_class_id is null or p_class_id=r.class_id)
 order by r.start_at;
end $$;
grant execute on function public.get_class_timetable(uuid,date,date,uuid,uuid) to anon,authenticated;