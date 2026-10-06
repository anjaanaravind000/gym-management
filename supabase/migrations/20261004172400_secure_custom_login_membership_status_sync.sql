create or replace function public.sync_membership_statuses()
returns void
language plpgsql
security definer
set search_path to 'public','private','pg_catalog'
as $function$
declare
  v_gym_id uuid;
begin
  select u.gym_id
    into v_gym_id
  from public.users as u
  where u.id = private.current_app_user_id()
    and u.status = 'active'
    and u.role = 'admin'
  limit 1;

  if v_gym_id is null then
    raise exception 'Unauthorized';
  end if;

  update public.memberships as m
  set status = case
    when m.status in ('cancelled','renewed') then m.status
    when exists(
      select 1 from public.membership_freezes as f
      where f.membership_id = m.id
        and current_date between f.start_date and f.end_date
    ) then 'frozen'::membership_status
    when current_date > m.end_date then
      case
        when current_date <= m.end_date + (
          select g.renewal_grace_days from public.gyms as g where g.id = m.gym_id
        ) then 'grace_period'::membership_status
        else 'did_not_renew'::membership_status
      end
    when m.end_date - current_date <= 10 then 'expiring_soon'::membership_status
    else 'active'::membership_status
  end
  where m.gym_id = v_gym_id
    and m.status not in ('cancelled','renewed');
end
$function$;

revoke all on function public.sync_membership_statuses() from public, authenticated;
grant execute on function public.sync_membership_statuses() to anon, authenticated;
