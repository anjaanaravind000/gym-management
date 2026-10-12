-- Keep RLS read and write policies independent so permissive policy ORs do not broaden SELECT.
do $policies$
begin
  -- attendance
  drop policy if exists "attendance manage" on public.attendance;
  create policy "attendance insert manage" on public.attendance for insert to anon,authenticated with check (private.has_permission(gym_id,'attendance.manage'));
  create policy "attendance update manage" on public.attendance for update to anon,authenticated using (private.has_permission(gym_id,'attendance.manage')) with check (private.has_permission(gym_id,'attendance.manage'));
  create policy "attendance delete manage" on public.attendance for delete to anon,authenticated using (private.has_permission(gym_id,'attendance.manage'));

  -- settings and gym profile
  drop policy if exists "settings manage" on public.gym_settings;
  create policy "settings insert manage" on public.gym_settings for insert to anon,authenticated with check (private.is_admin(gym_id));
  create policy "settings update manage" on public.gym_settings for update to anon,authenticated using (private.is_admin(gym_id)) with check (private.is_admin(gym_id));
  create policy "settings delete manage" on public.gym_settings for delete to anon,authenticated using (private.is_admin(gym_id));

  drop policy if exists "admins can manage gym" on public.gyms;
  create policy "admins insert gym" on public.gyms for insert to anon,authenticated with check (private.is_admin(id));
  create policy "admins update gym" on public.gyms for update to anon,authenticated using (private.is_admin(id)) with check (private.is_admin(id));
  create policy "admins delete gym" on public.gyms for delete to anon,authenticated using (private.is_admin(id));

  -- membership history and freeze records
  drop policy if exists "cancellations manage" on public.membership_cancellations;
  create policy "cancellations insert manage" on public.membership_cancellations for insert to anon,authenticated with check (private.has_permission(gym_id,'cancellations.manage'));
  create policy "cancellations update manage" on public.membership_cancellations for update to anon,authenticated using (private.has_permission(gym_id,'cancellations.manage')) with check (private.has_permission(gym_id,'cancellations.manage'));
  create policy "cancellations delete manage" on public.membership_cancellations for delete to anon,authenticated using (private.has_permission(gym_id,'cancellations.manage'));

  drop policy if exists "freezes manage" on public.membership_freezes;
  create policy "freezes insert manage" on public.membership_freezes for insert to anon,authenticated with check (private.has_permission(gym_id,'freezes.manage'));
  create policy "freezes update manage" on public.membership_freezes for update to anon,authenticated using (private.has_permission(gym_id,'freezes.manage')) with check (private.has_permission(gym_id,'freezes.manage'));
  create policy "freezes delete manage" on public.membership_freezes for delete to anon,authenticated using (private.has_permission(gym_id,'freezes.manage'));

  -- packages
  drop policy if exists "packages admin manage" on public.membership_packages;
  create policy "packages insert manage" on public.membership_packages for insert to anon,authenticated with check (private.is_admin(gym_id));
  create policy "packages update manage" on public.membership_packages for update to anon,authenticated using (private.is_admin(gym_id)) with check (private.is_admin(gym_id));
  create policy "packages delete manage" on public.membership_packages for delete to anon,authenticated using (private.is_admin(gym_id));

  -- WhatsApp notification templates
  drop policy if exists "templates manage" on public.notification_templates;
  create policy "templates insert manage" on public.notification_templates for insert to anon,authenticated with check (private.is_admin(gym_id) or private.has_permission(gym_id,'whatsapp.manage'));
  create policy "templates update manage" on public.notification_templates for update to anon,authenticated using (private.is_admin(gym_id) or private.has_permission(gym_id,'whatsapp.manage')) with check (private.is_admin(gym_id) or private.has_permission(gym_id,'whatsapp.manage'));
  create policy "templates delete manage" on public.notification_templates for delete to anon,authenticated using (private.is_admin(gym_id) or private.has_permission(gym_id,'whatsapp.manage'));

  -- Payment-method settings remain readable to member-create/renew operators, but writes are admin-only.
  drop policy if exists "payment settings manage" on public.payment_method_settings;
  create policy "payment settings insert manage" on public.payment_method_settings for insert to anon,authenticated with check (private.is_admin(gym_id));
  create policy "payment settings update manage" on public.payment_method_settings for update to anon,authenticated using (private.is_admin(gym_id)) with check (private.is_admin(gym_id));
  create policy "payment settings delete manage" on public.payment_method_settings for delete to anon,authenticated using (private.is_admin(gym_id));

  -- Refund history remains readable to payment viewers, writable only with refund permission.
  drop policy if exists "refunds manage" on public.refunds;
  create policy "refunds insert manage" on public.refunds for insert to anon,authenticated with check (private.has_permission(gym_id,'payments.refund'));
  create policy "refunds update manage" on public.refunds for update to anon,authenticated using (private.has_permission(gym_id,'payments.refund')) with check (private.has_permission(gym_id,'payments.refund'));
  create policy "refunds delete manage" on public.refunds for delete to anon,authenticated using (private.has_permission(gym_id,'payments.refund'));

  -- Staff and permission tables
  drop policy if exists "admins manage permissions" on public.user_permissions;
  create policy "admins insert permissions" on public.user_permissions for insert to anon,authenticated
    with check (exists(select 1 from public.users u where u.id=user_permissions.user_id and private.is_admin(u.gym_id)));
  create policy "admins update permissions" on public.user_permissions for update to anon,authenticated
    using (exists(select 1 from public.users u where u.id=user_permissions.user_id and private.is_admin(u.gym_id)))
    with check (exists(select 1 from public.users u where u.id=user_permissions.user_id and private.is_admin(u.gym_id)));
  create policy "admins delete permissions" on public.user_permissions for delete to anon,authenticated
    using (exists(select 1 from public.users u where u.id=user_permissions.user_id and private.is_admin(u.gym_id)));

  drop policy if exists "admins manage users" on public.users;
  create policy "admins insert users" on public.users for insert to anon,authenticated with check (private.is_admin(gym_id));
  create policy "admins update users" on public.users for update to anon,authenticated using (private.is_admin(gym_id)) with check (private.is_admin(gym_id));
  create policy "admins delete users" on public.users for delete to anon,authenticated using (private.is_admin(gym_id));
end
$policies$;

-- Cover every new composite foreign key with an index on its referencing columns.
create index if not exists members_assigned_coach_gym_fk_idx on public.members(assigned_coach_id,gym_id);
create index if not exists members_created_by_gym_fk_idx on public.members(created_by,gym_id);
create index if not exists memberships_member_gym_fk_idx on public.memberships(member_id,gym_id);
create index if not exists memberships_package_gym_fk_idx on public.memberships(package_id,gym_id);
create index if not exists memberships_previous_chain_fk_idx on public.memberships(previous_membership_id,member_id,gym_id);
create index if not exists memberships_created_by_gym_fk_idx on public.memberships(created_by,gym_id);
create index if not exists payments_member_gym_fk_idx on public.payments(member_id,gym_id);
create index if not exists payments_membership_member_gym_fk_idx on public.payments(membership_id,member_id,gym_id);
create index if not exists payments_recorded_by_gym_fk_idx on public.payments(recorded_by,gym_id);
create index if not exists payments_original_gym_fk_idx on public.payments(original_payment_id,gym_id);
create index if not exists attendance_member_gym_fk_idx on public.attendance(member_id,gym_id);
create index if not exists freezes_membership_gym_fk_idx on public.membership_freezes(membership_id,gym_id);
create index if not exists freezes_created_by_gym_fk_idx on public.membership_freezes(created_by,gym_id);
create index if not exists cancellations_membership_gym_fk_idx on public.membership_cancellations(membership_id,gym_id);
create index if not exists cancellations_cancelled_by_gym_fk_idx on public.membership_cancellations(cancelled_by,gym_id);
create index if not exists class_sessions_class_gym_fk_idx on public.class_sessions(class_id,gym_id);
create index if not exists class_sessions_instructor_gym_fk_idx on public.class_sessions(instructor_id,gym_id);
create index if not exists class_sessions_created_by_gym_fk_idx on public.class_sessions(created_by,gym_id);
create index if not exists class_bookings_member_gym_fk_idx on public.class_bookings(member_id,gym_id);
create index if not exists class_bookings_session_gym_fk_idx on public.class_bookings(session_id,gym_id);
create index if not exists leads_assigned_to_gym_fk_idx on public.leads(assigned_to,gym_id);
create index if not exists leads_created_by_gym_fk_idx on public.leads(created_by,gym_id);
create index if not exists leads_member_gym_fk_idx on public.leads(converted_member_id,gym_id);
create index if not exists leads_package_gym_fk_idx on public.leads(interested_package_id,gym_id);
create index if not exists notifications_member_gym_fk_idx on public.notifications(member_id,gym_id);
create index if not exists notifications_membership_chain_fk_idx on public.notifications(membership_id,member_id,gym_id);
create index if not exists expenses_created_by_gym_fk_idx on public.expenses(created_by,gym_id);
create index if not exists refunds_payment_gym_fk_idx on public.refunds(payment_id,gym_id);
create index if not exists refunds_authorized_by_gym_fk_idx on public.refunds(authorized_by,gym_id);
create index if not exists gym_classes_created_by_gym_fk_idx on public.gym_classes(created_by,gym_id);

notify pgrst,'reload schema';
