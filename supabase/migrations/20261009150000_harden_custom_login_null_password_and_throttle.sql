
create table if not exists private.login_rate_limits (
  scope text not null check (scope in ('ip','combo')),
  key_hash text not null,
  window_started_at timestamptz not null default clock_timestamp(),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  blocked_until timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  primary key(scope,key_hash)
);
create index if not exists login_rate_limits_window_idx on private.login_rate_limits(window_started_at);
revoke all on table private.login_rate_limits from public,anon,authenticated;

create or replace function public.login_with_password(p_username text,p_password text)
returns table(user_id uuid,username text,display_name text,role text,gym_id uuid,session_token text,expires_at timestamptz)
language plpgsql security definer
set search_path to 'public','private','pg_catalog'
as $function$
declare
 v_user public.login_accounts%rowtype;v_token text;v_expires timestamptz;v_now timestamptz:=clock_timestamp();
 v_headers jsonb:=coalesce(nullif(current_setting('request.headers',true),''),'{}')::jsonb;
 v_ip text;v_ip_key text;v_combo_key text;v_attempt_count integer;v_window_started_at timestamptz;v_blocked_until timestamptz;v_password_ok boolean:=false;
begin
 v_ip:=coalesce(nullif(trim(split_part(v_headers->>'x-forwarded-for',',',1)),''),nullif(trim(v_headers->>'x-real-ip'),''),nullif(trim(v_headers->>'cf-connecting-ip'),''));
 if v_ip is not null then v_ip_key:=encode(extensions.digest(v_ip,'sha256'),'hex'); end if;
 v_combo_key:=encode(extensions.digest(coalesce(v_ip,'')||chr(10)||lower(btrim(coalesce(p_username,''))),'sha256'),'hex');

 delete from private.login_rate_limits where window_started_at<v_now-interval '2 days' and coalesce(blocked_until,window_started_at)<v_now-interval '2 days';

 if v_ip_key is not null then
   insert into private.login_rate_limits(scope,key_hash,window_started_at,attempt_count) values('ip',v_ip_key,v_now,0) on conflict(scope,key_hash) do nothing;
   select attempt_count,window_started_at,blocked_until into v_attempt_count,v_window_started_at,v_blocked_until
   from private.login_rate_limits where scope='ip' and key_hash=v_ip_key for update;
   if v_blocked_until is not null and v_blocked_until>v_now then return; end if;
   if v_window_started_at<=v_now-interval '15 minutes' then
     update private.login_rate_limits set window_started_at=v_now,attempt_count=0,blocked_until=null,updated_at=v_now where scope='ip' and key_hash=v_ip_key;
     v_attempt_count:=0;
   end if;
   if v_attempt_count>=25 then
     update private.login_rate_limits set blocked_until=v_now+interval '15 minutes',updated_at=v_now where scope='ip' and key_hash=v_ip_key;
     return;
   end if;
 end if;

 insert into private.login_rate_limits(scope,key_hash,window_started_at,attempt_count) values('combo',v_combo_key,v_now,0) on conflict(scope,key_hash) do nothing;
 select attempt_count,window_started_at,blocked_until into v_attempt_count,v_window_started_at,v_blocked_until
 from private.login_rate_limits where scope='combo' and key_hash=v_combo_key for update;
 if v_blocked_until is not null and v_blocked_until>v_now then return; end if;
 if v_window_started_at<=v_now-interval '15 minutes' then
   update private.login_rate_limits set window_started_at=v_now,attempt_count=0,blocked_until=null,updated_at=v_now where scope='combo' and key_hash=v_combo_key;
   v_attempt_count:=0;
 end if;
 if v_attempt_count>=8 then
   update private.login_rate_limits set blocked_until=v_now+interval '15 minutes',updated_at=v_now where scope='combo' and key_hash=v_combo_key;
   return;
 end if;

 select la.* into v_user from public.login_accounts la
 where lower(la.username)=lower(btrim(coalesce(p_username,''))) and la.status='active' limit 1;
 if found and p_password is not null and length(p_password)>0 then
   v_password_ok:=v_user.password_hash=extensions.crypt(p_password,v_user.password_hash);
 end if;

 if not coalesce(v_password_ok,false) then
   if v_ip_key is not null then
     update private.login_rate_limits set attempt_count=attempt_count+1,
       blocked_until=case when attempt_count+1>=25 then v_now+interval '15 minutes' else null end,updated_at=v_now
     where scope='ip' and key_hash=v_ip_key;
   end if;
   update private.login_rate_limits set attempt_count=attempt_count+1,
     blocked_until=case when attempt_count+1>=8 then v_now+interval '15 minutes' else null end,updated_at=v_now
   where scope='combo' and key_hash=v_combo_key;
   return;
 end if;

 update private.login_rate_limits set window_started_at=v_now,attempt_count=0,blocked_until=null,updated_at=v_now where scope='combo' and key_hash=v_combo_key;
 delete from public.login_sessions ls where ls.user_id=v_user.id or ls.expires_at<=v_now;
 v_token:=encode(extensions.gen_random_bytes(32),'hex');
 v_expires:=v_now+interval '7 days';
 insert into public.login_sessions(user_id,token_hash,expires_at) values(v_user.id,encode(extensions.digest(v_token,'sha256'),'hex'),v_expires);
 return query select v_user.id,v_user.username,v_user.display_name,v_user.role,v_user.gym_id,v_token,v_expires;
end
$function$;
