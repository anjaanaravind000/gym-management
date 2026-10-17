alter table private.pg_net_http_response_archive_20261012
  alter column id set not null;

alter table private.pg_net_http_response_archive_20261012
  add constraint pg_net_http_response_archive_20261012_pkey primary key (id);
