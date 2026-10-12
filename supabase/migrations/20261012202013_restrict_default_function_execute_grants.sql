-- New app functions created by the migration owner should not become public
-- API endpoints by default. Existing function grants are unchanged: required
-- browser RPCs must be explicitly granted in their own migrations.
alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated;
alter default privileges for role postgres in schema private
  revoke execute on functions from public, anon, authenticated;
