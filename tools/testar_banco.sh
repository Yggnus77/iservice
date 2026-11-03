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
select cron.unschedule(jobid) from cron.job where jobname in ('iservice-expirar-pedidos', 'iservice-excluir-contas', 'iservice-limpar-arquivos');
SQL
# O auth do container local é antigo e não tem as colunas de telefone do Supabase atual.
docker exec ispg psql -q -U supabase_admin -d postgres -c \
  'alter table auth.users add column if not exists phone text, add column if not exists phone_confirmed_at timestamptz, add column if not exists banned_until timestamptz' >/dev/null 2>&1 || true
for f in supabase/migrations/*.sql; do
  psql "$DB" -q -v ON_ERROR_STOP=1 -f "$f" 2>&1 | grep -v 'already exists, skipping' || true
done
for t in supabase/tests/*.sql; do
  psql "$DB" -q -t -v ON_ERROR_STOP=1 -f "$t" 2>&1 | grep -E 'ok -|FALHOU|ERROR|ERRO|CONTEXT' | sed 's/^psql:[^ ]* //; s/^NOTICE:  //'
done
