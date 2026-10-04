-- Allow the custom-login (anon) client to invoke the first-time gym setup RPC.
grant execute on function public.bootstrap_gym(text, text, text, text) to anon;
