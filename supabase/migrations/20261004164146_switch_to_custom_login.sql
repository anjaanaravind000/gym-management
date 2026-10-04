CREATE OR REPLACE FUNCTION private.audit_row_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
begin
 if tg_op='DELETE' then insert into audit_logs(gym_id,user_id,action,entity_type,entity_id,old_data) values(old.gym_id,private.current_app_user_id(),tg_op,tg_table_name,old.id,to_jsonb(old));return old;
 elsif tg_op='UPDATE' then insert into audit_logs(gym_id,user_id,action,entity_type,entity_id,old_data,new_data) values(new.gym_id,private.current_app_user_id(),tg_op,tg_table_name,new.id,to_jsonb(old),to_jsonb(new));return new;
 else insert into audit_logs(gym_id,user_id,action,entity_type,entity_id,new_data) values(new.gym_id,private.current_app_user_id(),tg_op,tg_table_name,new.id,to_jsonb(new));return new;end if;
end $function$;

CREATE OR REPLACE FUNCTION private.bootstrap_gym(p_gym_name text, p_user_name text, p_email text DEFAULT NULL::text, p_phone text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare v_gym uuid;v_uid uuid:=private.current_app_user_id();
begin
 if v_uid is null then raise exception 'Authentication required';end if;
 if exists(select 1 from public.users where id=v_uid) then raise exception 'User already belongs to a gym';end if;
 insert into public.gyms(name,email,phone) values(trim(p_gym_name),nullif(trim(p_email),''),nullif(trim(p_phone),'')) returning id into v_gym;
 insert into public.users(id,gym_id,name,email,phone,role) values(v_uid,v_gym,trim(p_user_name),nullif(trim(p_email),''),nullif(trim(p_phone),''),'admin');
 insert into public.gym_settings(gym_id) values(v_gym);
 insert into public.payment_method_settings(gym_id,payment_method) select v_gym,x from unnest(enum_range(null::public.payment_method)) x;
 insert into public.membership_packages(gym_id,name,duration_months,duration_unit,price,description,display_order)
 values(v_gym,'1 Month',1,'month',1000,'Default monthly plan',1),(v_gym,'3 Months',3,'month',2700,'Default quarterly plan',2),
 (v_gym,'6 Months',6,'month',5000,'Default half-year plan',3),(v_gym,'12 Months',12,'month',9000,'Default annual plan',4);
 insert into public.notification_templates(gym_id,notification_type,channel,subject,body,enabled)
 values(v_gym,'expiry_10_days','in_app','Membership expiring','{Member Name} expires in 10 days on {Expiry Date}.',true),
 (v_gym,'expiry_10_days','whatsapp',null,'Hi {Member Name}, your membership at {Gym Name} will expire in 10 days on {Expiry Date}. Please renew your membership.',true),
 (v_gym,'expiry_5_days','in_app','Membership expiring','{Member Name} expires in 5 days on {Expiry Date}.',true),
 (v_gym,'expiry_5_days','whatsapp',null,'Hi {Member Name}, your membership at {Gym Name} will expire in 5 days on {Expiry Date}. Please renew your membership soon.',true),
 (v_gym,'expiry_today','in_app','Membership expires today','{Member Name} membership expires today.',true),
 (v_gym,'expiry_today','whatsapp',null,'Hi {Member Name}, your membership at {Gym Name} expires today. Please contact us for renewal details.',true),
 (v_gym,'payment_pending','in_app','Payment pending','{Member Name} has an outstanding balance of {Amount Due}.',true),
 (v_gym,'payment_received','in_app','Payment received','Payment received from {Member Name}.',true),
 (v_gym,'membership_renewed','in_app','Membership renewed','{Member Name} renewed their membership.',true),
 (v_gym,'new_member','in_app','New member','{Member Name} was added to the gym.',true);
 return v_gym;
end $function$;

CREATE OR REPLACE FUNCTION private.has_permission(p_gym_id uuid, p_permission permission_key)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$ select exists(select 1 from public.users u where u.id=(select private.current_app_user_id()) and u.gym_id=p_gym_id and u.status='active' and(u.role='admin' or exists(select 1 from public.user_permissions up where up.user_id=u.id and up.permission=p_permission and up.allowed=true))) $function$;

CREATE OR REPLACE FUNCTION private.is_admin(p_gym_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$ select exists(select 1 from public.users where id=(select private.current_app_user_id()) and gym_id=p_gym_id and role='admin' and status='active') $function$;

CREATE OR REPLACE FUNCTION private.user_gym_ids()
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$ select gym_id from public.users where id=(select private.current_app_user_id()) and status='active' $function$;

CREATE OR REPLACE FUNCTION public.bootstrap_gym(p_gym_name text, p_user_name text, p_email text DEFAULT NULL::text, p_phone text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public', 'private', 'pg_catalog'
AS $function$
begin
 return private.bootstrap_gym(p_gym_name,p_user_name,p_email,p_phone);
end
$function$;

CREATE OR REPLACE FUNCTION public.cancel_membership(p_gym_id uuid, p_membership_id uuid, p_cancellation_date date, p_reason text, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public', 'private', 'pg_catalog'
AS $function$
declare v_id uuid;
begin
 if not private.has_permission(p_gym_id,'cancellations.manage') then raise exception 'Unauthorized';end if;
 if nullif(trim(p_reason),'') is null then raise exception 'Cancellation reason is required';end if;
 if not exists(select 1 from public.memberships where id=p_membership_id and gym_id=p_gym_id) then raise exception 'Membership not found';end if;
 update public.memberships set status='cancelled'::membership_status where id=p_membership_id and status<>'renewed';
 insert into public.membership_cancellations(gym_id,membership_id,cancellation_date,reason,notes,cancelled_by)
 values(p_gym_id,p_membership_id,p_cancellation_date,trim(p_reason),p_notes,private.current_app_user_id()) returning id into v_id;
 return v_id;
end $function$;

CREATE OR REPLACE FUNCTION public.create_member_registration(p_gym_id uuid, p_name text, p_phone text, p_email text DEFAULT NULL::text, p_dob date DEFAULT NULL::date, p_gender text DEFAULT NULL::text, p_address text DEFAULT NULL::text, p_emergency_contact text DEFAULT NULL::text, p_emergency_phone text DEFAULT NULL::text, p_member_id text DEFAULT NULL::text, p_package_id uuid DEFAULT NULL::uuid, p_duration_months integer DEFAULT NULL::integer, p_start_date date DEFAULT CURRENT_DATE, p_price numeric DEFAULT NULL::numeric, p_discount numeric DEFAULT 0, p_amount_paid numeric DEFAULT 0, p_payment_method payment_method DEFAULT 'cash'::payment_method, p_transaction_reference text DEFAULT NULL::text, p_payment_notes text DEFAULT NULL::text, p_manual_end_date date DEFAULT NULL::date)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare v_member_id uuid;v_mid text;v_price numeric;v_end date;v_membership uuid;v_final numeric;v_duration integer;
begin
 if not private.has_permission(p_gym_id,'members.create') then raise exception 'Unauthorized';end if;
 if p_amount_paid<0 then raise exception 'Invalid payment amount';end if;
 if p_member_id is null then v_mid:=private.generate_member_id(p_gym_id);else v_mid:=p_member_id;end if;
 if exists(select 1 from members where gym_id=p_gym_id and member_id=v_mid) then raise exception 'Member ID already exists';end if;
 if p_package_id is not null then
  select price,duration_months into v_price,v_duration from membership_packages where id=p_package_id and gym_id=p_gym_id and status='active';
  if not found then raise exception 'Invalid package';end if;
 else
  v_price:=coalesce(p_price,0);v_duration:=p_duration_months;if v_duration is null or v_duration<=0 then raise exception 'Duration is required';end if;
 end if;
 v_duration:=coalesce(p_duration_months,v_duration);v_price:=coalesce(p_price,v_price);v_final:=greatest(v_price-coalesce(p_discount,0),0);
 if p_amount_paid>v_final then raise exception 'Amount paid cannot exceed final amount';end if;
 v_end:=coalesce(p_manual_end_date,public.calculate_membership_end(p_start_date,v_duration));if v_end<p_start_date then raise exception 'Invalid membership dates';end if;
 insert into members(gym_id,member_id,name,phone,email,dob,gender,address,emergency_contact,emergency_phone,created_by) values(p_gym_id,v_mid,p_name,p_phone,p_email,p_dob,p_gender,p_address,p_emergency_contact,p_emergency_phone,private.current_app_user_id()) returning id into v_member_id;
 insert into memberships(gym_id,member_id,package_id,membership_type,start_date,end_date,duration_months,price,discount,created_by) values(p_gym_id,v_member_id,p_package_id,'new',p_start_date,v_end,v_duration,v_price,p_discount,private.current_app_user_id()) returning id into v_membership;
 if p_amount_paid>0 then insert into payments(gym_id,member_id,membership_id,amount,payment_method,transaction_reference,notes,recorded_by,status) values(p_gym_id,v_member_id,v_membership,p_amount_paid,p_payment_method,p_transaction_reference,p_payment_notes,private.current_app_user_id(),'paid');end if;
 return v_member_id;
end $function$;

CREATE OR REPLACE FUNCTION public.create_member_registration_v2(p_gym_id uuid, p_name text, p_phone text, p_email text DEFAULT NULL::text, p_dob date DEFAULT NULL::date, p_gender text DEFAULT NULL::text, p_address text DEFAULT NULL::text, p_emergency_contact text DEFAULT NULL::text, p_emergency_phone text DEFAULT NULL::text, p_member_id text DEFAULT NULL::text, p_package_id uuid DEFAULT NULL::uuid, p_duration_months integer DEFAULT NULL::integer, p_join_date date DEFAULT CURRENT_DATE, p_start_date date DEFAULT CURRENT_DATE, p_price numeric DEFAULT NULL::numeric, p_discount numeric DEFAULT 0, p_amount_paid numeric DEFAULT 0, p_payment_method payment_method DEFAULT 'cash'::payment_method, p_transaction_reference text DEFAULT NULL::text, p_payment_notes text DEFAULT NULL::text, p_manual_end_date date DEFAULT NULL::date, p_assigned_coach_id uuid DEFAULT NULL::uuid, p_allow_duplicate_phone boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public', 'private', 'pg_catalog'
AS $function$
declare v_member uuid;v_mid text;v_price numeric;v_end date;v_membership uuid;v_final numeric;v_duration integer;v_admin boolean;
begin
 if not private.has_permission(p_gym_id,'members.create') then raise exception 'Unauthorized';end if;
 if length(trim(p_name))<2 then raise exception 'Please enter a valid member name';end if;
 if p_phone !~ '^[0-9+][0-9 ()-]{7,19}$' then raise exception 'Please enter a valid mobile number';end if;
 if p_amount_paid<0 then raise exception 'Invalid payment amount';end if;
 v_admin:=private.is_admin(p_gym_id);
 if p_manual_end_date is not null and not v_admin then raise exception 'Only an admin can override the membership end date';end if;
 if p_allow_duplicate_phone and not v_admin then raise exception 'Only an admin can allow duplicate mobile numbers';end if;
 v_mid:=case when p_member_id is null then private.generate_member_id(p_gym_id) else trim(p_member_id) end;
 if exists(select 1 from public.members where gym_id=p_gym_id and member_id=v_mid) then raise exception 'Member ID already exists';end if;
 if exists(select 1 from public.members where gym_id=p_gym_id and phone=p_phone and not allow_duplicate_phone) and not p_allow_duplicate_phone then raise exception 'An existing member with this mobile number was found';end if;
 if p_package_id is not null then
  select price,duration_months into v_price,v_duration from public.membership_packages where id=p_package_id and gym_id=p_gym_id and status='active';
  if not found then raise exception 'Invalid package';end if;
 else v_price:=coalesce(p_price,0);v_duration:=p_duration_months;end if;
 if v_duration is null or v_duration<=0 then raise exception 'Duration is required';end if;
 v_price:=coalesce(p_price,v_price);v_final:=greatest(v_price-coalesce(p_discount,0),0);
 if p_amount_paid>v_final then raise exception 'Amount paid cannot exceed final amount';end if;
 v_end:=coalesce(p_manual_end_date,public.calculate_membership_end(p_start_date,v_duration));if v_end<p_start_date then raise exception 'Invalid membership dates';end if;
 if p_assigned_coach_id is not null and not exists(select 1 from public.users where id=p_assigned_coach_id and gym_id=p_gym_id and status='active') then raise exception 'Invalid assigned coach';end if;
 if nullif(trim(p_transaction_reference),'') is not null and exists(select 1 from public.payments where gym_id=p_gym_id and transaction_reference=trim(p_transaction_reference) and status not in('refunded','reversed')) then raise exception 'Transaction reference already exists';end if;
 insert into public.members(gym_id,member_id,name,phone,email,dob,gender,address,emergency_contact,emergency_phone,created_by,join_date,assigned_coach_id,allow_duplicate_phone)
 values(p_gym_id,v_mid,trim(p_name),trim(p_phone),nullif(trim(p_email),''),p_dob,p_gender,p_address,p_emergency_contact,p_emergency_phone,private.current_app_user_id(),p_join_date,p_assigned_coach_id,p_allow_duplicate_phone)
 returning id into v_member;
 insert into public.memberships(gym_id,member_id,package_id,membership_type,start_date,end_date,duration_months,price,discount,final_amount,created_by)
 values(p_gym_id,v_member,p_package_id,'new',p_start_date,v_end,v_duration,v_price,coalesce(p_discount,0),v_final,private.current_app_user_id())
 returning id into v_membership;
 if p_amount_paid>0 then insert into public.payments(gym_id,member_id,membership_id,amount,payment_method,transaction_reference,notes,recorded_by,status)
 values(p_gym_id,v_member,v_membership,p_amount_paid,p_payment_method,nullif(trim(p_transaction_reference),''),p_payment_notes,private.current_app_user_id(),'paid');end if;
 return v_member;
end $function$;

CREATE OR REPLACE FUNCTION public.create_renewal(p_gym_id uuid, p_member_id uuid, p_package_id uuid DEFAULT NULL::uuid, p_duration_months integer DEFAULT NULL::integer, p_start_date date DEFAULT NULL::date, p_price numeric DEFAULT NULL::numeric, p_discount numeric DEFAULT 0, p_amount_paid numeric DEFAULT 0, p_payment_method payment_method DEFAULT 'cash'::payment_method, p_transaction_reference text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_end_date date DEFAULT NULL::date)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public', 'private', 'pg_catalog'
AS $function$
declare v_old memberships%rowtype;v_new uuid;v_price numeric;v_duration integer;v_start date;v_end date;v_final numeric;
begin
 if not private.has_permission(p_gym_id,'members.renew') then raise exception 'Unauthorized';end if;
 if p_end_date is not null and not private.is_admin(p_gym_id) then raise exception 'Only an admin can override the renewal end date';end if;
 select * into v_old from public.memberships where id=(select id from public.memberships where member_id=p_member_id and gym_id=p_gym_id order by end_date desc,created_at desc limit 1) for update;
 if not found then raise exception 'No previous membership found';end if;
 if v_old.status='cancelled' then raise exception 'Cancelled memberships cannot be renewed';end if;
 if p_package_id is not null then
  select price,duration_months into v_price,v_duration from public.membership_packages where id=p_package_id and gym_id=p_gym_id and status='active';
  if not found then raise exception 'Invalid package';end if;
 else v_price:=coalesce(p_price,0);v_duration:=p_duration_months;end if;
 if v_duration is null or v_duration<=0 then raise exception 'Duration is required';end if;
 v_price:=coalesce(p_price,v_price);v_start:=coalesce(p_start_date,greatest(current_date,v_old.end_date+1));v_end:=coalesce(p_end_date,public.calculate_membership_end(v_start,v_duration));v_final:=greatest(v_price-coalesce(p_discount,0),0);
 if p_amount_paid<0 or p_amount_paid>v_final then raise exception 'Invalid amount paid';end if;
 if nullif(trim(p_transaction_reference),'') is not null and exists(select 1 from public.payments where gym_id=p_gym_id and transaction_reference=trim(p_transaction_reference) and status not in('refunded','reversed')) then raise exception 'Transaction reference already exists';end if;
 update public.memberships set status='renewed' where id=v_old.id;
 insert into public.memberships(gym_id,member_id,package_id,membership_type,start_date,end_date,duration_months,price,discount,final_amount,status,previous_membership_id,created_by)
 values(p_gym_id,p_member_id,p_package_id,'renewal',v_start,v_end,v_duration,v_price,coalesce(p_discount,0),v_final,'active',v_old.id,private.current_app_user_id()) returning id into v_new;
 if p_amount_paid>0 then insert into public.payments(gym_id,member_id,membership_id,amount,payment_method,transaction_reference,notes,recorded_by,status)
 values(p_gym_id,p_member_id,v_new,p_amount_paid,p_payment_method,nullif(trim(p_transaction_reference),''),p_notes,private.current_app_user_id(),'paid');end if;
 return v_new;
end $function$;

CREATE OR REPLACE FUNCTION public.freeze_membership(p_gym_id uuid, p_membership_id uuid, p_start_date date, p_end_date date, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public', 'private', 'pg_catalog'
AS $function$
declare v_m public.memberships%rowtype;v_id uuid;v_days integer;
begin
 if not private.has_permission(p_gym_id,'freezes.manage') then raise exception 'Unauthorized';end if;
 if p_end_date<p_start_date then raise exception 'Invalid freeze dates';end if;
 if nullif(trim(p_reason),'') is null then raise exception 'Freeze reason is required';end if;
 select * into v_m from public.memberships where id=p_membership_id and gym_id=p_gym_id for update;
 if not found then raise exception 'Membership not found';end if;
 if v_m.status in('cancelled','renewed') then raise exception 'Membership cannot be frozen';end if;
 v_days:=p_end_date-p_start_date+1;
 insert into public.membership_freezes(gym_id,membership_id,start_date,end_date,reason,created_by)
 values(p_gym_id,p_membership_id,p_start_date,p_end_date,trim(p_reason),private.current_app_user_id()) returning id into v_id;
 update public.memberships set end_date=end_date+v_days,status='frozen'::membership_status where id=p_membership_id;
 return v_id;
end $function$;

CREATE OR REPLACE FUNCTION public.record_payment(p_gym_id uuid, p_member_id uuid, p_membership_id uuid, p_amount numeric, p_payment_method payment_method, p_transaction_reference text DEFAULT NULL::text, p_payment_date timestamp with time zone DEFAULT now(), p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public', 'private', 'pg_catalog'
AS $function$
declare v_id uuid;
begin
 if not private.has_permission(p_gym_id,'payments.create') then raise exception 'Unauthorized';end if;
 if p_amount<=0 then raise exception 'Payment amount must be greater than zero';end if;
 if not exists(select 1 from public.memberships where id=p_membership_id and member_id=p_member_id and gym_id=p_gym_id) then raise exception 'Invalid membership';end if;
 if nullif(trim(p_transaction_reference),'') is not null and exists(select 1 from public.payments where gym_id=p_gym_id and transaction_reference=trim(p_transaction_reference) and status not in('refunded','reversed')) then raise exception 'Transaction reference already exists';end if;
 insert into public.payments(gym_id,member_id,membership_id,amount,payment_method,transaction_reference,payment_date,notes,recorded_by,status)
 values(p_gym_id,p_member_id,p_membership_id,p_amount,p_payment_method,nullif(trim(p_transaction_reference),''),p_payment_date,p_notes,private.current_app_user_id(),'paid')
 returning id into v_id;
 return v_id;
end $function$;

CREATE OR REPLACE FUNCTION public.refund_payment(p_gym_id uuid, p_payment_id uuid, p_amount numeric, p_reason text, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public', 'private', 'pg_catalog'
AS $function$
declare v_payment public.payments%rowtype;v_refunded numeric;v_id uuid;
begin
 if not private.has_permission(p_gym_id,'payments.refund') then raise exception 'Unauthorized';end if;
 if p_amount<=0 then raise exception 'Refund amount must be greater than zero';end if;
 if nullif(trim(p_reason),'') is null then raise exception 'Refund reason is required';end if;
 select * into v_payment from public.payments where id=p_payment_id and gym_id=p_gym_id for update;
 if not found then raise exception 'Payment not found';end if;
 select coalesce(sum(amount),0) into v_refunded from public.refunds where payment_id=p_payment_id;
 if v_refunded+p_amount>v_payment.amount then raise exception 'Refund exceeds original payment amount';end if;
 insert into public.refunds(gym_id,payment_id,amount,reason,authorized_by,notes)
 values(p_gym_id,p_payment_id,p_amount,trim(p_reason),private.current_app_user_id(),p_notes) returning id into v_id;
 if v_refunded+p_amount>=v_payment.amount then update public.payments set status='refunded'::payment_status where id=p_payment_id;end if;
 return v_id;
end $function$;

CREATE OR REPLACE FUNCTION public.set_staff_role(p_gym_id uuid, p_user_id uuid, p_role user_role, p_status text DEFAULT 'active'::text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public', 'private', 'pg_catalog'
AS $function$
begin
 if not private.has_permission(p_gym_id,'staff.manage') then raise exception 'Unauthorized';end if;
 if p_user_id=private.current_app_user_id() and p_role<>'admin' then raise exception 'You cannot remove your own admin role';end if;
 update public.users set role=p_role,status=p_status,updated_at=now() where id=p_user_id and gym_id=p_gym_id;
 if not found then raise exception 'Staff member not found';end if;
end $function$;

update public.login_accounts
set id = (select id from auth.users where lower(email)='admin@gmail.com' limit 1)
where lower(username)='admin'
  and exists(select 1 from auth.users where lower(email)='admin@gmail.com');

do $$
declare p record;
begin
  for p in
    select schemaname,tablename,policyname
    from pg_policies
    where schemaname='public' and 'authenticated'=any(roles)
  loop
    execute format('alter policy %I on %I.%I to anon, authenticated',p.policyname,p.schemaname,p.tablename);
  end loop;
end
$$;