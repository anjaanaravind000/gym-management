create or replace function public.login_with_password(p_username text, p_password text)
returns table (
  user_id uuid,
  username text,
  display_name text,
  role text,
  gym_id uuid,
  session_token text,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = 'public', 'private', 'pg_catalog'
as $$
declare
  v_user public.login_accounts%rowtype;
  v_token text;
  v_expires timestamptz;
begin
  select la.*
    into v_user
  from public.login_accounts as la
  where lower(la.username) = lower(btrim(p_username))
    and la.status = 'active'
  limit 1;

  if not found or v_user.password_hash <> extensions.crypt(p_password, v_user.password_hash) then
    raise exception 'Invalid username or password';
  end if;

  delete from public.login_sessions
  where user_id = v_user.id
     or expires_at <= now();

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  v_expires := now() + interval '7 days';

  insert into public.login_sessions(user_id, token_hash, expires_at)
  values (
    v_user.id,
    encode(extensions.digest(v_token, 'sha256'), 'hex'),
    v_expires
  );

  return query
  select
    v_user.id,
    v_user.username,
    v_user.display_name,
    v_user.role,
    v_user.gym_id,
    v_token,
    v_expires;
end
$$;

revoke all on function public.login_with_password(text,text) from public, authenticated;
grant execute on function public.login_with_password(text,text) to anon;