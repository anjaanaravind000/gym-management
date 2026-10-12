-- Defense-in-depth fixes for the custom-session browser client.
-- The prior migration adds membership_status.scheduled before this migration uses it.

-- Add retry-safe renewal handling and serialize renewals by member.
do $migration$
declare
  v_sql text;
  v_old text;
  v_new text;
begin
  v_sql := pg_get_functiondef('public.create_renewal(uuid,uuid,uuid,integer,date,numeric,numeric,numeric,payment_method,text,text,date)'::regprocedure);

  v_old := 'v_today date;' || E'\nbegin';
  v_new := 'v_today date; v_existing_payment public.payments%rowtype; v_existing_membership public.memberships%rowtype;' || E'\nbegin';
  if position(v_old in v_sql)=0 then raise exception 'Could not locate create_renewal declaration'; end if;
  v_sql := replace(v_sql,v_old,v_new);

  v_old := 'if p_amount_paid is null or p_amount_paid<0 then raise exception ''Invalid amount paid''; end if;';
  v_new := v_old || E'\n'
    || 'perform 1 from public.members where id=p_member_id and gym_id=p_gym_id for update;'
    || E'\n' || 'if not found then raise exception ''Member not found''; end if;'
    || E'\n'
    || 'if nullif(trim(p_transaction_reference),'''') is not null then'
    || E'\n' || ' select p.* into v_existing_payment from public.payments p'
    || E'\n' || ' where p.gym_id=p_gym_id and p.transaction_reference=trim(p_transaction_reference)'
    || E'\n' || ' and p.status not in (''refunded'',''reversed'') limit 1;'
    || E'\n' || ' if found then'
    || E'\n' || '  select * into v_existing_membership from public.memberships where id=v_existing_payment.membership_id;'
    || E'\n' || '  if v_existing_membership.id is not null'
    || E'\n' || '   and v_existing_payment.member_id=p_member_id'
    || E'\n' || '   and v_existing_payment.gym_id=p_gym_id'
    || E'\n' || '   and v_existing_payment.amount=p_amount_paid'
    || E'\n' || '   and v_existing_payment.payment_method=p_payment_method'
    || E'\n' || '   and v_existing_membership.member_id=p_member_id'
    || E'\n' || '   and v_existing_membership.gym_id=p_gym_id'
    || E'\n' || '   and v_existing_membership.membership_type=''renewal'''
    || E'\n' || '   and v_existing_membership.package_id is not distinct from p_package_id'
    || E'\n' || '   and (p_start_date is null or v_existing_membership.start_date=p_start_date)'
    || E'\n' || '   and (p_price is null or v_existing_membership.price=p_price)'
    || E'\n' || '   and v_existing_membership.discount=coalesce(p_discount,0)'
    || E'\n' || '   and (p_duration_months is null or v_existing_membership.duration_months=p_duration_months) then'
    || E'\n' || '    return v_existing_membership.id;'
    || E'\n' || '  end if;'
    || E'\n' || '  raise exception ''Transaction reference already exists'';'
    || E'\n' || ' end if;'
    || E'\n' || 'end if;';
  if position(v_old in v_sql)=0 then raise exception 'Could not locate create_renewal payment validation'; end if;
  v_sql := replace(v_sql,v_old,v_new);

  v_old := 'if v_old.status=''cancelled'' then raise exception ''Cancelled memberships cannot be renewed''; end if;';
  v_new := v_old || E'\n'
    || 'if exists(select 1 from public.memberships where member_id=p_member_id and gym_id=p_gym_id and status=''scheduled'' and membership_type=''renewal'') then'
    || E'\n' || ' raise exception ''A future renewal is already scheduled for this member'';'
    || E'\n' || 'end if;';
  if position(v_old in v_sql)=0 then raise exception 'Could not locate create_renewal cancelled-membership guard'; end if;
  v_sql := replace(v_sql,v_old,v_new);

  v_old := 'v_final:=greatest(v_price-coalesce(p_discount,0),0);';
  v_new := 'if coalesce(p_discount,0)>v_price then raise exception ''Discount cannot exceed membership price''; end if;' || E'\n' || v_old;
  if position(v_old in v_sql)=0 then raise exception 'Could not locate create_renewal final amount calculation'; end if;
  v_sql := replace(v_sql,v_old,v_new);

  execute v_sql;
end
$migration$;

-- Only one future renewal may be pending per member. Active membership uniqueness remains unchanged.
create unique index if not exists memberships_one_scheduled_renewal_per_member
  on public.memberships(member_id)
  where status='scheduled' and membership_type='renewal';

-- Add composite keys so child records cannot point across gyms even if an RPC regresses.
create unique index if not exists members_id_gym_uq on public.members(id,gym_id);
create unique index if not exists users_id_gym_uq on public.users(id,gym_id);
create unique index if not exists membership_packages_id_gym_uq on public.membership_packages(id,gym_id);
create unique index if not exists memberships_id_gym_uq on public.memberships(id,gym_id);
create unique index if not exists memberships_id_member_gym_uq on public.memberships(id,member_id,gym_id);
create unique index if not exists payments_id_gym_uq on public.payments(id,gym_id);
create unique index if not exists gym_classes_id_gym_uq on public.gym_classes(id,gym_id);
create unique index if not exists class_sessions_id_gym_uq on public.class_sessions(id,gym_id);

do $constraints$
begin
  if not exists(select 1 from pg_constraint where conname='members_assigned_coach_same_gym_fk') then
    alter table public.members add constraint members_assigned_coach_same_gym_fk foreign key(assigned_coach_id,gym_id) references public.users(id,gym_id) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='members_created_by_same_gym_fk') then
    alter table public.members add constraint members_created_by_same_gym_fk foreign key(created_by,gym_id) references public.users(id,gym_id) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='memberships_member_same_gym_fk') then
    alter table public.memberships add constraint memberships_member_same_gym_fk foreign key(member_id,gym_id) references public.members(id,gym_id) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='memberships_package_same_gym_fk') then
    alter table public.memberships add constraint memberships_package_same_gym_fk foreign key(package_id,gym_id) references public.membership_packages(id,gym_id) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='memberships_previous_same_member_gym_fk') then
    alter table public.memberships add constraint memberships_previous_same_member_gym_fk foreign key(previous_membership_id,member_id,gym_id) references public.memberships(id,member_id,gym_id) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='memberships_created_by_same_gym_fk') then
    alter table public.memberships add constraint memberships_created_by_same_gym_fk foreign key(created_by,gym_id) references public.users(id,gym_id) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='payments_member_same_gym_fk') then
    alter table public.payments add constraint payments_member_same_gym_fk foreign key(member_id,gym_id) references public.members(id,gym_id) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='payments_membership_same_member_gym_fk') then
    alter table public.payments add constraint payments_membership_same_member_gym_fk foreign key(membership_id,member_id,gym_id) references public.memberships(id,member_id,gym_id) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='payments_recorded_by_same_gym_fk') then
    alter table public.payments add constraint payments_recorded_by_same_gym_fk foreign key(recorded_by,gym_id) references public.users(id,gym_id) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='payments_original_same_gym_fk') then
    alter table public.payments add constraint payments_original_same_gym_fk foreign key(original_payment_id,gym_id) references public.payments(id,gym_id) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='attendance_member_same_gym_fk') then
    alter table public.attendance add constraint attendance_member_same_gym_fk foreign key(member_id,gym_id) references public.members(id,gym_id) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='membership_freezes_same_gym_fk') then
    alter table public.membership_freezes add constraint membership_freezes_same_gym_fk foreign key(membership_id,gym_id) references public.memberships(id,gym_id) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='membership_freezes_created_by_same_gym_fk') then
    alter table public.membership_freezes add constraint membership_freezes_created_by_same_gym_fk foreign key(created_by,gym_id) references public.users(id,gym_id) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='membership_cancellations_same_gym_fk') then
    alter table public.membership_cancellations add constraint membership_cancellations_same_gym_fk foreign key(membership_id,gym_id) references public.memberships(id,gym_id) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='membership_cancellations_cancelled_by_same_gym_fk') then
    alter table public.membership_cancellations add constraint membership_cancellations_cancelled_by_same_gym_fk foreign key(cancelled_by,gym_id) references public.users(id,gym_id) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='class_sessions_class_same_gym_fk') then
    alter table public.class_sessions add constraint class_sessions_class_same_gym_fk foreign key(class_id,gym_id) references public.gym_classes(id,gym_id) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='class_sessions_instructor_same_gym_fk') then
    alter table public.class_sessions add constraint class_sessions_instructor_same_gym_fk foreign key(instructor_id,gym_id) references public.users(id,gym_id) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='class_sessions_created_by_same_gym_fk') then
    alter table public.class_sessions add constraint class_sessions_created_by_same_gym_fk foreign key(created_by,gym_id) references public.users(id,gym_id) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='class_bookings_member_same_gym_fk') then
    alter table public.class_bookings add constraint class_bookings_member_same_gym_fk foreign key(member_id,gym_id) references public.members(id,gym_id) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='class_bookings_session_same_gym_fk') then
    alter table public.class_bookings add constraint class_bookings_session_same_gym_fk foreign key(session_id,gym_id) references public.class_sessions(id,gym_id) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='leads_assigned_to_same_gym_fk') then
    alter table public.leads add constraint leads_assigned_to_same_gym_fk foreign key(assigned_to,gym_id) references public.users(id,gym_id) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='leads_package_same_gym_fk') then
    alter table public.leads add constraint leads_package_same_gym_fk foreign key(interested_package_id,gym_id) references public.membership_packages(id,gym_id) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='leads_member_same_gym_fk') then
    alter table public.leads add constraint leads_member_same_gym_fk foreign key(converted_member_id,gym_id) references public.members(id,gym_id) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='leads_created_by_same_gym_fk') then
    alter table public.leads add constraint leads_created_by_same_gym_fk foreign key(created_by,gym_id) references public.users(id,gym_id) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='notifications_member_same_gym_fk') then
    alter table public.notifications add constraint notifications_member_same_gym_fk foreign key(member_id,gym_id) references public.members(id,gym_id) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='notifications_membership_same_member_gym_fk') then
    alter table public.notifications add constraint notifications_membership_same_member_gym_fk foreign key(membership_id,member_id,gym_id) references public.memberships(id,member_id,gym_id) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='expenses_created_by_same_gym_fk') then
    alter table public.expenses add constraint expenses_created_by_same_gym_fk foreign key(created_by,gym_id) references public.users(id,gym_id) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='refunds_payment_same_gym_fk') then
    alter table public.refunds add constraint refunds_payment_same_gym_fk foreign key(payment_id,gym_id) references public.payments(id,gym_id) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='refunds_authorized_by_same_gym_fk') then
    alter table public.refunds add constraint refunds_authorized_by_same_gym_fk foreign key(authorized_by,gym_id) references public.users(id,gym_id) not valid;
  end if;
  if not exists(select 1 from pg_constraint where conname='gym_classes_created_by_same_gym_fk') then
    alter table public.gym_classes add constraint gym_classes_created_by_same_gym_fk foreign key(created_by,gym_id) references public.users(id,gym_id) not valid;
  end if;
end
$constraints$;

-- Validate old rows as well as enforcing these constraints on future writes.
alter table public.members validate constraint members_assigned_coach_same_gym_fk;
alter table public.members validate constraint members_created_by_same_gym_fk;
alter table public.memberships validate constraint memberships_member_same_gym_fk;
alter table public.memberships validate constraint memberships_package_same_gym_fk;
alter table public.memberships validate constraint memberships_previous_same_member_gym_fk;
alter table public.memberships validate constraint memberships_created_by_same_gym_fk;
alter table public.payments validate constraint payments_member_same_gym_fk;
alter table public.payments validate constraint payments_membership_same_member_gym_fk;
alter table public.payments validate constraint payments_recorded_by_same_gym_fk;
alter table public.payments validate constraint payments_original_same_gym_fk;
alter table public.attendance validate constraint attendance_member_same_gym_fk;
alter table public.membership_freezes validate constraint membership_freezes_same_gym_fk;
alter table public.membership_freezes validate constraint membership_freezes_created_by_same_gym_fk;
alter table public.membership_cancellations validate constraint membership_cancellations_same_gym_fk;
alter table public.membership_cancellations validate constraint membership_cancellations_cancelled_by_same_gym_fk;
alter table public.class_sessions validate constraint class_sessions_class_same_gym_fk;
alter table public.class_sessions validate constraint class_sessions_instructor_same_gym_fk;
alter table public.class_sessions validate constraint class_sessions_created_by_same_gym_fk;
alter table public.class_bookings validate constraint class_bookings_member_same_gym_fk;
alter table public.class_bookings validate constraint class_bookings_session_same_gym_fk;
alter table public.leads validate constraint leads_assigned_to_same_gym_fk;
alter table public.leads validate constraint leads_package_same_gym_fk;
alter table public.leads validate constraint leads_member_same_gym_fk;
alter table public.leads validate constraint leads_created_by_same_gym_fk;
alter table public.notifications validate constraint notifications_member_same_gym_fk;
alter table public.notifications validate constraint notifications_membership_same_member_gym_fk;
alter table public.expenses validate constraint expenses_created_by_same_gym_fk;
alter table public.refunds validate constraint refunds_payment_same_gym_fk;
alter table public.refunds validate constraint refunds_authorized_by_same_gym_fk;
alter table public.gym_classes validate constraint gym_classes_created_by_same_gym_fk;

-- Tighten broad same-gym read policies for sensitive operational data.
drop policy if exists "attendance view" on public.attendance;
create policy "attendance view" on public.attendance for select to anon,authenticated
  using (private.has_permission(gym_id,'attendance.manage'));

drop policy if exists "cancellations view" on public.membership_cancellations;
create policy "cancellations view" on public.membership_cancellations for select to anon,authenticated
  using (private.has_permission(gym_id,'cancellations.manage'));

drop policy if exists "freezes view" on public.membership_freezes;
create policy "freezes view" on public.membership_freezes for select to anon,authenticated
  using (private.has_permission(gym_id,'freezes.manage'));

drop policy if exists "templates view" on public.notification_templates;
create policy "templates view" on public.notification_templates for select to anon,authenticated
  using (private.is_admin(gym_id) or private.has_permission(gym_id,'whatsapp.manage'));

drop policy if exists "payment settings view" on public.payment_method_settings;
create policy "payment settings view" on public.payment_method_settings for select to anon,authenticated
  using (private.is_admin(gym_id)
      or private.has_permission(gym_id,'members.create')
      or private.has_permission(gym_id,'members.renew'));

drop policy if exists "packages permission" on public.membership_packages;
create policy "packages permission" on public.membership_packages for select to anon,authenticated
  using (private.is_admin(gym_id)
      or private.has_permission(gym_id,'packages.manage')
      or private.has_permission(gym_id,'members.create')
      or private.has_permission(gym_id,'members.renew'));

drop policy if exists "users permissions view" on public.user_permissions;
create policy "users permissions view" on public.user_permissions for select to anon,authenticated
  using (exists(select 1 from public.users u
                where u.id=user_permissions.user_id and u.gym_id in (select private.user_gym_ids())
                  and (private.is_admin(u.gym_id) or private.has_permission(u.gym_id,'staff.manage'))));

drop policy if exists "notifications view" on public.notifications;
create policy "notifications view" on public.notifications for select to anon,authenticated
  using (private.has_permission(gym_id,'notifications.send'));

drop policy if exists "notification logs view" on public.notification_logs;
create policy "notification logs view" on public.notification_logs for select to anon,authenticated
  using (exists(select 1 from public.notifications n where n.id=notification_logs.notification_id
                and private.has_permission(n.gym_id,'notifications.send')));

-- Maintenance functions are run by the database scheduler, not browsers.
revoke all on function public.run_expiry_engine() from public,anon,authenticated;

notify pgrst,'reload schema';
