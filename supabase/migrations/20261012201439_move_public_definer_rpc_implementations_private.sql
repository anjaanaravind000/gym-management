-- Keep the app's existing public RPC names stable while moving the
-- privileged implementations into the non-exposed private schema.
--
-- Public entry points become SECURITY INVOKER SQL wrappers. Each wrapper
-- forwards to its private SECURITY DEFINER implementation, whose function
-- body continues to validate the custom x-gym-session and permission checks.
-- Only the anonymous role used by the app's custom-session client can execute
-- the browser wrappers. The private implementation is not exposed by the
-- default Supabase Data API schema configuration.

do $migration$
declare
  r record;
  v_call_args text;
  v_body text;
  v_volatility text;
begin
  if not has_schema_privilege('anon','private','USAGE') then
    raise exception 'anon must have USAGE on private for internal wrapper invocation';
  end if;

  for r in
    select p.oid, p.proname, p.proargtypes,
           pg_get_function_identity_arguments(p.oid) as identity_args,
           pg_get_function_arguments(p.oid) as full_args,
           pg_get_function_result(p.oid) as result_type,
           p.pronargs, p.provolatile, p.proretset
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.prokind='f'
      and p.prosecdef
      and has_function_privilege('anon',p.oid,'EXECUTE')
    order by p.proname
  loop
    if exists (
      select 1 from pg_proc p2
      join pg_namespace n2 on n2.oid=p2.pronamespace
      where n2.nspname='private'
        and p2.proname=r.proname
        and p2.proargtypes=r.proargtypes
    ) then
      raise exception 'Private function collision for % (%)', r.proname, r.identity_args;
    end if;

    select coalesce(string_agg('$'||i::text, ', ' order by i), '')
      into v_call_args
      from generate_series(1,r.pronargs) as g(i);

    v_volatility := case r.provolatile
      when 'i' then 'IMMUTABLE'
      when 's' then 'STABLE'
      else 'VOLATILE'
    end;

    execute format(
      'alter function public.%I(%s) set schema private',
      r.proname, r.identity_args
    );

    if r.proretset or r.result_type like 'TABLE(%%' then
      v_body := format('SELECT * FROM private.%I(%s)',r.proname,v_call_args);
    else
      v_body := format('SELECT private.%I(%s)',r.proname,v_call_args);
    end if;

    execute format(
      'create function public.%I(%s) returns %s language sql %s security invoker set search_path to %L as %L',
      r.proname, r.full_args, r.result_type, v_volatility, '', v_body
    );

    execute format(
      'revoke all on function public.%I(%s) from public, anon, authenticated',
      r.proname, r.identity_args
    );
    execute format(
      'grant execute on function public.%I(%s) to anon',
      r.proname, r.identity_args
    );

    execute format(
      'revoke all on function private.%I(%s) from public, anon, authenticated',
      r.proname, r.identity_args
    );
    execute format(
      'grant execute on function private.%I(%s) to anon',
      r.proname, r.identity_args
    );
  end loop;
end
$migration$;

notify pgrst, 'reload schema';
