#!/usr/bin/env bash
# Recria o banco local do zero, aplica as migrações e roda os testes de regras.
# Requer um Postgres do Supabase local (supabase start, ou o container supabase/postgres).
set -euo pipefail
cd "$(dirname "$0")/.."
DB="${DATABASE_URL:-postgresql://postgres:postgres@localhost:54329/postgres}"
psql "$DB" -q -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
set client_min_messages = warning;
drop schema if exists public cascade;
create schema public;
grant usage on schema public to anon, authenticated, service_role;
grant all on schema public to postgres, service_role;
delete from auth.users;
select cron.unschedule(jobid) from cron.job where jobname in ('iservice-expirar-pedidos', 'iservice-excluir-contas');
SQL
for f in supabase/migrations/*.sql; do
  psql "$DB" -q -v ON_ERROR_STOP=1 -f "$f" 2>&1 | grep -v 'already exists, skipping' || true
done
psql "$DB" -q -t -v ON_ERROR_STOP=1 -f supabase/tests/regras_de_negocio.sql 2>&1 | grep -E 'ok -|FALHOU|ERROR|ERRO|CONTEXT' | sed 's/^psql:[^ ]* //; s/^NOTICE:  //'
