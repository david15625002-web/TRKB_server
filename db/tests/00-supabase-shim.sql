-- Minimal Supabase compatibility shim so the schema can be validated locally.
-- Supplies only what db/schema.sql and db/policies.sql reference.
create schema if not exists auth;

create table if not exists auth.users (
  id    uuid primary key default gen_random_uuid(),
  email text
);

-- Supabase sets request.jwt.claim.sub per request; emulate with a GUC.
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

-- Realtime publication that schema.sql appends tables to.
do $$ begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end $$;
