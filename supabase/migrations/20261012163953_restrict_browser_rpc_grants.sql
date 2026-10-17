-- This frontend uses its custom x-gym-session token and the Supabase anon role.
-- Strip inherited/public and unused Supabase-authenticated execution, then grant only
-- the browser RPCs referenced by src/data.ts. Internal service_role grants remain intact.
do $grants$
declare
  r record;
  v_browser_rpc_names text[] := array[
    'book_class','bootstrap_gym','cancel_class_booking','cancel_class_session',
    'cancel_membership','cancel_notification','checkout_attendance','convert_lead',
    'create_member_from_lead','create_member_registration_v2','create_old_member',
    'create_renewal','create_staff_account','delete_lead','delete_member',
    'disconnect_whatsapp_connection','export_gym_backup','freeze_membership',
    'get_analytics','get_class_timetable','get_current_app_session','get_finance_summary',
    'get_notification_counts','get_whatsapp_connection','login_with_password','logout_app',
    'mark_notification_read','queue_member_notification','record_attendance','record_payment',
    'refund_payment','reverse_payment','save_class','save_class_session','save_expense',
    'save_gym_profile','save_gym_settings','save_lead','save_notification_template',
    'save_package','save_payment_method_setting','save_whatsapp_connection',
    'set_class_booking_attendance','set_member_photo','set_member_status',
    'set_staff_permission','set_staff_role','sync_membership_statuses',
    'unfreeze_membership','update_member_profile','void_expense'
  ];
begin
  for r in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prokind='f'
  loop
    execute format('revoke execute on function %s from public, anon, authenticated',r.signature);
  end loop;

  for r in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prokind='f' and p.proname=any(v_browser_rpc_names)
  loop
    execute format('grant execute on function %s to anon',r.signature);
  end loop;
end
$grants$;

notify pgrst,'reload schema';
