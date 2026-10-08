create or replace function public.create_member_registration_v2(
 p_gym_id uuid,p_name text,p_phone text,p_email text default null,p_dob date default null,p_gender text default null,p_address text default null,
 p_emergency_contact text default null,p_emergency_phone text default null,p_member_id text default null,p_package_id uuid default null,
 p_duration_months integer default null,p_join_date date default current_date,p_start_date date default current_date,p_price numeric default null,
 p_discount numeric default 0,p_amount_paid numeric default 0,p_payment_method public.payment_method default 'cash'::public.payment_method,
 p_transaction_reference text default null,p_payment_notes text default null,p_manual_end_date date default null,p_assigned_coach_id uuid default null,
 p_allow_duplicate_phone boolean default false
)
returns uuid language plpgsql security definer set search_path to 'public','private','pg_catalog'
as $function$
declare
 v_member uuid;v_mid text;v_price numeric;v_end date;v_membership uuid;v_final numeric;v_duration integer;v_admin boolean;v_unit text:='month';
begin
 if not private.has_permission(p_gym_id,'members.create') then raise exception 'Unauthorized'; end if;
 if length(trim(p_name))<2 then raise exception 'Please enter a valid member name'; end if;
 if p_phone !~ '^[0-9+][0-9 ()-]{7,19}$' then raise exception 'Please enter a valid mobile number'; end if;
 if p_amount_paid is null or p_amount_paid<0 then raise exception 'Invalid payment amount'; end if;
 if p_discount is null or p_discount<0 then raise exception 'Discount cannot be negative'; end if;
 if p_manual_end_date is not null then raise exception 'Manual membership end date is no longer supported; it is calculated from the start date and duration.'; end if;
 v_admin:=private.is_admin(p_gym_id);
 if p_allow_duplicate_phone and not v_admin then raise exception 'Only an admin can allow duplicate mobile numbers'; end if;
 v_mid:=case when p_member_id is null then private.generate_member_id(p_gym_id) else trim(p_member_id) end;
 if exists(select 1 from public.members where gym_id=p_gym_id and member_id=v_mid) then raise exception 'Member ID already exists'; end if;
 if exists(select 1 from public.members where gym_id=p_gym_id and phone=p_phone and not allow_duplicate_phone) and not p_allow_duplicate_phone then raise exception 'An existing member with this mobile number was found'; end if;
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
 v_end:=public.calculate_membership_end_by_unit(p_start_date,v_duration,v_unit);
 if v_end<p_start_date then raise exception 'Invalid membership dates'; end if;
 if p_assigned_coach_id is not null and not exists(select 1 from public.users where id=p_assigned_coach_id and gym_id=p_gym_id and status='active') then raise exception 'Invalid assigned coach'; end if;
 if nullif(trim(p_transaction_reference),'') is not null and exists(select 1 from public.payments where gym_id=p_gym_id and transaction_reference=trim(p_transaction_reference) and status not in('refunded','reversed')) then raise exception 'Transaction reference already exists'; end if;
 insert into public.members(gym_id,member_id,name,phone,email,dob,gender,address,emergency_contact,emergency_phone,created_by,join_date,assigned_coach_id,allow_duplicate_phone)
 values(p_gym_id,v_mid,trim(p_name),trim(p_phone),nullif(trim(p_email),''),p_dob,p_gender,p_address,p_emergency_contact,p_emergency_phone,private.current_app_user_id(),p_join_date,p_assigned_coach_id,p_allow_duplicate_phone)
 returning id into v_member;
 insert into public.memberships(gym_id,member_id,package_id,membership_type,start_date,end_date,duration_months,price,discount,created_by)
 values(p_gym_id,v_member,p_package_id,'new',p_start_date,v_end,v_duration,v_price,coalesce(p_discount,0),private.current_app_user_id())
 returning id into v_membership;
 if p_amount_paid>0 then
   insert into public.payments(gym_id,member_id,membership_id,amount,payment_method,transaction_reference,notes,recorded_by,status)
   values(p_gym_id,v_member,v_membership,p_amount_paid,p_payment_method,nullif(trim(p_transaction_reference),''),p_payment_notes,private.current_app_user_id(),'paid');
 end if;
 return v_member;
end
$function$;

create or replace function public.record_payment(
 p_gym_id uuid,p_member_id uuid,p_membership_id uuid,p_amount numeric,p_payment_method public.payment_method,
 p_transaction_reference text default null,p_payment_date timestamptz default now(),p_notes text default null
)
returns uuid language plpgsql security definer set search_path to 'public','private','pg_catalog'
as $function$
begin
 if not private.has_permission(p_gym_id,'payments.create') then raise exception 'Unauthorized'; end if;
 raise exception 'Please renew the membership first. The renewal screen will calculate the end date and automatically capture the payment.';
end
$function$;