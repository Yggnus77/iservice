-- Ajustes de segurança apontados pelo verificador do Supabase (21/11/2026).
-- 1) Funções auxiliares sem search_path fixo passam a usar só "public".
-- 2) Visitantes sem login (anon) perdem a execução de funções que não são deles:
--    admin_captacao (já exigia permissão da equipe) e funções de gatilho.
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as f
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('inicio_do_trabalho','permissao_do_atendimento','permissoes_catalogo','permissoes_todas',
        'permissoes_validas','cargo_permissoes_padrao','suporte_protocolo','cargo_nome','cargo_do_atendimento',
        'cargo_nivel','site_limpar','site_motivo_reclamacao','mascarar_cpf','limpar_prazo_suspensao',
        'validade_padrao_documento','nome_pendencia','nota_permissao','marcar_envio_analise','gravidade_sugerida')
      and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')
  loop
    execute format('alter function %s set search_path = public', r.f);
  end loop;

  for r in
    select p.oid::regprocedure as f
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and (p.proname = 'admin_captacao' or (p.prosecdef and p.prorettype = 'trigger'::regtype))
  loop
    execute format('revoke execute on function %s from public, anon', r.f);
  end loop;
end $$;
