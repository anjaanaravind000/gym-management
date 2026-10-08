-- Full audit hardening. Safe to replay after the existing 2026-10-09 migrations.

alter table private.whatsapp_connections add column if not exists meta_app_secret text;
create index if not exists class_sessions_created_by_idx on public.class_sessions(created_by);


create or replace function private.normalize_member_phone(p_phone text)
returns text language sql immutable
set search_path to 'private','pg_catalog'
as $$ select regexp_replace(trim(coalesce(p_phone,'')),'[^0-9]','','g') $$;

create or replace function private.canonicalize_member_phone()
returns trigger language plpgsql
set search_path to 'public','private','pg_catalog'
as $$
declare v_phone text;
begin
 v_phone:=private.normalize_member_phone(new.phone);
 if length(v_phone)<8 or length(v_phone)>20 then raise exception 'Please enter a valid mobile number'; end if;
 new.phone:=v_phone;
 return new;
end
$$;
drop trigger if exists members_canonical_phone on public.members;
create trigger members_canonical_phone before insert or update of phone on public.members
for each row execute function private.canonicalize_member_phone();
update public.members set phone=private.normalize_member_phone(phone)
where phone<>private.normalize_member_phone(phone);

create or replace function public.record_attendance(p_gym_id uuid,p_member_id uuid,p_method text default 'manual')
returns uuid language plpgsql security definer
set search_path to 'public','private','pg_catalog'
as $$
declare v_id uuid;v_status membership_status;v_end date;v_tz text;v_today date;v_member_status member_status;
begin
 if not private.has_permission(p_gym_id,'attendance.manage') then raise exception 'Unauthorized'; end if;
 select status into v_member_status from public.members where id=p_member_id and gym_id=p_gym_id;
 if v_member_status is null then raise exception 'Member not found'; end if;
 if v_member_status<>'active' then raise exception 'Only active members can check in'; end if;
 select g.timezone into v_tz from public.gyms g where g.id=p_gym_id;
 if v_tz is null then raise exception 'Gym timezone is not configured'; end if;
 v_today:=(now() at time zone v_tz)::date;
 select status,end_date into v_status,v_end from public.memberships
 where member_id=p_member_id and gym_id=p_gym_id
 order by created_at desc,end_date desc limit 1;
 if v_status is null then raise exception 'Active membership required'; end if;
 if v_end<v_today or v_status not in('active','expiring_soon','grace_period') then raise exception 'Member is not currently eligible for attendance'; end if;
 insert into public.attendance(gym_id,member_id,method)
 values(p_gym_id,p_member_id,coalesce(nullif(trim(p_method),''),'manual'))
 returning id into v_id;
 return v_id;
exception when unique_violation then raise exception 'Member is already checked in';
end
$$;

create or replace function public.freeze_membership(p_gym_id uuid,p_membership_id uuid,p_start_date date,p_end_date date,p_reason text)
returns uuid language plpgsql security definer
set search_path to 'public','private','pg_catalog'
as $$
declare v_m public.memberships%rowtype;v_id uuid;v_days integer;v_tz text;v_today date;
begin
 if not private.has_permission(p_gym_id,'freezes.manage') then raise exception 'Unauthorized'; end if;
 select timezone into v_tz from public.gyms where id=p_gym_id;if v_tz is null then raise exception 'Gym timezone is not configured';end if;
 v_today:=(now() at time zone v_tz)::date;
 if p_start_date is null or p_end_date is null or p_end_date<p_start_date then raise exception 'Invalid freeze dates'; end if;
 if p_start_date<v_today then raise exception 'Freeze cannot start in the past'; end if;
 if nullif(trim(p_reason),'') is null then raise exception 'Freeze reason is required'; end if;
 select * into v_m from public.memberships where id=p_membership_id and gym_id=p_gym_id for update;
 if not found then raise exception 'Membership not found'; end if;
 if v_m.status not in('active','expiring_soon','grace_period') then raise exception 'Only active memberships can be frozen'; end if;
 if p_start_date>v_m.end_date then raise exception 'Freeze must start on or before the membership end date'; end if;
 if exists(select 1 from public.membership_freezes f where f.membership_id=p_membership_id and daterange(f.start_date,f.end_date,'[]') && daterange(p_start_date,p_end_date,'[]')) then raise exception 'Freeze dates overlap an existing freeze'; end if;
 v_days:=p_end_date-p_start_date+1;
 insert into public.membership_freezes(gym_id,membership_id,start_date,end_date,reason,created_by)
 values(p_gym_id,p_membership_id,p_start_date,p_end_date,trim(p_reason),private.current_app_user_id()) returning id into v_id;
 update public.memberships set end_date=end_date+v_days,status='frozen' where id=p_membership_id;
 return v_id;
end
$$;

create or replace function public.unfreeze_membership(p_gym_id uuid,p_membership_id uuid)
returns void language plpgsql security definer
set search_path to 'public','private','pg_catalog'
as $$
declare v_freeze public.membership_freezes%rowtype;v_unused_days integer;v_tz text;v_today date;
begin
 if not private.has_permission(p_gym_id,'freezes.manage') then raise exception 'Unauthorized'; end if;
 select timezone into v_tz from public.gyms where id=p_gym_id;if v_tz is null then raise exception 'Gym timezone is not configured';end if;
 v_today:=(now() at time zone v_tz)::date;
 select * into v_freeze from public.membership_freezes
 where membership_id=p_membership_id and gym_id=p_gym_id and start_date<=v_today and end_date>=v_today
 order by start_date desc,created_at desc limit 1 for update;
 if not found then raise exception 'No active freeze found'; end if;
 v_unused_days:=greatest(v_freeze.end_date-v_today+1,0);
 update public.membership_freezes set end_date=v_today-1,updated_at=now() where id=v_freeze.id;
 if v_unused_days>0 then
   update public.memberships set end_date=end_date-v_unused_days where id=p_membership_id and gym_id=p_gym_id;
   if not found then raise exception 'Membership not found'; end if;
 end if;
 perform public.sync_membership_statuses();
end
$$;

create or replace function public.cancel_membership(p_gym_id uuid,p_membership_id uuid,p_cancellation_date date,p_reason text,p_notes text default null)
returns uuid language plpgsql security definer
set search_path to 'public','private','pg_catalog'
as $$
declare v_id uuid;v_m public.memberships%rowtype;v_tz text;v_today date;
begin
 if not private.has_permission(p_gym_id,'cancellations.manage') then raise exception 'Unauthorized'; end if;
 if nullif(trim(p_reason),'') is null then raise exception 'Cancellation reason is required'; end if;
 select timezone into v_tz from public.gyms where id=p_gym_id;if v_tz is null then raise exception 'Gym timezone is not configured';end if;
 v_today:=(now() at time zone v_tz)::date;
 select * into v_m from public.memberships where id=p_membership_id and gym_id=p_gym_id for update;
 if not found then raise exception 'Membership not found'; end if;
 if p_cancellation_date is null or p_cancellation_date<v_m.start_date or p_cancellation_date>v_today then raise exception 'Cancellation date must be between the membership start date and today'; end if;
 if v_m.status in('cancelled','renewed') then raise exception 'Membership is already closed'; end if;
 if v_m.status not in('active','expiring_soon','grace_period','frozen','expired','did_not_renew') then raise exception 'Membership cannot be cancelled'; end if;
 update public.memberships set status='cancelled' where id=p_membership_id;
 insert into public.membership_cancellations(gym_id,membership_id,cancellation_date,reason,notes,cancelled_by)
 values(p_gym_id,p_membership_id,p_cancellation_date,trim(p_reason),p_notes,private.current_app_user_id()) returning id into v_id;
 return v_id;
end
$$;

create or replace function public.reverse_payment(p_gym_id uuid,p_payment_id uuid,p_reason text,p_notes text default null)
returns void language plpgsql security definer
set search_path to 'public','private','pg_catalog'
as $$
declare v_payment public.payments%rowtype;v_refunded numeric;
begin
 if not private.has_permission(p_gym_id,'payments.edit') then raise exception 'Unauthorized'; end if;
 if nullif(trim(p_reason),'') is null then raise exception 'Reversal reason is required'; end if;
 select * into v_payment from public.payments where id=p_payment_id and gym_id=p_gym_id for update;
 if not found then raise exception 'Payment not found'; end if;
 if v_payment.status<>'paid' then raise exception 'Only paid payments can be reversed'; end if;
 select coalesce(sum(amount),0) into v_refunded from public.refunds where payment_id=p_payment_id;
 if v_refunded>0 then raise exception 'Refunded payments cannot be reversed'; end if;
 update public.payments set status='reversed',notes=coalesce(notes||E'\n','')||'Reversed: '||trim(p_reason)||case when p_notes is not null then ' | '||p_notes else '' end
 where id=p_payment_id and gym_id=p_gym_id;
end
$$;

create or replace function public.set_class_booking_attendance(p_gym_id uuid,p_booking_id uuid,p_status text)
returns void language plpgsql security definer
set search_path to 'public','private','pg_catalog'
as $$
declare v_session public.class_sessions%rowtype;
begin
 if not private.has_permission(p_gym_id,'classes.manage') then raise exception 'Unauthorized'; end if;
 if p_status not in('attended','no_show') then raise exception 'Invalid attendance status'; end if;
 select s.* into v_session from public.class_sessions s join public.class_bookings b on b.session_id=s.id
 where b.id=p_booking_id and b.gym_id=p_gym_id for update;
 if not found then raise exception 'Class session not found'; end if;
 if v_session.status<>'scheduled' then raise exception 'Cancelled or closed class sessions cannot be marked for attendance'; end if;
 if p_status='attended' and now()<v_session.start_at then raise exception 'Class has not started yet'; end if;
 if p_status='no_show' and now()<v_session.end_at then raise exception 'A no-show can only be recorded after the class ends'; end if;
 update public.class_bookings set status=p_status,waitlist_position=null,updated_at=now()
 where id=p_booking_id and gym_id=p_gym_id and status='booked';
 if not found then raise exception 'Active booking not found'; end if;
end
$$;

create or replace function public.queue_member_notification(p_gym_id uuid,p_member_id uuid,p_membership_id uuid default null,p_channel public.notification_channel default 'in_app',p_notification_type text default 'manual_message',p_message_body text default null)
returns uuid language plpgsql security definer
set search_path to 'public','private','pg_catalog'
as $$
declare v_id uuid;v_tz text;
begin
 if not private.has_permission(p_gym_id,'notifications.send') then raise exception 'Unauthorized'; end if;
 if p_channel='whatsapp' and not private.has_permission(p_gym_id,'whatsapp.manage') then raise exception 'Unauthorized'; end if;
 if p_notification_type='manual_message' and nullif(trim(p_message_body),'') is null then raise exception 'Message body is required'; end if;
 if not exists(select 1 from public.members where id=p_member_id and gym_id=p_gym_id) then raise exception 'Member not found'; end if;
 if p_membership_id is not null and not exists(select 1 from public.memberships where id=p_membership_id and member_id=p_member_id and gym_id=p_gym_id) then raise exception 'Invalid membership'; end if;
 select timezone into v_tz from public.gyms where id=p_gym_id;if v_tz is null then raise exception 'Gym timezone is not configured';end if;
 insert into public.notifications(gym_id,member_id,membership_id,notification_type,channel,scheduled_at,scheduled_date,status,delivery_status,message_body)
 values(p_gym_id,p_member_id,p_membership_id,p_notification_type,p_channel,now(),(now() at time zone v_tz)::date,'queued','pending',nullif(trim(p_message_body),''))
 returning id into v_id; return v_id;
end
$$;

create or replace function public.save_lead(p_gym_id uuid,p_lead_id uuid default null,p_name text default '',p_phone text default null,p_email text default null,p_source text default 'walk_in',p_status text default 'new',p_interested_package_id uuid default null,p_assigned_to uuid default null,p_follow_up_date date default null,p_notes text default null,p_lost_reason text default null)
returns uuid language plpgsql security definer
set search_path to 'public','private','pg_catalog'
as $$
declare v_id uuid;v_existing_status text;
begin
 if not private.has_permission(p_gym_id,'leads.manage') then raise exception 'Unauthorized'; end if;
 if length(trim(coalesce(p_name,'')))<2 then raise exception 'Please enter a valid lead name'; end if;
 if p_status not in('new','contacted','trial','won','lost') then raise exception 'Invalid lead status'; end if;
 if p_status='lost' and nullif(trim(p_lost_reason),'') is null then raise exception 'Lost reason is required'; end if;
 if p_status='won' and (p_lead_id is null or not exists(select 1 from public.leads where id=p_lead_id and gym_id=p_gym_id and converted_member_id is not null)) then raise exception 'Use Convert lead to mark a lead as won'; end if;
 if p_assigned_to is not null and not exists(select 1 from public.users where id=p_assigned_to and gym_id=p_gym_id and status='active') then raise exception 'Invalid assigned staff member'; end if;
 if p_interested_package_id is not null and not exists(select 1 from public.membership_packages where id=p_interested_package_id and gym_id=p_gym_id) then raise exception 'Invalid package'; end if;
 if p_lead_id is null then
   insert into public.leads(gym_id,name,phone,email,source,status,interested_package_id,assigned_to,follow_up_date,notes,lost_reason,created_by)
   values(p_gym_id,trim(p_name),nullif(trim(p_phone),''),nullif(trim(p_email),''),coalesce(nullif(trim(p_source),''),'walk_in'),p_status,p_interested_package_id,p_assigned_to,p_follow_up_date,nullif(trim(p_notes),''),nullif(trim(p_lost_reason),''),private.current_app_user_id())
   returning id into v_id;
 else
   select status into v_existing_status from public.leads where id=p_lead_id and gym_id=p_gym_id;
   if v_existing_status is null then raise exception 'Lead not found'; end if;
   if v_existing_status in('won','lost') and p_status<>v_existing_status then raise exception 'Closed leads cannot be reopened; create a new lead instead'; end if;
   update public.leads set name=trim(p_name),phone=nullif(trim(p_phone),''),email=nullif(trim(p_email),''),source=coalesce(nullif(trim(p_source),''),'walk_in'),
     status=p_status,interested_package_id=p_interested_package_id,assigned_to=p_assigned_to,follow_up_date=p_follow_up_date,
     notes=nullif(trim(p_notes),''),lost_reason=nullif(trim(p_lost_reason),''),updated_at=now()
   where id=p_lead_id and gym_id=p_gym_id;
   v_id:=p_lead_id;
 end if; return v_id;
end
$$;

create or replace function public.convert_lead(p_gym_id uuid,p_lead_id uuid,p_member_id uuid)
returns void language plpgsql security definer
set search_path to 'public','private','pg_catalog'
as $$
begin
 if not private.has_permission(p_gym_id,'leads.manage') then raise exception 'Unauthorized'; end if;
 if not exists(select 1 from public.leads where id=p_lead_id and gym_id=p_gym_id) then raise exception 'Lead not found'; end if;
 if not exists(select 1 from public.members where id=p_member_id and gym_id=p_gym_id and status='active') then raise exception 'Active member not found'; end if;
 update public.leads set status='won',converted_member_id=p_member_id,updated_at=now()
 where id=p_lead_id and gym_id=p_gym_id and status not in('won','lost');
 if not found then raise exception 'Lead is already closed'; end if;
end
$$;

create or replace function public.create_member_registration_v2(
 p_gym_id uuid,p_name text,p_phone text,p_email text default null,p_dob date default null,p_gender text default null,p_address text default null,
 p_emergency_contact text default null,p_emergency_phone text default null,p_member_id text default null,p_package_id uuid default null,
 p_duration_months integer default null,p_join_date date default current_date,p_start_date date default current_date,p_price numeric default null,
 p_discount numeric default 0,p_amount_paid numeric default 0,p_payment_method public.payment_method default 'cash',
 p_transaction_reference text default null,p_payment_notes text default null,p_manual_end_date date default null,p_assigned_coach_id uuid default null,
 p_allow_duplicate_phone boolean default false)
returns uuid language plpgsql security definer set search_path to 'public','private','pg_catalog'
as $$
declare v_member uuid;v_mid text;v_phone text:=private.normalize_member_phone(p_phone);v_price numeric;v_end date;v_membership uuid;v_final numeric;v_duration integer;v_admin boolean;v_unit text:='month';v_constraint text;v_tz text;v_today date;
begin
 if not private.has_permission(p_gym_id,'members.create') then raise exception 'Unauthorized';end if;
 if length(trim(p_name))<2 then raise exception 'Please enter a valid member name';end if;
 if length(v_phone)<8 or length(v_phone)>20 then raise exception 'Please enter a valid mobile number';end if;
 select timezone into v_tz from public.gyms where id=p_gym_id;if v_tz is null then raise exception 'Gym timezone is not configured';end if;
 v_today:=(now() at time zone v_tz)::date;
 if p_join_date is null or p_join_date>v_today then raise exception 'Joining date cannot be in the future';end if;
 if p_start_date is null or p_start_date<p_join_date then raise exception 'Membership start date cannot be before joining date';end if;
 if p_amount_paid is null or p_amount_paid<0 then raise exception 'Invalid payment amount';end if;
 if p_discount is null or p_discount<0 then raise exception 'Discount cannot be negative';end if;
 if p_manual_end_date is not null then raise exception 'Manual membership end date is no longer supported; it is calculated from the start date and duration.';end if;
 v_admin:=private.is_admin(p_gym_id);if p_allow_duplicate_phone and not v_admin then raise exception 'Only an admin can allow duplicate mobile numbers';end if;
 v_mid:=case when nullif(trim(p_member_id),'') is null then private.generate_member_id(p_gym_id) else trim(p_member_id) end;
 if exists(select 1 from public.members where gym_id=p_gym_id and member_id=v_mid) then raise exception 'Member ID already exists';end if;
 if not p_allow_duplicate_phone and exists(select 1 from public.members where gym_id=p_gym_id and phone=v_phone and not allow_duplicate_phone) then raise exception 'An existing member with this mobile number was found';end if;
 if p_package_id is not null then
   select price,duration_months,duration_unit into v_price,v_duration,v_unit from public.membership_packages where id=p_package_id and gym_id=p_gym_id and status='active';if not found then raise exception 'Invalid package';end if;
 else
   if p_price is null or p_price<0 then raise exception 'Valid custom price is required';end if;
   v_price:=p_price;v_duration:=p_duration_months;v_unit:='month';
 end if;
 if v_duration is null or v_duration<=0 then raise exception 'Duration is required';end if;
 v_final:=greatest(v_price-coalesce(p_discount,0),0);if p_amount_paid>v_final then raise exception 'Amount paid cannot exceed final amount';end if;
 if p_amount_paid>0 and not exists(select 1 from public.payment_method_settings where gym_id=p_gym_id and payment_method=p_payment_method and enabled) then raise exception 'Selected payment method is disabled';end if;
 if nullif(trim(p_transaction_reference),'') is not null and exists(select 1 from public.payments where gym_id=p_gym_id and transaction_reference=trim(p_transaction_reference) and status not in('refunded','reversed')) then raise exception 'Transaction reference already exists';end if;
 v_end:=public.calculate_membership_end_by_unit(p_start_date,v_duration,v_unit);if v_end<p_start_date then raise exception 'Invalid membership dates';end if;
 if p_assigned_coach_id is not null and not exists(select 1 from public.users where id=p_assigned_coach_id and gym_id=p_gym_id and status='active') then raise exception 'Invalid assigned coach';end if;
 begin
   insert into public.members(gym_id,member_id,name,phone,email,dob,gender,address,emergency_contact,emergency_phone,created_by,join_date,assigned_coach_id,allow_duplicate_phone)
   values(p_gym_id,v_mid,trim(p_name),v_phone,nullif(trim(p_email),''),p_dob,p_gender,p_address,p_emergency_contact,p_emergency_phone,private.current_app_user_id(),p_join_date,p_assigned_coach_id,p_allow_duplicate_phone)
   returning id into v_member;
 exception when unique_violation then get stacked diagnostics v_constraint=constraint_name;
   if v_constraint='members_gym_phone_unique' then raise exception 'An existing member with this mobile number was found';
   elsif v_constraint='members_gym_id_member_id_key' then raise exception 'Member ID already exists'; end if; raise;
 end;
 insert into public.memberships(gym_id,member_id,package_id,membership_type,start_date,end_date,duration_months,price,discount,created_by)
 values(p_gym_id,v_member,p_package_id,'new',p_start_date,v_end,v_duration,v_price,coalesce(p_discount,0),private.current_app_user_id()) returning id into v_membership;
 if p_amount_paid>0 then insert into public.payments(gym_id,member_id,membership_id,amount,payment_method,transaction_reference,notes,recorded_by,status)
 values(p_gym_id,v_member,v_membership,p_amount_paid,p_payment_method,nullif(trim(p_transaction_reference),''),p_payment_notes,private.current_app_user_id(),'paid');end if;
 return v_member;
end
$$;

create or replace function public.update_member_profile(p_gym_id uuid,p_member_id uuid,p_name text,p_phone text,p_email text default null,p_dob date default null,p_gender text default null,p_address text default null,p_emergency_contact text default null,p_emergency_phone text default null,p_assigned_coach_id uuid default null)
returns void language plpgsql security definer set search_path to 'public','private','pg_catalog'
as $$
declare v_phone text:=private.normalize_member_phone(p_phone);v_constraint text;
begin
 if not private.has_permission(p_gym_id,'members.edit') then raise exception 'Unauthorized';end if;
 if length(trim(p_name))<2 then raise exception 'Please enter a valid member name';end if;
 if length(v_phone)<8 or length(v_phone)>20 then raise exception 'Please enter a valid mobile number';end if;
 if p_assigned_coach_id is not null and not exists(select 1 from public.users where id=p_assigned_coach_id and gym_id=p_gym_id and status='active') then raise exception 'Invalid assigned coach';end if;
 begin
  update public.members set name=trim(p_name),phone=v_phone,email=nullif(trim(p_email),''),dob=p_dob,gender=p_gender,address=p_address,
    emergency_contact=nullif(trim(p_emergency_contact),''),emergency_phone=nullif(trim(p_emergency_phone),''),assigned_coach_id=p_assigned_coach_id,updated_at=now()
  where id=p_member_id and gym_id=p_gym_id;
  if not found then raise exception 'Member not found';end if;
 exception when unique_violation then get stacked diagnostics v_constraint=constraint_name;
  if v_constraint='members_gym_phone_unique' then raise exception 'An existing member with this mobile number was found';end if;raise;
 end;
end
$$;

create or replace function public.create_renewal(
 p_gym_id uuid,p_member_id uuid,p_package_id uuid default null,p_duration_months integer default null,p_start_date date default null,
 p_price numeric default null,p_discount numeric default 0,p_amount_paid numeric default 0,p_payment_method public.payment_method default 'cash',
 p_transaction_reference text default null,p_notes text default null,p_end_date date default null)
returns uuid language plpgsql security definer set search_path to 'public','private','pg_catalog'
as $$
declare v_old public.memberships%rowtype;v_new uuid;v_price numeric;v_duration integer;v_start date;v_end date;v_final numeric;v_unit text:='month';v_tz text;v_today date;
begin
 if not private.has_permission(p_gym_id,'members.renew') then raise exception 'Unauthorized';end if;
 if p_end_date is not null then raise exception 'Manual renewal end date is no longer supported; choose the package and start date.';end if;
 if p_discount is null or p_discount<0 then raise exception 'Discount cannot be negative';end if;
 if p_amount_paid is null or p_amount_paid<0 then raise exception 'Invalid amount paid';end if;
 select timezone into v_tz from public.gyms where id=p_gym_id;if v_tz is null then raise exception 'Gym timezone is not configured';end if;
 v_today:=(now() at time zone v_tz)::date;
 select * into v_old from public.memberships where member_id=p_member_id and gym_id=p_gym_id order by created_at desc,end_date desc limit 1 for update;
 if not found then raise exception 'No previous membership found';end if;
 if v_old.status='cancelled' then raise exception 'Cancelled memberships cannot be renewed';end if;
 if p_package_id is not null then
  select price,duration_months,duration_unit into v_price,v_duration,v_unit from public.membership_packages where id=p_package_id and gym_id=p_gym_id and status='active';if not found then raise exception 'Invalid package';end if;
 else
  if p_price is null or p_price<0 then raise exception 'Valid custom price is required';end if;
  v_price:=p_price;v_duration:=p_duration_months;v_unit:='month';
 end if;
 if v_duration is null or v_duration<=0 then raise exception 'Duration is required';end if;
 v_start:=coalesce(p_start_date,greatest(v_today,v_old.end_date+1));
 if v_start<greatest(v_today,v_old.end_date+1) then raise exception 'Renewal start date cannot overlap or predate the previous membership';end if;
 v_end:=public.calculate_membership_end_by_unit(v_start,v_duration,v_unit);if v_end<v_start then raise exception 'Invalid membership dates';end if;
 v_final:=greatest(v_price-coalesce(p_discount,0),0);if p_amount_paid>v_final then raise exception 'Amount paid cannot exceed final membership amount';end if;
 if v_final>0 and p_amount_paid<=0 then raise exception 'Renewal requires a payment';end if;
 if p_amount_paid>0 and not exists(select 1 from public.payment_method_settings where gym_id=p_gym_id and payment_method=p_payment_method and enabled) then raise exception 'Selected payment method is disabled';end if;
 if nullif(trim(p_transaction_reference),'') is not null and exists(select 1 from public.payments where gym_id=p_gym_id and transaction_reference=trim(p_transaction_reference) and status not in('refunded','reversed')) then raise exception 'Transaction reference already exists';end if;
 update public.memberships set status='renewed' where id=v_old.id;
 insert into public.memberships(gym_id,member_id,package_id,membership_type,start_date,end_date,duration_months,price,discount,status,previous_membership_id,created_by)
 values(p_gym_id,p_member_id,p_package_id,'renewal',v_start,v_end,v_duration,v_price,coalesce(p_discount,0),'active',v_old.id,private.current_app_user_id()) returning id into v_new;
 if p_amount_paid>0 then insert into public.payments(gym_id,member_id,membership_id,amount,payment_method,transaction_reference,notes,recorded_by,status)
 values(p_gym_id,p_member_id,v_new,p_amount_paid,p_payment_method,nullif(trim(p_transaction_reference),''),p_notes,private.current_app_user_id(),'paid');end if;
 return v_new;
end
$$;

create or replace function public.get_whatsapp_app_secrets_internal()
returns table(meta_app_secret text)
language sql security definer
set search_path to 'private','pg_catalog'
as $$select c.meta_app_secret from private.whatsapp_connections c where c.enabled=true and c.meta_app_secret is not null$$;
revoke all on function public.get_whatsapp_app_secrets_internal() from public,anon,authenticated;
grant execute on function public.get_whatsapp_app_secrets_internal() to service_role;

create or replace function public.save_whatsapp_connection(
 p_gym_id uuid,p_business_account_id text,p_phone_number_id text,p_access_token text,p_api_version text,p_verify_token text default null,p_meta_app_secret text default null)
returns void language plpgsql security definer
set search_path to 'public','private','pg_catalog'
as $$
declare existing_token text;existing_app_secret text;
begin
 if not private.is_admin(p_gym_id) then raise exception 'Unauthorized';end if;
 if nullif(trim(p_phone_number_id),'') is null then raise exception 'Phone Number ID is required';end if;
 if nullif(trim(p_api_version),'') is null then raise exception 'Graph API version is required';end if;
 select access_token,meta_app_secret into existing_token,existing_app_secret from private.whatsapp_connections where gym_id=p_gym_id;
 if existing_token is null and nullif(trim(coalesce(p_access_token,'')),'') is null then raise exception 'WhatsApp access token is required for the first connection';end if;
 if existing_app_secret is null and nullif(trim(coalesce(p_meta_app_secret,'')),'') is null then raise exception 'Meta App Secret is required for webhook security';end if;
 insert into private.whatsapp_connections(gym_id,business_account_id,phone_number_id,access_token,api_version,verify_token,meta_app_secret,enabled,last_test_ok,last_error,updated_at)
 values(p_gym_id,nullif(trim(p_business_account_id),''),trim(p_phone_number_id),coalesce(nullif(trim(p_access_token),''),existing_token),trim(p_api_version),nullif(trim(p_verify_token),''),coalesce(nullif(trim(p_meta_app_secret),''),existing_app_secret),true,null,null,now())
 on conflict(gym_id) do update set business_account_id=excluded.business_account_id,phone_number_id=excluded.phone_number_id,access_token=excluded.access_token,api_version=excluded.api_version,verify_token=excluded.verify_token,meta_app_secret=excluded.meta_app_secret,enabled=true,last_test_ok=null,last_error=null,updated_at=now();
end
$$;
revoke execute on function public.save_whatsapp_connection(uuid,text,text,text,text,text,text) from public,authenticated;
grant execute on function public.save_whatsapp_connection(uuid,text,text,text,text,text,text) to anon;
revoke execute on function public.get_whatsapp_connection(uuid) from public,anon,authenticated;
grant execute on function public.get_whatsapp_connection(uuid) to anon;
revoke execute on function public.disconnect_whatsapp_connection(uuid) from public,anon,authenticated;
grant execute on function public.disconnect_whatsapp_connection(uuid) to anon;

create or replace function public.record_whatsapp_test_internal(p_gym_id uuid,p_ok boolean,p_error text default null)
returns void language plpgsql security definer set search_path to 'public','private','pg_catalog'
as $$begin
 update private.whatsapp_connections set last_tested_at=now(),last_test_ok=p_ok,last_error=case when p_ok then null else left(p_error,4000) end,updated_at=now() where gym_id=p_gym_id;
 if not found then raise exception 'WhatsApp connection has not been saved'; end if;
end$$;
revoke all on function public.record_whatsapp_test_internal(uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.record_whatsapp_test_internal(uuid,boolean,text) to service_role;

create or replace function public.get_whatsapp_credentials_internal(p_gym_id uuid)
returns table(phone_number_id text,access_token text,api_version text,enabled boolean)
language sql security definer set search_path to 'private','pg_catalog'
as $$select c.phone_number_id,c.access_token,c.api_version,c.enabled from private.whatsapp_connections c where c.gym_id=p_gym_id limit 1$$;
revoke all on function public.get_whatsapp_credentials_internal(uuid) from public,anon,authenticated;
grant execute on function public.get_whatsapp_credentials_internal(uuid) to service_role;

create or replace function public.get_whatsapp_worker_secret_internal()
returns text language sql security definer set search_path to 'private','pg_catalog'
as $$select secret from private.whatsapp_worker_config where id=true limit 1$$;
revoke all on function public.get_whatsapp_worker_secret_internal() from public,anon,authenticated;
grant execute on function public.get_whatsapp_worker_secret_internal() to service_role;

create or replace function public.record_whatsapp_test_internal(p_gym_id uuid,p_ok boolean,p_error text default null)
returns void language plpgsql security definer set search_path to 'public','private','pg_catalog'
as $$begin
 update private.whatsapp_connections set last_tested_at=now(),last_test_ok=p_ok,last_error=case when p_ok then null else left(p_error,4000) end,updated_at=now() where gym_id=p_gym_id;
 if not found then raise exception 'WhatsApp connection has not been saved';end if;
end$$;
revoke all on function public.record_whatsapp_test_internal(uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.record_whatsapp_test_internal(uuid,boolean,text) to service_role;

create index if not exists class_sessions_created_by_idx on public.class_sessions(created_by);

revoke all on table public.attendance_report,public.class_timetable_report,public.coach_performance_report,public.did_not_renew_report,public.expired_members_report,public.expiring_members_report,public.member_class_bookings_report,public.member_report,public.membership_payment_summary,public.outstanding_payment_report,public.package_performance_report,public.renewal_report,public.revenue_report from anon,authenticated;
grant select on table public.attendance_report,public.class_timetable_report,public.coach_performance_report,public.did_not_renew_report,public.expired_members_report,public.expiring_members_report,public.member_class_bookings_report,public.member_report,public.membership_payment_summary,public.outstanding_payment_report,public.package_performance_report,public.renewal_report,public.revenue_report to anon,authenticated;

alter view public.member_report set (security_invoker=true);


create or replace function public.save_gym_profile(
 p_gym_id uuid,p_name text,p_address text default null,p_phone text default null,p_whatsapp text default null,p_email text default null,
 p_gst_number text default null,p_currency text default 'INR',p_timezone text default 'Asia/Kolkata',p_opening_time time default null,p_closing_time time default null,
 p_weekly_holidays smallint[] default '{}',p_member_id_prefix text default 'GYM',p_renewal_grace_days integer default 7)
returns public.gyms language plpgsql security definer set search_path to 'public','private','pg_catalog'
as $$declare v public.gyms%rowtype;begin
 if not private.is_admin(p_gym_id) then raise exception 'Unauthorized';end if;
 if nullif(trim(p_name),'') is null then raise exception 'Gym name is required';end if;
 if p_renewal_grace_days is null or p_renewal_grace_days<0 or p_renewal_grace_days>365 then raise exception 'Grace period must be between 0 and 365 days';end if;
 if nullif(trim(p_currency),'') is null or length(trim(p_currency))<>3 then raise exception 'Currency must be a 3-letter code';end if;
 if nullif(trim(p_timezone),'') is null then raise exception 'Timezone is required';end if;
 if p_opening_time is not null and p_closing_time is not null and p_closing_time<=p_opening_time then raise exception 'Closing time must be after opening time';end if;
 update public.gyms set name=trim(p_name),address=nullif(trim(p_address),''),phone=nullif(trim(p_phone),''),whatsapp=nullif(trim(p_whatsapp),''),email=nullif(trim(p_email),''),
 gst_number=nullif(trim(p_gst_number),''),currency=upper(trim(p_currency)),timezone=trim(p_timezone),opening_time=p_opening_time,closing_time=p_closing_time,
 weekly_holidays=coalesce(p_weekly_holidays,'{}'),member_id_prefix=upper(coalesce(nullif(trim(p_member_id_prefix),''),'GYM')),renewal_grace_days=p_renewal_grace_days,updated_at=now()
 where id=p_gym_id returning * into v;if not found then raise exception 'Gym not found';end if;return v;end$$;

create or replace function public.save_gym_settings(
 p_gym_id uuid,p_expiry_reminder_10_days boolean,p_expiry_reminder_5_days boolean,p_expiry_reminder_today boolean,p_payment_reminders boolean,p_admin_alerts boolean,
 p_whatsapp_enabled boolean,p_email_enabled boolean,p_push_enabled boolean)
returns public.gym_settings language plpgsql security definer set search_path to 'public','private','pg_catalog'
as $$declare v public.gym_settings%rowtype;begin
 if not private.is_admin(p_gym_id) then raise exception 'Unauthorized';end if;
 update public.gym_settings set expiry_reminder_10_days=p_expiry_reminder_10_days,expiry_reminder_5_days=p_expiry_reminder_5_days,
 expiry_reminder_today=p_expiry_reminder_today,payment_reminders=p_payment_reminders,admin_alerts=p_admin_alerts,
 whatsapp_enabled=p_whatsapp_enabled,email_enabled=p_email_enabled,push_enabled=p_push_enabled,updated_at=now()
 where gym_id=p_gym_id returning * into v;if not found then raise exception 'Gym settings not found';end if;return v;end$$;

create or replace function public.save_payment_method_setting(p_gym_id uuid,p_payment_method public.payment_method,p_enabled boolean)
returns void language plpgsql security definer set search_path to 'public','private','pg_catalog'
as $$begin
 if not private.is_admin(p_gym_id) then raise exception 'Unauthorized';end if;
 insert into public.payment_method_settings(gym_id,payment_method,enabled) values(p_gym_id,p_payment_method,p_enabled)
 on conflict(gym_id,payment_method) do update set enabled=excluded.enabled;
end$$;

create or replace function public.save_notification_template(
 p_gym_id uuid,p_template_id uuid,p_body text,p_enabled boolean,p_subject text default null,
 p_provider_template_name text default null,p_provider_template_language text default 'en_US',p_provider_template_variables text[] default '{}')
returns public.notification_templates language plpgsql security definer set search_path to 'public','private','pg_catalog'
as $$declare v public.notification_templates%rowtype;begin
 if not(private.is_admin(p_gym_id) or private.has_permission(p_gym_id,'whatsapp.manage')) then raise exception 'Unauthorized';end if;
 if nullif(trim(p_body),'') is null then raise exception 'Template body is required';end if;
 update public.notification_templates set body=p_body,enabled=p_enabled,subject=nullif(trim(p_subject),''),provider_template_name=nullif(trim(p_provider_template_name),''),
 provider_template_language=coalesce(nullif(trim(p_provider_template_language),''),'en_US'),provider_template_variables=coalesce(p_provider_template_variables,'{}'),updated_at=now()
 where id=p_template_id and gym_id=p_gym_id returning * into v;
 if not found then raise exception 'Notification template not found';end if;return v;end$$;

revoke insert,update,delete,truncate,references,trigger on public.gyms,public.gym_settings,public.payment_method_settings,public.notification_templates from anon,authenticated;
