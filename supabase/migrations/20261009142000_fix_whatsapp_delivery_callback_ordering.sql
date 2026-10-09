-- Meta callbacks may arrive out of order. Delivered/read must not be downgraded,
-- but a failed callback must be allowed to fail a message that was merely sent.
create or replace function public.record_whatsapp_delivery_status_internal(p_provider_message_id text,p_status text,p_error_message text default null)
returns integer language plpgsql security definer
set search_path to 'public','private','pg_catalog'
as $$
declare v_log record;v_latest_id uuid;v_final public.delivery_status;v_current public.delivery_status;v_target public.delivery_status;v_count integer:=0;
begin
 if nullif(trim(p_provider_message_id),'') is null or p_status not in('sent','delivered','read','failed') then return 0; end if;
 for v_log in
   select l.id,l.notification_id,l.delivery_status from public.notification_logs l where l.provider_message_id=p_provider_message_id for update
 loop
   v_final:=case when v_log.delivery_status in('delivered','read') and p_status not in('delivered','read')
       then v_log.delivery_status else p_status::public.delivery_status end;
   update public.notification_logs set
      delivery_status=v_final,
      status=case when v_final='failed' then 'failed'::public.notification_status else 'sent'::public.notification_status end,
      error_message=case when v_final='failed' then left(coalesce(p_error_message,'Delivery failed'),4000) else null end
   where id=v_log.id;
   select l.id into v_latest_id from public.notification_logs l where l.notification_id=v_log.notification_id
   order by l.attempt_at desc,l.created_at desc,l.id desc limit 1;
   if v_latest_id=v_log.id then
     select n.delivery_status into v_current from public.notifications n where n.id=v_log.notification_id;
     v_target:=case when v_current in('delivered','read') and p_status not in('delivered','read') then v_current else v_final end;
     update public.notifications n set
       delivery_status=v_target,
       status=case when v_target='failed' then 'failed'::public.notification_status else 'sent'::public.notification_status end,
       error_message=case when v_target='failed' then left(coalesce(p_error_message,'Delivery failed'),4000) else null end,
       sent_at=case when v_target in('sent','delivered','read') then coalesce(n.sent_at,now()) else n.sent_at end
     where n.id=v_log.notification_id and n.status<>'cancelled';
   end if;
   v_count:=v_count+1;
 end loop;
 return v_count;
end
$$;
