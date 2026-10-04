update public.login_accounts
set password_hash=replace(password_hash,'$2y$','$2a$'),updated_at=now()
where lower(username)='admin'
  and password_hash like '$2y$%';