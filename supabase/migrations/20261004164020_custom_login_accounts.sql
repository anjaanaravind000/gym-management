create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.login_accounts (
  id uuid primary key default extensions.gen_random_uuid(),
  username text not null,
  password_hash text not null,
  display_name text not null default '',
  role text not null default 'admin',
  status text not null default 'active',
  gym_id uuid references public.gyms(id) on delete set null,
  email text,
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists login_accounts_username_lower_uq
  on public.login_accounts (lower(username));

create table if not exists public.login_sessions (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references public.login_accounts(id) on delete cascade,
  token_hash text not null unique,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create index if not exists login_sessions_user_id_idx on public.login_sessions(user_id);
create index if not exists login_sessions_expires_at_idx on public.login_sessions(expires_at);

alter table public.login_accounts enable row level security;
alter table public.login_sessions enable row level security;
revoke all on table public.login_accounts, public.login_sessions from public, anon, authenticated;
grant all on table public.login_accounts, public.login_sessions to service_role;

create or replace function private.current_app_user_id()
returns uuid
language sql
stable
security definer
set search_path = 'public', 'private', 'pg_catalog'
as $$
  select s.user_id
  from public.login_sessions s
  where s.token_hash = encode(
    extensions.digest(
      coalesce(current_setting('request.headers', true)::json->>'x-gym-session', ''),
      'sha256'
    ),
    'hex'
  )
  and s.expires_at > now()
  limit 1
$$;

revoke all on function private.current_app_user_id() from public, anon, authenticated;

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
  select * into v_user
  from public.login_accounts
  where lower(username) = lower(btrim(p_username))
    and status = 'active'
  limit 1;

  if not found or v_user.password_hash <> extensions.crypt(p_password, v_user.password_hash) then
    raise exception 'Invalid username or password';
  end if;

  delete from public.login_sessions where user_id = v_user.id or expires_at <= now();

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  v_expires := now() + interval '7 days';

  insert into public.login_sessions(user_id, token_hash, expires_at)
  values (v_user.id, encode(extensions.digest(v_token, 'sha256'), 'hex'), v_expires);

  return query select v_user.id, v_user.username, v_user.display_name, v_user.role, v_user.gym_id, v_token, v_expires;
end
$$;

revoke all on function public.login_with_password(text,text) from public, authenticated;
grant execute on function public.login_with_password(text,text) to anon;

create or replace function public.get_current_app_session()
returns table (
  user_id uuid,
  username text,
  display_name text,
  role text,
  gym_id uuid,
  expires_at timestamptz
)
language sql
stable
security definer
set search_path = 'public', 'private', 'pg_catalog'
as $$
  select a.id, a.username, a.display_name, a.role, a.gym_id, s.expires_at
  from public.login_sessions s
  join public.login_accounts a on a.id = s.user_id
  where s.token_hash = encode(
    extensions.digest(
      coalesce(current_setting('request.headers', true)::json->>'x-gym-session', ''),
      'sha256'
    ),
    'hex'
  )
  and s.expires_at > now()
  and a.status = 'active'
  limit 1
$$;

revoke all on function public.get_current_app_session() from public, authenticated;
grant execute on function public.get_current_app_session() to anon;

create or replace function public.logout_app()
returns void
language sql
security definer
set search_path = 'public', 'private', 'pg_catalog'
as $$
  delete from public.login_sessions
  where token_hash = encode(
    extensions.digest(
      coalesce(current_setting('request.headers', true)::json->>'x-gym-session', ''),
      'sha256'
    ),
    'hex'
  )
$$;

revoke all on function public.logout_app() from public, authenticated;
grant execute on function public.logout_app() to anon;

insert into public.login_accounts (username, password_hash, display_name, role, status)
select 'Admin', '$2y$12$wQ4JNolNofEA6Lnpa9wyW.99Ftk2UllEk9TI/ccjs9FTjtXsncLBu', 'Gym Administrator', 'admin', 'active'
where not exists (select 1 from public.login_accounts where lower(username) = 'admin');

update public.login_accounts
set password_hash = '$2y$12$wQ4JNolNofEA6Lnpa9wyW.99Ftk2UllEk9TI/ccjs9FTjtXsncLBu',
    display_name = 'Gym Administrator',
    role = 'admin',
    status = 'active',
    updated_at = now()
where lower(username) = 'admin';