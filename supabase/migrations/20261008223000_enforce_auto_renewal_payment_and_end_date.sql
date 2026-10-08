create or replace function public.create_renewal(
 p_gym_id uuid,
 p_member_id uuid,
 p_package_id uuid default null::uuid,
 p_duration_months integer default null::integer,
 p_start_date date default null::date,
 p_price numeric default null::numeric,
 p_discount numeric default 0,
 p_amount_paid numeric default 0,
 p_payment_method public.payment_method default 'cash'::public.payment_method,
 p_transaction_reference text default null::text,
 p_notes text default null::text,
 p_end_date date default null::date
)
returns uuid
language plpgsql
security definer
set search_path to 'public','private','pg_catalog'
as $function$
declare
 v_old public.memberships%rowtype;
 v_new uuid;
 v_price numeric;
 v_duration integer;
 v_start date;
 v_end date;
 v_final numeric;
 v_unit text:='month';
 v_tz text;
 v_today date;
begin
 if not private.has_permission(p_gym_id,'members.renew') then raise exception 'Unauthorized'; end if;
 if p_end_date is not null then raise exception 'Manual renewal end date is no longer supported; choose the package and start date.'; end if;
 if p_discount is null or p_discount<0 then raise exception 'Discount cannot be negative'; end if;
 if p_amount_paid is null or p_amount_paid<0 then raise exception 'Invalid amount paid'; end if;

 select timezone into v_tz from public.gyms where id=p_gym_id;
 if v_tz is null then raise exception 'Gym timezone is not configured'; end if;
 v_today:=(now() at time zone v_tz)::date;

 select * into v_old from public.memberships
 where id=(select id from public.memberships where member_id=p_member_id and gym_id=p_gym_id order by end_date desc,created_at desc limit 1) for update;
 if not found then raise exception 'No previous membership found'; end if;
 if v_old.status='cancelled' then raise exception 'Cancelled memberships cannot be renewed'; end if;

 if p_package_id is not null then
   select price,duration_months,duration_unit into v_price,v_duration,v_unit
   from public.membership_packages
   where id=p_package_id and gym_id=p_gym_id and status='active';
   if not found then raise exception 'Invalid package'; end if;
 else
   if p_price is null or p_price<0 then raise exception 'Valid custom price is required'; end if;
   v_price:=p_price;v_duration:=p_duration_months;v_unit:='month';
 end if;

 if v_duration is null or v_duration<=0 then raise exception 'Duration is required'; end if;
 v_start:=coalesce(p_start_date,greatest(v_today,v_old.end_date+1));
 v_end:=public.calculate_membership_end_by_unit(v_start,v_duration,v_unit);
 if v_end<v_start then raise exception 'Invalid membership dates'; end if;
 v_final:=greatest(v_price-coalesce(p_discount,0),0);
 if p_amount_paid>v_final then raise exception 'Amount paid cannot exceed final membership amount'; end if;
 if v_final>0 and p_amount_paid<=0 then raise exception 'Renewal requires a payment'; end if;
 if p_amount_paid>0 and not exists(
   select 1 from public.payment_method_settings
   where gym_id=p_gym_id and payment_method=p_payment_method and enabled
 ) then raise exception 'Selected payment method is disabled'; end if;

 if nullif(trim(p_transaction_reference),'') is not null and exists(
   select 1 from public.payments where gym_id=p_gym_id and transaction_reference=trim(p_transaction_reference)
   and status not in('refunded','reversed')
 ) then raise exception 'Transaction reference already exists'; end if;

 update public.memberships set status='renewed' where id=v_old.id;
 insert into public.memberships(gym_id,member_id,package_id,membership_type,start_date,end_date,duration_months,price,discount,status,previous_membership_id,created_by)
 values(p_gym_id,p_member_id,p_package_id,'renewal',v_start,v_end,v_duration,v_price,coalesce(p_discount,0),'active',v_old.id,private.current_app_user_id())
 returning id into v_new;

 if p_amount_paid>0 then
   insert into public.payments(gym_id,member_id,membership_id,amount,payment_method,transaction_reference,notes,recorded_by,status)
   values(p_gym_id,p_member_id,v_new,v_final,p_payment_method,nullif(trim(p_transaction_reference),''),p_notes,private.current_app_user_id(),'paid');
 end if;
 return v_new;
end
$function$;