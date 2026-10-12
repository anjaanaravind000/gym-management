create policy login_accounts_deny_direct_browser_access
  on public.login_accounts
  for all
  to anon, authenticated
  using (false)
  with check (false);

create policy login_sessions_deny_direct_browser_access
  on public.login_sessions
  for all
  to anon, authenticated
  using (false)
  with check (false);
