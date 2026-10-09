create or replace function public.queue_member_notification(
 p_gym_id uuid,
 p_member_id uuid,
 p_membership_id uuid default null,
 p_channel public.notification_channel default 'in_app',
 p_notification_type text default 'manual_message',
 p_message_body text default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public','private','pg_catalog'
as $function$
declare v_id uuid;v_tz text;
begin
 if not private.has_permission(p_gym_id,'notifications.send') then raise exception 'Unauthorized'; end if;
 if p_channel='whatsapp' then
   if not private.has_permission(p_gym_id,'whatsapp.manage') then raise exception 'Unauthorized'; end if;
   if not exists(select 1 from private.whatsapp_connections c where c.gym_id=p_gym_id and c.enabled and c.last_test_ok is true) then
     raise exception 'WhatsApp connection must be tested successfully before queuing messages';
   end if;
 end if;
 if p_notification_type='manual_message' and nullif(trim(p_message_body),'') is null then raise exception 'Message body is required'; end if;
 if not exists(select 1 from public.members where id=p_member_id and gym_id=p_gym_id) then raise exception 'Member not found'; end if;
 if p_membership_id is not null and not exists(select 1 from public.memberships where id=p_membership_id and member_id=p_member_id and gym_id=p_gym_id) then raise exception 'Invalid membership'; end if;
 select timezone into v_tz from public.gyms where id=p_gym_id;
 if v_tz is null then raise exception 'Gym timezone is not configured'; end if;
 insert into public.notifications(gym_id,member_id,membership_id,notification_type,channel,scheduled_at,scheduled_date,status,delivery_status,message_body)
 values(p_gym_id,p_member_id,p_membership_id,p_notification_type,p_channel,now(),(now() at time zone v_tz)::date,'queued','pending',nullif(trim(p_message_body),''))
 returning id into v_id;
 return v_id;
end
$function$;