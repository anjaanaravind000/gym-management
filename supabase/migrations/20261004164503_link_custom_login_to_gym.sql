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
 update public.login_accounts set gym_id=v_gym,display_name=trim(p_user_name),email=nullif(trim(p_email),''),phone=nullif(trim(p_phone),''),updated_at=now() where id=v_uid;
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