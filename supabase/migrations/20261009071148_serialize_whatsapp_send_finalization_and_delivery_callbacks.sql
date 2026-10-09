
-- Serialize Meta delivery callbacks and worker finalization for the same provider ID.
-- Both paths take the same transaction-scoped advisory lock before touching the
-- notification row/logs, preventing a callback from being stranded in the pending buffer.
create or replace function public.record_whatsapp_delivery_status_internal(p_provider_message_id text,p_status text,p_error_message text default null)
returns integer language plpgsql security definer
set search_path to 'public','private','pg_catalog'
as $function$
declare v_log record;v_latest_id uuid;v_final public.delivery_status;v_current public.delivery_status;v_target public.delivery_status;v_count integer:=0;
begin
 if nullif(trim(p_provider_message_id),'') is null or p_status not in('sent','delivered','read','failed') then return 0; end if;
 perform pg_advisory_xact_lock(hashtextextended(trim(p_provider_message_id),0));
 delete from private.whatsapp_webhook_pending where received_at<now()-interval '7 days';
 if not exists(select 1 from public.notification_logs where provider_message_id=trim(p_provider_message_id)) then
   insert into private.whatsapp_webhook_pending(provider_message_id,delivery_status,error_message,received_at)
   values(trim(p_provider_message_id),p_status::public.delivery_status,case when p_status='failed' then left(coalesce(p_error_message,'Delivery failed'),4000) else null end,now())
   on conflict(provider_message_id) do update set
     delivery_status=case
       when private.whatsapp_delivery_status_rank(excluded.delivery_status)>private.whatsapp_delivery_status_rank(private.whatsapp_webhook_pending.delivery_status)
         then excluded.delivery_status else private.whatsapp_webhook_pending.delivery_status end,
     error_message=case
       when (case when private.whatsapp_delivery_status_rank(excluded.delivery_status)>private.whatsapp_delivery_status_rank(private.whatsapp_webhook_pending.delivery_status) then excluded.delivery_status else private.whatsapp_webhook_pending.delivery_status end)='failed'
         then coalesce(excluded.error_message,private.whatsapp_webhook_pending.error_message) else null end,
     received_at=now();
   return 0;
 end if;
 for v_log in
   select l.id,l.notification_id,l.delivery_status from public.notification_logs l
   where l.provider_message_id=trim(p_provider_message_id) for update
 loop
   v_final:=case when private.whatsapp_delivery_status_rank(v_log.delivery_status)>private.whatsapp_delivery_status_rank(p_status::public.delivery_status)
     then v_log.delivery_status else p_status::public.delivery_status end;
   update public.notification_logs set
      delivery_status=v_final,
      status=case when v_final='failed' then 'failed'::public.notification_status else 'sent'::public.notification_status end,
      error_message=case when v_final='failed' then left(coalesce(p_error_message,error_message,'Delivery failed'),4000) else null end
   where id=v_log.id;
   select l.id into v_latest_id from public.notification_logs l where l.notification_id=v_log.notification_id
   order by l.attempt_at desc,l.created_at desc,l.id desc limit 1;
   if v_latest_id=v_log.id then
     select n.delivery_status into v_current from public.notifications n where n.id=v_log.notification_id;
     v_target:=case when private.whatsapp_delivery_status_rank(v_current)>private.whatsapp_delivery_status_rank(v_final) then v_current else v_final end;
     update public.notifications n set
       delivery_status=v_target,
       status=case when v_target='failed' then 'failed'::public.notification_status else 'sent'::public.notification_status end,
       error_message=case when v_target='failed' then left(coalesce(p_error_message,'Delivery failed'),4000) else null end,
       retry_count=case when v_target='failed' and n.delivery_status<>'failed' then coalesce(n.retry_count,0)+1 else n.retry_count end,
       sent_at=case when v_target in('sent','delivered','read') then coalesce(n.sent_at,now()) else n.sent_at end
     where n.id=v_log.notification_id and n.status<>'cancelled';
   end if;
   v_count:=v_count+1;
 end loop;
 return v_count;
end
$function$;

create or replace function public.finish_whatsapp_notification_internal(
 p_notification_id uuid,p_provider_message_id text,p_success boolean,p_error_message text,p_previous_retry_count integer
)
returns void language plpgsql security definer
set search_path to 'public','private','pg_catalog'
as $function$
declare v_notification public.notifications%rowtype;v_log_id uuid;v_initial public.delivery_status;v_pending public.delivery_status;
 v_final public.delivery_status;v_error text;v_retry integer;
begin
 if nullif(trim(p_provider_message_id),'') is not null then
   perform pg_advisory_xact_lock(hashtextextended(trim(p_provider_message_id),0));
 end if;
 select * into v_notification from public.notifications where id=p_notification_id for update;
 if not found then raise exception 'Notification not found'; end if;
 if v_notification.channel<>'whatsapp' then raise exception 'Only WhatsApp notifications can be finalized here'; end if;
 v_initial:=case when p_success then 'sent'::public.delivery_status else 'failed'::public.delivery_status end;
 v_error:=case when p_success then null else left(coalesce(p_error_message,'Delivery failed'),4000) end;

 if nullif(trim(p_provider_message_id),'') is not null then
   insert into public.notification_logs(notification_id,status,delivery_status,provider_message_id,error_message)
   values(p_notification_id,case when p_success then 'sent'::public.notification_status else 'failed'::public.notification_status end,
     v_initial,trim(p_provider_message_id),v_error)
   on conflict(provider_message_id) where provider_message_id is not null do nothing
   returning id into v_log_id;
   if v_log_id is null then
     select id into v_log_id from public.notification_logs where provider_message_id=trim(p_provider_message_id);
     if not exists(select 1 from public.notification_logs where id=v_log_id and notification_id=p_notification_id) then
       raise exception 'Provider message ID is already linked to a different notification';
     end if;
   end if;
 else
   insert into public.notification_logs(notification_id,status,delivery_status,provider_message_id,error_message)
   values(p_notification_id,case when p_success then 'sent'::public.notification_status else 'failed'::public.notification_status end,v_initial,null,v_error)
   returning id into v_log_id;
 end if;

 v_final:=v_initial;
 if nullif(trim(p_provider_message_id),'') is not null then
   select delivery_status,error_message into v_pending,v_error from private.whatsapp_webhook_pending
   where provider_message_id=trim(p_provider_message_id) for update;
   if found then
     if private.whatsapp_delivery_status_rank(v_pending)>private.whatsapp_delivery_status_rank(v_final) then v_final:=v_pending; end if;
     if v_final='failed' then v_error:=coalesce(v_error,p_error_message,'Delivery failed'); else v_error:=null; end if;
     delete from private.whatsapp_webhook_pending where provider_message_id=trim(p_provider_message_id);
   end if;
 end if;

 if private.whatsapp_delivery_status_rank(v_notification.delivery_status)>private.whatsapp_delivery_status_rank(v_final) then
   v_final:=v_notification.delivery_status;
 end if;
 if v_final='failed' then v_error:=left(coalesce(v_error,p_error_message,'Delivery failed'),4000); else v_error:=null; end if;

 update public.notification_logs set
   status=case when v_final='failed' then 'failed'::public.notification_status else 'sent'::public.notification_status end,
   delivery_status=v_final,error_message=v_error
 where id=v_log_id;

 if v_notification.status<>'cancelled' then
   v_retry:=greatest(coalesce(v_notification.retry_count,0),coalesce(p_previous_retry_count,0)+case when v_final='failed' then 1 else 0 end);
   update public.notifications set
     status=case when v_final='failed' then 'failed'::public.notification_status else 'sent'::public.notification_status end,
     delivery_status=v_final,error_message=v_error,retry_count=v_retry,
     sent_at=case when v_final in('sent','delivered','read') then coalesce(sent_at,now()) else sent_at end
   where id=p_notification_id;
 end if;
 delete from private.whatsapp_notification_claims where notification_id=p_notification_id;
end
$function$;

revoke all on function public.record_whatsapp_delivery_status_internal(text,text,text) from public,anon,authenticated;
grant execute on function public.record_whatsapp_delivery_status_internal(text,text,text) to service_role;
revoke all on function public.finish_whatsapp_notification_internal(uuid,text,boolean,text,integer) from public,anon,authenticated;
grant execute on function public.finish_whatsapp_notification_internal(uuid,text,boolean,text,integer) to service_role;
