-- Cargo "Captação" na equipe (Plano Diretor, tópico 8, 20/11/2026).
-- O captador vê só o Início e a página Captação (funil, metas por profissão e quem
-- indicou). Não vê dados pessoais, não atende e-mails e não manda comunicados.
-- Antes, o captador precisaria do cargo Marketing, que também manda comunicados.

-- ---------------------------------------------------------------------------
-- 1. O cargo
-- ---------------------------------------------------------------------------
alter table public.equipe drop constraint if exists equipe_papel_check;
alter table public.equipe add constraint equipe_papel_check
  check (papel in ('dono', 'gerente', 'responsavel', 'suporte', 'marketing', 'captacao'));

create or replace function public.cargo_nivel(p_cargo text)
returns integer
language sql immutable
as $$ select case p_cargo when 'dono' then 4 when 'gerente' then 3 when 'responsavel' then 2
  when 'suporte' then 1 when 'marketing' then 1 when 'captacao' then 1 else 0 end $$;

create or replace function public.cargo_nome(p_cargo text)
returns text
language sql immutable
as $$ select case p_cargo when 'dono' then 'Dono' when 'gerente' then 'Gerente geral' when 'responsavel' then 'Responsável de setor'
  when 'suporte' then 'Suporte' when 'marketing' then 'Marketing' when 'captacao' then 'Captação' else p_cargo end $$;

-- Permissão nova "captacao" (a página Captação). Antes ela pedia "crescimento".
create or replace function public.cargo_permissoes(p_cargo text)
returns text[]
language sql immutable
as $$
  select case p_cargo
    when 'dono' then array[
      'inicio', 'emails', 'emails_todos', 'cadastros', 'cadastros_decidir', 'dados_pessoais', 'pedidos', 'emergencias',
      'garantia', 'garantia_decidir', 'avaliacoes', 'avaliacoes_moderar', 'denuncias', 'pessoas', 'pessoas_suspender',
      'crescimento', 'comunicados', 'catalogo', 'precos', 'configuracoes', 'equipe', 'equipe_gerir', 'registro', 'registro_completo',
      'relatorios', 'captacao']
    when 'gerente' then array[
      'inicio', 'emails', 'emails_todos', 'cadastros', 'cadastros_decidir', 'dados_pessoais', 'pedidos', 'emergencias',
      'garantia', 'garantia_decidir', 'avaliacoes', 'avaliacoes_moderar', 'denuncias', 'pessoas', 'pessoas_suspender',
      'crescimento', 'comunicados', 'catalogo', 'precos', 'equipe', 'equipe_gerir', 'registro', 'registro_completo',
      'relatorios', 'captacao']
    when 'responsavel' then array[
      'inicio', 'emails', 'emails_todos', 'cadastros', 'cadastros_decidir', 'dados_pessoais', 'pedidos', 'emergencias',
      'garantia', 'garantia_decidir', 'avaliacoes', 'avaliacoes_moderar', 'denuncias', 'pessoas', 'pessoas_suspender',
      'equipe', 'registro', 'relatorios']
    when 'suporte' then array[
      'inicio', 'emails', 'cadastros', 'pedidos', 'emergencias', 'garantia', 'pessoas']
    when 'marketing' then array[
      'inicio', 'avaliacoes', 'crescimento', 'comunicados', 'relatorios', 'captacao']
    when 'captacao' then array[
      'inicio', 'captacao']
    else '{}'::text[] end
$$;
revoke all on function public.cargo_permissoes(text) from public, anon;
grant execute on function public.cargo_permissoes(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Ajustes nas funções que já existem (troca de trechos, como nas migrações anteriores)
-- ---------------------------------------------------------------------------
do $$
declare
  r record;
  v_def text;
begin
  for r in select * from (values
    -- Convidar e mudar de cargo: Captação entra na lista e, como o Marketing, não recebe e-mails do suporte.
    ('admin_convidar_equipe(text,text,text)',
     'if v_cargo not in (''gerente'', ''responsavel'', ''suporte'', ''marketing'') then',
     'if v_cargo not in (''gerente'', ''responsavel'', ''suporte'', ''marketing'', ''captacao'') then'),
    ('admin_convidar_equipe(text,text,text)',
     'v_cargo <> ''marketing'');',
     'v_cargo not in (''marketing'', ''captacao''));'),
    ('admin_mudar_cargo(text,text)',
     'if v_cargo not in (''gerente'', ''responsavel'', ''suporte'', ''marketing'') then',
     'if v_cargo not in (''gerente'', ''responsavel'', ''suporte'', ''marketing'', ''captacao'') then'),
    ('admin_mudar_cargo(text,text)',
     'if v_cargo = ''marketing'' then',
     'if v_cargo in (''marketing'', ''captacao'') then'),
    -- Caixa de e-mails: Captação não atende, como o Marketing.
    ('admin_suporte_equipe()',
     'where e.papel <> ''marketing''',
     'where e.papel not in (''marketing'', ''captacao'')'),
    ('admin_suporte_transferir(bigint,text)',
     'e.email = v_email and e.papel = ''marketing'') then
    perform public.erro(''sem_permissao'', ''O cargo Marketing não atende e-mails do suporte.'');',
     'e.email = v_email and e.papel in (''marketing'', ''captacao'')) then
    perform public.erro(''sem_permissao'', ''Os cargos Marketing e Captação não atendem e-mails do suporte.'');'),
    ('admin_suporte_rodizio(text,boolean)',
     'e.email = v_email and e.papel = ''marketing'') then
    perform public.erro(''sem_permissao'', ''O cargo Marketing não recebe e-mails do suporte.'');',
     'e.email = v_email and e.papel in (''marketing'', ''captacao'')) then
    perform public.erro(''sem_permissao'', ''Os cargos Marketing e Captação não recebem e-mails do suporte.'');'),
    -- Página Captação: permissão própria.
    ('admin_captacao()',
     'perform public.exigir_permissao(''crescimento'');',
     'perform public.exigir_permissao(''captacao'');'),
    -- Horário, plantão e prazos: só quem atende emergências (antes, qualquer pessoa da equipe via a lista).
    ('admin_atendimento()',
     'perform public.exigir_admin();',
     'perform public.exigir_permissao(''emergencias'');')
  ) as t(funcao, antes, depois)
  loop
    -- Colado pelo SQL Editor no Windows, o texto chega com \r\n: normaliza tudo para \n.
    v_def := replace(pg_get_functiondef(('public.' || r.funcao)::regprocedure), E'\r\n', E'\n');
    r.antes := replace(r.antes, E'\r\n', E'\n');
    r.depois := replace(r.depois, E'\r\n', E'\n');
    if position(r.antes in v_def) = 0 then
      if position(r.depois in v_def) > 0 then
        continue; -- já aplicado
      end if;
      raise exception 'A função % está diferente do esperado.', r.funcao;
    end if;
    execute replace(v_def, r.antes, r.depois);
  end loop;
end;
$$;
