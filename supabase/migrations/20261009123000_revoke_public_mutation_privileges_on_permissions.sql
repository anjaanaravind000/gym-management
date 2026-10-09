-- The permissions lookup is read-only. TRUNCATE bypasses RLS, so remove all direct mutation privileges.
revoke insert,update,delete,truncate,references,trigger on public.permissions from anon,authenticated;
