-- The public bootstrap RPC is SECURITY INVOKER and calls a function in the private schema.
-- Allow the custom anon/authenticated client to resolve that schema without exposing tables.
grant usage on schema private to anon, authenticated;
