create schema if not exists extensions;

-- Preserve diagnostic responses when pg_net is already installed. A clean
-- environment may not have the extension yet, so provide the same empty
-- archive shape when there are no existing responses to copy.
do $migration$
begin
  if to_regclass('private.pg_net_http_response_archive_20261012') is null then
    if to_regclass('net._http_response') is not null then
      execute 'create table private.pg_net_http_response_archive_20261012 as select * from net._http_response';
    else
      create table private.pg_net_http_response_archive_20261012 (
        id bigint,
        status_code integer,
        content_type text,
        headers jsonb,
        content text,
        timed_out boolean,
        error_msg text,
        created timestamptz
      );
    end if;
  end if;
end
$migration$;

revoke all on table private.pg_net_http_response_archive_20261012
from public, anon, authenticated;

-- The request queue was empty when this migration ran. Recreate pg_net in
-- the recommended schema while keeping the existing net.* API available.
drop extension if exists pg_net;
create extension pg_net with schema extensions;
