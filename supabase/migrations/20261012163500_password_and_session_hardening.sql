-- Tighten session revocation and require stronger credentials for newly created staff accounts.
create or replace function private.current_app_user_id()
returns uuid
language sql
stable
security definer
set search_path to 'public','private','pg_catalog'
as $function$
  select s.user_id
  from public.login_sessions s
  join public.login_accounts a on a.id=s.user_id and a.status='active'
  where s.token_hash=encode(
    extensions.digest(
      coalesce(current_setting('request.headers',true)::json->>'x-gym-session',''),
      'sha256'
    ),
    'hex'
  )
  and s.expires_at>now()
  limit 1
$function$;
revoke all on function private.current_app_user_id() from public,anon,authenticated;

do $migration$
declare
  v_sql text;
  v_old text;
  v_new text;
begin
  v_sql:=pg_get_functiondef('public.create_staff_account(uuid,text,text,text,text,text,user_role)'::regprocedure);
  v_old:='if p_password is null or length(p_password)<8 then raise exception ''Password must be at least 8 characters''; end if;';
  v_new:='if p_password is null or length(p_password)<12 or p_password !~ ''[A-Z]'' or p_password !~ ''[a-z]'' or p_password !~ ''[0-9]'' or p_password !~ ''[^A-Za-z0-9]'' then raise exception ''Password must be at least 12 characters and include uppercase, lowercase, number, and symbol''; end if;';
  if position(v_new in v_sql)>0 then
    return;
  end if;
  if position(v_old in v_sql)=0 then
    raise exception 'Could not locate staff password validation; migration stopped';
  end if;
  execute replace(v_sql,v_old,v_new);
end
$migration$;

notify pgrst,'reload schema';
