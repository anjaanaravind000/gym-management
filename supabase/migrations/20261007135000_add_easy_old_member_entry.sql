create or replace function public.create_old_member(
  p_gym_id uuid,
  p_name text,
  p_phone text,
  p_member_id text default null,
  p_join_date date default current_date,
  p_status member_status default 'active',
  p_allow_duplicate_phone boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
declare
  v_member uuid;
  v_mid text;
  v_admin boolean;
begin
  if not private.has_permission(p_gym_id, 'members.create') then
    raise exception 'Unauthorized';
  end if;

  if length(trim(p_name)) < 2 then
    raise exception 'Please enter a valid member name';
  end if;

  if p_phone !~ '^[0-9+][0-9 ()-]{7,19}$' then
    raise exception 'Please enter a valid mobile number';
  end if;

  if p_join_date is null then
    raise exception 'Joining date is required';
  end if;

  if p_status not in ('active','inactive','cancelled') then
    raise exception 'Invalid member status';
  end if;

  v_admin := private.is_admin(p_gym_id);

  if p_allow_duplicate_phone and not v_admin then
    raise exception 'Only an admin can allow duplicate mobile numbers';
  end if;

  v_mid := case
    when nullif(trim(p_member_id), '') is null then private.generate_member_id(p_gym_id)
    else trim(p_member_id)
  end;

  if exists (
    select 1 from public.members
    where gym_id = p_gym_id
      and member_id = v_mid
  ) then
    raise exception 'Member ID already exists';
  end if;

  if exists (
    select 1 from public.members
    where gym_id = p_gym_id
      and phone = p_phone
      and not allow_duplicate_phone
  ) and not p_allow_duplicate_phone then
    raise exception 'An existing member with this mobile number was found';
  end if;

  insert into public.members(
    gym_id, member_id, name, phone, created_by, join_date,
    status, allow_duplicate_phone
  )
  values(
    p_gym_id, v_mid, trim(p_name), trim(p_phone), private.current_app_user_id(),
    p_join_date, p_status, p_allow_duplicate_phone
  )
  returning id into v_member;

  return v_member;
end
$$;

revoke all on function public.create_old_member(uuid,text,text,text,date,member_status,boolean) from public;
grant execute on function public.create_old_member(uuid,text,text,text,date,member_status,boolean) to anon, authenticated;
