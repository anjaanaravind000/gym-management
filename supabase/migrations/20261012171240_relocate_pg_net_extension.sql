create schema if not exists extensions;

-- Preserve diagnostic responses before recreating the extension.
create table private.pg_net_http_response_archive_20261012 as
select * from net._http_response;

revoke all on table private.pg_net_http_response_archive_20261012
from public, anon, authenticated;

-- The request queue was empty when this migration ran. Recreate pg_net in
-- the recommended schema while keeping the existing net.* API available.
drop extension pg_net;
create extension pg_net with schema extensions;
