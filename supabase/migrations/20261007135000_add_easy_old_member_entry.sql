alter type public.membership_type add value if not exists 'imported';

drop function if exists public.create_old_member(uuid,text,text,text,date,public.member_status,boolean);

create or replace function public.create_old_member(
  p_gym_id uuid,
  p_name text,
  p_phone text,
  p_email text default null,
  p_dob date default null,
  p_gender text default null,
  p_address text default null,
  p_emergency_contact text default null,
  p_emergency_phone text default null,
  p_member_id text default null,
  p_join_date date default current_date,
  p_status member_status default 'active',
  p_assigned_coach_id uuid default null,
  p_allow_duplicate_phone boolean default false,
  p_add_membership boolean default false,
  p_package_id uuid default null,
  p_membership_start_date date default null,
  p_membership_end_date date default null,
  p_membership_status membership_status default 'active',
  p_price numeric default null,
  p_duration_months integer default null,
  p_discount numeric default 0,
  p_amount_paid numeric default 0,
  p_payment_method payment_method default 'cash',
  p_payment_date date default null,
  p_transaction_reference text default null,
  p_payment_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
declare
  v_member uuid;
  v_mid text;
  v_phone text := trim(p_phone);
  v_admin boolean;
  v_price numeric;
  v_duration integer;
  v_final numeric;
  v_membership uuid;
  v_tz text;
  v_today date;
  v_membership_status membership_status;
begin
  if not private.has_permission(p_gym_id, 'members.create') then raise exception 'Unauthorized'; end if;
  if length(trim(p_name)) < 2 then raise exception 'Please enter a valid member name'; end if;
  if v_phone !~ '^[0-9+][0-9 ()-]{7,19}$' then raise exception 'Please enter a valid mobile number'; end if;
  if p_join_date is null then raise exception 'Joining date is required'; end if;
  if p_status not in ('active','inactive','cancelled') then raise exception 'Invalid member status'; end if;

  v_admin := private.is_admin(p_gym_id);
  if p_allow_duplicate_phone and not v_admin then raise exception 'Only an admin can allow duplicate mobile numbers'; end if;

  if p_assigned_coach_id is not null and not exists(
    select 1 from public.users where id=p_assigned_coach_id and gym_id=p_gym_id and status='active'
  ) then raise exception 'Invalid assigned coach'; end if;

  v_mid := case when nullif(trim(p_member_id),'') is null then private.generate_member_id(p_gym_id) else trim(p_member_id) end;

  if exists(select 1 from public.members where gym_id=p_gym_id and member_id=v_mid) then
    raise exception 'Member ID already exists';
  end if;

  if exists(
    select 1 from public.members where gym_id=p_gym_id and phone=v_phone and not allow_duplicate_phone
  ) and not p_allow_duplicate_phone then
    raise exception 'An existing member with this mobile number was found';
  end if;

  insert into public.members(
    gym_id,member_id,name,phone,email,dob,gender,address,emergency_contact,emergency_phone,
    created_by,join_date,status,assigned_coach_id,allow_duplicate_phone
  )
  values(
    p_gym_id,v_mid,trim(p_name),v_phone,nullif(trim(p_email),''),
    p_dob,p_gender,p_address,p_emergency_contact,p_emergency_phone,
    private.current_app_user_id(),p_join_date,p_status,p_assigned_coach_id,p_allow_duplicate_phone
  )
  returning id into v_member;

  if p_add_membership then
    if p_package_id is not null then
      select price,duration_months into v_price,v_duration
      from public.membership_packages
      where id=p_package_id and gym_id=p_gym_id;
      if not found then raise exception 'Invalid package'; end if;
      v_price := coalesce(p_price,v_price);
    else
      if p_price is null or p_price < 0 then raise exception 'Select a package or enter a valid membership price'; end if;
      if p_duration_months is null or p_duration_months <= 0 then raise exception 'Enter the membership duration'; end if;
      v_price := p_price;
      v_duration := p_duration_months;
    end if;

    if p_membership_start_date is null or p_membership_end_date is null then
      raise exception 'Membership start date and end date are required';
    end if;
    if p_membership_end_date < p_membership_start_date then
      raise exception 'Membership end date cannot be before the start date';
    end if;
    if p_discount is null or p_discount < 0 then raise exception 'Discount cannot be negative'; end if;
    if p_amount_paid is null or p_amount_paid < 0 then raise exception 'Invalid amount paid'; end if;

    v_final := greatest(v_price-coalesce(p_discount,0),0);
    if p_amount_paid > v_final then raise exception 'Amount paid cannot exceed final amount'; end if;
    if p_membership_status not in ('active','cancelled') then raise exception 'Imported membership status must be Active or Cancelled'; end if;

    select timezone into v_tz from public.gyms where id=p_gym_id;
    if v_tz is null then raise exception 'Gym timezone is not configured'; end if;
    v_today := (now() at time zone v_tz)::date;

    if p_membership_status='cancelled' or p_status='cancelled' then
      v_membership_status := 'cancelled'::membership_status;
    elsif v_today > p_membership_end_date then
      if v_today <= p_membership_end_date + (select renewal_grace_days from public.gyms where id=p_gym_id) then
        v_membership_status := 'grace_period'::membership_status;
      else
        v_membership_status := 'did_not_renew'::membership_status;
      end if;
    elsif p_membership_end_date-v_today <= 10 then
      v_membership_status := 'expiring_soon'::membership_status;
    else
      v_membership_status := 'active'::membership_status;
    end if;

    insert into public.memberships(
      gym_id,member_id,package_id,membership_type,start_date,end_date,duration_months,
      price,discount,status,created_by
    )
    values(
      p_gym_id,v_member,p_package_id,'imported'::membership_type,p_membership_start_date,
      p_membership_end_date,v_duration,v_price,coalesce(p_discount,0),
      v_membership_status,private.current_app_user_id()
    )
    returning id into v_membership;

    if p_amount_paid > 0 then
      if nullif(trim(p_transaction_reference),'') is not null and exists(
        select 1 from public.payments
        where gym_id=p_gym_id and transaction_reference=trim(p_transaction_reference)
          and status not in ('refunded','reversed')
      ) then raise exception 'Transaction reference already exists'; end if;

      insert into public.payments(
        gym_id,member_id,membership_id,amount,payment_method,transaction_reference,notes,
        recorded_by,status,payment_date
      )
      values(
        p_gym_id,v_member,v_membership,p_amount_paid,p_payment_method,
        nullif(trim(p_transaction_reference),''),p_payment_notes,
        private.current_app_user_id(),'paid',
        (coalesce(p_payment_date,p_join_date)::timestamp at time zone v_tz)
      );
    end if;
  end if;

  return v_member;
end
$$;

revoke all on function public.create_old_member(
  uuid,text,text,text,date,text,text,text,text,text,date,public.member_status,uuid,boolean,boolean,uuid,
  date,date,public.membership_status,numeric,integer,numeric,numeric,public.payment_method,date,text,text
) from public;
grant execute on function public.create_old_member(
  uuid,text,text,text,date,text,text,text,text,text,date,public.member_status,uuid,boolean,boolean,uuid,
  date,date,public.membership_status,numeric,integer,numeric,numeric,public.payment_method,date,text,text
) to anon, authenticated;
