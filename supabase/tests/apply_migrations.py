import pgserver, psycopg2, sys, glob, json, os, warnings
warnings.filterwarnings("ignore")
srv = pgserver.get_server('/tmp/pgt/data', cleanup_mode=None)
uri = srv.get_uri()
conn = psycopg2.connect(uri); conn.autocommit = True
cur = conn.cursor()
cur.execute("select version()"); print(cur.fetchone()[0][:40])
cur.execute("drop schema if exists public cascade; drop schema if exists app cascade; drop schema if exists auth cascade; drop schema if exists extensions cascade; create schema public;")
cur.execute("""
do $$ begin
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
end $$;
create schema auth;
create table auth.users(id uuid primary key default gen_random_uuid(), email text, encrypted_password text);
-- Supabase installs pgcrypto in the extensions schema. The scratch database has no pgcrypto, so crypt() is a stand-in
-- that exercises the same control flow (real bcrypt checking only runs on Supabase).
create schema if not exists extensions;
create function extensions.crypt(pw text, salt text) returns text language sql immutable as $f$ select 'stub:' || md5(pw) $f$;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema public to authenticated, anon; grant usage on schema auth to authenticated;
alter default privileges in schema public grant all on tables to authenticated;
""")
# Storage migrations need Supabase's storage schema and are skipped on the scratch database.
SKIP = ('0005_', '0013_')
here = os.path.dirname(os.path.abspath(__file__))
for f in sorted(glob.glob(os.path.join(here, '..', 'migrations', '*.sql'))):
    if os.path.basename(f).startswith(SKIP):
        continue
    try:
        cur.execute(open(f).read()); print("OK ", os.path.basename(f))
    except Exception as e:
        print("ERR", os.path.basename(f), str(e)[:600]); sys.exit(1)
cur.execute("grant all on all tables in schema public to authenticated")
print("migrations applied")
