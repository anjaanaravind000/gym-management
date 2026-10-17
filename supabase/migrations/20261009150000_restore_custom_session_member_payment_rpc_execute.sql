-- Reassert the RPC grants required by the custom x-gym-session auth flow.
-- SECURITY DEFINER bodies must continue to validate session identity and gym permissions.
begin;
grant usage on schema private to anon, authenticated;
revoke execute on function public.bootstrap_gym(text,text,text,text) from public;
grant execute on function public.bootstrap_gym(text,text,text,text) to anon, authenticated;
revoke execute on function private.bootstrap_gym(text,text,text,text) from public;
grant execute on function private.bootstrap_gym(text,text,text,text) to anon, authenticated;
revoke execute on function public.sync_membership_statuses() from public;
grant execute on function public.sync_membership_statuses() to anon, authenticated;
revoke execute on function public.create_member_registration_v2(uuid,text,text,text,date,text,text,text,text,text,uuid,integer,date,date,numeric,numeric,numeric,payment_method,text,text,date,uuid,boolean) from public;
grant execute on function public.create_member_registration_v2(uuid,text,text,text,date,text,text,text,text,text,uuid,integer,date,date,numeric,numeric,numeric,payment_method,text,text,date,uuid,boolean) to anon, authenticated;
revoke execute on function public.create_old_member(uuid,text,text,text,date,text,text,text,text,text,date,member_status,uuid,boolean,boolean,uuid,date,date,membership_status,numeric,integer,numeric,numeric,payment_method,date,text,text) from public;
grant execute on function public.create_old_member(uuid,text,text,text,date,text,text,text,text,text,date,member_status,uuid,boolean,boolean,uuid,date,date,membership_status,numeric,integer,numeric,numeric,payment_method,date,text,text) to anon, authenticated;
revoke execute on function public.create_renewal(uuid,uuid,uuid,integer,date,numeric,numeric,numeric,payment_method,text,text,date) from public;
grant execute on function public.create_renewal(uuid,uuid,uuid,integer,date,numeric,numeric,numeric,payment_method,text,text,date) to anon, authenticated;
revoke execute on function public.record_payment(uuid,uuid,uuid,numeric,payment_method,text,timestamp with time zone,text) from public;
grant execute on function public.record_payment(uuid,uuid,uuid,numeric,payment_method,text,timestamp with time zone,text) to anon, authenticated;
notify pgrst, 'reload schema';
commit;
