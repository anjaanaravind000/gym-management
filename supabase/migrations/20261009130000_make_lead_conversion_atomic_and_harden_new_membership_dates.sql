-- Prevent future-start memberships with no pending status, derive status using the gym's timezone,
-- and make CRM lead conversion plus member registration a single transaction.

create or replace function public.create_member_registration_v2(
 p_gym_id uuid,p_name text,p_phone text,p_email text default null,p_dob date default null,p_gender text default null,p_address text default null,
 p_emergency_contact text default null,p_emergency_phone text default null,p_member_id text default null,p_package_id uuid default null,
 p_duration_months integer default null,p_join_date date default current_date,p_start_date date default current_date,p_price numeric default null,
 p_discount numeric default 0,p_amount_paid numeric default 0,p_payment_method public.payment_method default 'cash',
 p_transaction_reference text default null,p_payment_notes text default null,p_manual_end_date date default null,p_assigned_coach_id uuid default null,
 p_allow_duplicate_phone boolean default false
)
returns uuid language plpgsql security definer
set search_path to 'public','private','pg_catalog'
as $$
declare
 v_member uuid;v_mid text;v_phone text:=private.normalize_member_phone(p_phone);v_price numeric;v_end date;v_membership uuid;
 v_final numeric;v_duration integer;v_admin boolean;v_unit text:='month';v_constraint text;v_tz text;v_today date;v_end_status public.membership_status;
begin
 if not private.has_permission(p_gym_id,'members.create') then raise exception 'Unauthorized'; end if;
 if length(trim(p_name))<2 then raise exception 'Please enter a valid member name'; end if;
 if length(v_phone)<8 or length(v_phone)>20 then raise exception 'Please enter a valid mobile number'; end if;
 select timezone into v_tz from public.gyms where id=p_gym_id;
 if v_tz is null then raise exception 'Gym timezone is not configured'; end if;
 v_today:=(now() at time zone v_tz)::date;
 if p_join_date is null or p_join_date>v_today then raise exception 'Joining date cannot be in the future'; end if;
 if p_start_date is null or p_start_date<p_join_date then raise exception 'Membership start date cannot be before joining date'; end if;
 if p_start_date>v_today then raise exception 'Membership start date cannot be in the future'; end if;
 if p_amount_paid is null or p_amount_paid<0 then raise exception 'Invalid payment amount'; end if;
 if p_discount is null or p_discount<0 then raise exception 'Discount cannot be negative'; end if;
 if p_manual_end_date is not null then raise exception 'Manual membership end date is no longer supported; it is calculated from the start date and duration.'; end if;
 v_admin:=private.is_admin(p_gym_id);
 if p_allow_duplicate_phone and not v_admin then raise exception 'Only an admin can allow duplicate mobile numbers'; end if;
 v_mid:=case when nullif(trim(p_member_id),'') is null then private.generate_member_id(p_gym_id) else trim(p_member_id) end;
 if exists(select 1 from public.members where gym_id=p_gym_id and member_id=v_mid) then raise exception 'Member ID already exists'; end if;
 if not p_allow_duplicate_phone and exists(select 1 from public.members where gym_id=p_gym_id and phone=v_phone and not allow_duplicate_phone) then raise exception 'An existing member with this mobile number was found'; end if;
 if p_package_id is not null then
   select price,duration_months,duration_unit into v_price,v_duration,v_unit from public.membership_packages where id=p_package_id and gym_id=p_gym_id and status='active';
   if not found then raise exception 'Invalid package'; end if;
 else
   if p_price is null or p_price<0 then raise exception 'Valid custom price is required'; end if;
   v_price:=p_price;v_duration:=p_duration_months;v_unit:='month';
 end if;
 if v_duration is null or v_duration<=0 then raise exception 'Duration is required'; end if;
 v_final:=greatest(v_price-coalesce(p_discount,0),0);
 if p_amount_paid>v_final then raise exception 'Amount paid cannot exceed final amount'; end if;
 if p_amount_paid>0 and not exists(select 1 from public.payment_method_settings where gym_id=p_gym_id and payment_method=p_payment_method and enabled) then raise exception 'Selected payment method is disabled'; end if;
 if nullif(trim(p_transaction_reference),'') is not null and exists(select 1 from public.payments where gym_id=p_gym_id and transaction_reference=trim(p_transaction_reference) and status not in('refunded','reversed')) then raise exception 'Transaction reference already exists'; end if;
 v_end:=public.calculate_membership_end_by_unit(p_start_date,v_duration,v_unit);
 if v_end<p_start_date then raise exception 'Invalid membership dates'; end if;
 if v_end<v_today then
   if v_today<=v_end+(select renewal_grace_days from public.gyms where id=p_gym_id) then v_end_status:='grace_period';
   else v_end_status:='did_not_renew'; end if;
 elsif v_end-v_today<=10 then v_end_status:='expiring_soon';
 else v_end_status:='active'; end if;
 if p_assigned_coach_id is not null and not exists(select 1 from public.users where id=p_assigned_coach_id and gym_id=p_gym_id and status='active') then raise exception 'Invalid assigned coach'; end if;
 begin
   insert into public.members(gym_id,member_id,name,phone,email,dob,gender,address,emergency_contact,emergency_phone,created_by,join_date,assigned_coach_id,allow_duplicate_phone)
   values(p_gym_id,v_mid,trim(p_name),v_phone,nullif(trim(p_email),''),p_dob,p_gender,p_address,p_emergency_contact,p_emergency_phone,private.current_app_user_id(),p_join_date,p_assigned_coach_id,p_allow_duplicate_phone)
   returning id into v_member;
 exception when unique_violation then
   get stacked diagnostics v_constraint=constraint_name;
   if v_constraint='members_gym_phone_unique' then raise exception 'An existing member with this mobile number was found';
   elsif v_constraint='members_gym_id_member_id_key' then raise exception 'Member ID already exists'; end if;
   raise;
 end;
 insert into public.memberships(gym_id,member_id,package_id,membership_type,start_date,end_date,duration_months,price,discount,status,created_by)
 values(p_gym_id,v_member,p_package_id,'new',p_start_date,v_end,v_duration,v_price,coalesce(p_discount,0),v_end_status,private.current_app_user_id())
 returning id into v_membership;
 if p_amount_paid>0 then
   insert into public.payments(gym_id,member_id,membership_id,amount,payment_method,transaction_reference,notes,recorded_by,status)
   values(p_gym_id,v_member,v_membership,p_amount_paid,p_payment_method,nullif(trim(p_transaction_reference),''),p_payment_notes,private.current_app_user_id(),'paid');
 end if;
 return v_member;
end
$$;

create or replace function public.create_member_from_lead(
 p_gym_id uuid,p_lead_id uuid,p_name text,p_phone text,p_email text,p_dob date,p_gender text,p_address text,
 p_emergency_contact text,p_emergency_phone text,p_member_id text,p_package_id uuid,p_duration_months integer,
 p_join_date date,p_start_date date,p_price numeric,p_discount numeric,p_amount_paid numeric,p_payment_method public.payment_method,
 p_transaction_reference text,p_payment_notes text,p_assigned_coach_id uuid,p_allow_duplicate_phone boolean
)
returns uuid language plpgsql security definer
set search_path to 'public','private','pg_catalog'
as $$
declare v_lead_status text;v_converted uuid;v_member uuid;
begin
 if not private.has_permission(p_gym_id,'leads.manage') then raise exception 'Unauthorized'; end if;
 select status,converted_member_id into v_lead_status,v_converted from public.leads
 where id=p_lead_id and gym_id=p_gym_id for update;
 if not found then raise exception 'Lead not found'; end if;
 if v_lead_status in ('won','lost') or v_converted is not null then raise exception 'Lead is already closed'; end if;
 v_member:=public.create_member_registration_v2(
   p_gym_id=>p_gym_id,p_name=>p_name,p_phone=>p_phone,p_email=>p_email,p_dob=>p_dob,p_gender=>p_gender,p_address=>p_address,
   p_emergency_contact=>p_emergency_contact,p_emergency_phone=>p_emergency_phone,p_member_id=>p_member_id,p_package_id=>p_package_id,
   p_duration_months=>p_duration_months,p_join_date=>p_join_date,p_start_date=>p_start_date,p_price=>p_price,p_discount=>p_discount,
   p_amount_paid=>p_amount_paid,p_payment_method=>p_payment_method,p_transaction_reference=>p_transaction_reference,
   p_payment_notes=>p_payment_notes,p_manual_end_date=>null,p_assigned_coach_id=>p_assigned_coach_id,p_allow_duplicate_phone=>p_allow_duplicate_phone
 );
 update public.leads set status='won',converted_member_id=v_member,updated_at=now()
 where id=p_lead_id and gym_id=p_gym_id and status not in ('won','lost') and converted_member_id is null;
 if not found then raise exception 'Lead was closed while conversion was in progress'; end if;
 return v_member;
end
$$;
revoke all on function public.create_member_from_lead(uuid,uuid,text,text,text,date,text,text,text,text,text,uuid,integer,date,date,numeric,numeric,numeric,public.payment_method,text,text,uuid,boolean) from public;
grant execute on function public.create_member_from_lead(uuid,uuid,text,text,text,date,date,text,text,text,text,text,uuid,integer,date,date,numeric,numeric,numeric,public.payment_method,text,text,uuid,boolean) to anon,authenticated;
