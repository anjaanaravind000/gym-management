-- The public bootstrap wrapper runs as the caller and therefore needs execute
-- permission on the private SECURITY DEFINER implementation.
grant execute on function private.bootstrap_gym(text, text, text, text) to anon, authenticated;
