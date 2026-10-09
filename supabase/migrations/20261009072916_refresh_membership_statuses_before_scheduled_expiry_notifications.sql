
-- Update membership statuses across every gym during the scheduled expiry run,
-- not only when a gym admin opens the Analytics screen.
create or replace function private.refresh_membership_statuses_for_all_gyms()
returns void
language sql
security definer
set search_path to 'public','private','pg_catalog'
as $function$
 update public.memberships m
 set status=case
   when m.status in ('cancelled','renewed') then m.status
   when exists(
     select 1 from public.memberships later
     where later.previous_membership_id=m.id
       and later.membership_type='renewal'
       and later.start_date<=(now() at time zone g.timezone)::date
   ) then 'renewed'::public.membership_status
   when exists(
     select 1 from public.membership_freezes f
     where f.membership_id=m.id
       and (now() at time zone g.timezone)::date between f.start_date and f.end_date
   ) then 'frozen'::public.membership_status
   when (now() at time zone g.timezone)::date>m.end_date then
     case when (now() at time zone g.timezone)::date<=m.end_date+g.renewal_grace_days
       then 'grace_period'::public.membership_status else 'did_not_renew'::public.membership_status end
   when m.end_date-(now() at time zone g.timezone)::date<=10 then 'expiring_soon'::public.membership_status
   else 'active'::public.membership_status
 end
 from public.gyms g
 where g.id=m.gym_id and m.status not in ('cancelled','renewed');
$function$;
revoke all on function private.refresh_membership_statuses_for_all_gyms() from public,anon,authenticated;

do $$
declare v_sql text; v_old text; v_new text;
begin
 v_sql:=pg_get_functiondef('public.run_expiry_engine()'::regprocedure);
 v_old:=E'begin\n for r in';
 v_new:=E'begin\n perform private.refresh_membership_statuses_for_all_gyms();\n for r in';
 if position(v_old in v_sql)=0 then raise exception 'Could not locate expiry engine loop; migration stopped'; end if;
 execute replace(v_sql,v_old,v_new);
end $$;
