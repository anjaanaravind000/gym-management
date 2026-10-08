create extension if not exists pg_net;

create table if not exists private.whatsapp_worker_config(
 id boolean primary key default true check(id),
 secret text not null,
 updated_at timestamptz not null default now()
);
insert into private.whatsapp_worker_config(id,secret)
values(true,encode(extensions.gen_random_bytes(32),'hex'))
on conflict(id) do nothing;
revoke all on private.whatsapp_worker_config from public,anon,authenticated;

create or replace function public.get_whatsapp_worker_secret_internal()
returns text
language sql
security definer
set search_path to 'private','pg_catalog'
as $function$
 select secret from private.whatsapp_worker_config where id=true limit 1
$function$;
revoke all on function public.get_whatsapp_worker_secret_internal() from public,anon,authenticated;
grant execute on function public.get_whatsapp_worker_secret_internal() to service_role;

select cron.unschedule(jobid) from cron.job where jobname='gym-whatsapp-worker';
select cron.schedule(
 'gym-whatsapp-worker',
 '* * * * *',
 $$select net.http_post(
   url := 'https://pifivtjonppliyvetcqk.supabase.co/functions/v1/whatsapp-worker',
   headers := jsonb_build_object('Content-Type','application/json','x-worker-secret',public.get_whatsapp_worker_secret_internal()),
   body := '{}'::jsonb
 );$$
);