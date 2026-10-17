-- Prevent newly created functions owned by postgres from receiving the
-- built-in PUBLIC EXECUTE grant. Callers must be granted explicitly.
alter default privileges for role postgres
  revoke execute on functions from public, anon, authenticated;
