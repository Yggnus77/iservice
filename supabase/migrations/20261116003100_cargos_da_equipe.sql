-- Cargos da equipe do painel (16/11/2026).
--
-- Cinco cargos fixos, aprovados pelo dono:
--   dono         tudo; só ele mexe em Configurações, nomeia/remove gerentes e passa a posição de dono.
--   gerente      Operação, Crescimento, Profissões, Preços e Comunicados; gere responsáveis, suporte e marketing.
--   responsavel  Responsável de setor (Atendimento): toda a Operação, vê só o próprio time na Equipe.
--   suporte      Atende os próprios e-mails e as emergências, consulta pedidos e pessoas (CPF mascarado).
--   marketing    Buscas e mapa, Site e downloads, Avaliações e Comunicados, sem dados pessoais.
--
-- As permissões valem no banco: cada função admin_* confere a permissão do cargo, não só o painel.
-- Quem já estava como "suporte" continua como Suporte.

-- ---------------------------------------------------------------------------
-- 1. Cargo na tabela da equipe
-- ---------------------------------------------------------------------------
alter table public.equipe drop constraint if exists equipe_papel_check;
alter table public.equipe add constraint equipe_papel_check
  check (papel in ('dono', 'gerente', 'responsavel', 'suporte', 'marketing'));

-- Um dono só.
create unique index if not exists equipe_um_dono on public.equipe ((true)) where papel = 'dono';

-- ---------------------------------------------------------------------------
-- 2. O que cada cargo pode
-- ---------------------------------------------------------------------------
create or replace function public.cargo_nivel(p_cargo text)
returns integer
language sql immutable
as $$ select case p_cargo when 'dono' then 4 when 'gerente' then 3 when 'responsavel' then 2 when 'suporte' then 1 when 'marketing' then 1 else 0 end $$;

create or replace function public.cargo_nome(p_cargo text)
returns text
language sql immutable
as $$ select case p_cargo when 'dono' then 'Dono' when 'gerente' then 'Gerente geral' when 'responsavel' then 'Responsável de setor'
  when 'suporte' then 'Suporte' when 'marketing' then 'Marketing' else p_cargo end $$;

-- A tabela de permissões. Mudar aqui muda o banco e o painel juntos (o painel lê admin_meu_acesso).
create or replace function public.cargo_permissoes(p_cargo text)
returns text[]
language sql immutable
as $$
  select case p_cargo
    when 'dono' then array[
      'inicio', 'emails', 'emails_todos', 'cadastros', 'cadastros_decidir', 'dados_pessoais', 'pedidos', 'emergencias',
      'garantia', 'garantia_decidir', 'avaliacoes', 'avaliacoes_moderar', 'denuncias', 'pessoas', 'pessoas_suspender',
      'crescimento', 'comunicados', 'catalogo', 'precos', 'configuracoes', 'equipe', 'equipe_gerir', 'registro', 'registro_completo']
    when 'gerente' then array[
      'inicio', 'emails', 'emails_todos', 'cadastros', 'cadastros_decidir', 'dados_pessoais', 'pedidos', 'emergencias',
      'garantia', 'garantia_decidir', 'avaliacoes', 'avaliacoes_moderar', 'denuncias', 'pessoas', 'pessoas_suspender',
      'crescimento', 'comunicados', 'catalogo', 'precos', 'equipe', 'equipe_gerir', 'registro', 'registro_completo']
    when 'responsavel' then array[
      'inicio', 'emails', 'emails_todos', 'cadastros', 'cadastros_decidir', 'dados_pessoais', 'pedidos', 'emergencias',
      'garantia', 'garantia_decidir', 'avaliacoes', 'avaliacoes_moderar', 'denuncias', 'pessoas', 'pessoas_suspender',
      'equipe', 'registro']
    when 'suporte' then array[
      'inicio', 'emails', 'cadastros', 'pedidos', 'emergencias', 'garantia', 'pessoas']
    when 'marketing' then array[
      'inicio', 'avaliacoes', 'crescimento', 'comunicados']
    else '{}'::text[] end
$$;

-- Cargo de quem está logado. Conta com e_admin fora da lista da equipe fica com o menor acesso.
create or replace function public.meu_cargo()
returns text
language sql stable security definer
set search_path = public
as $$
  select case when not public.e_admin() then null
    else coalesce((select e.papel from public.equipe e where e.usuario_id = auth.uid() limit 1), 'suporte') end
$$;

create or replace function public.pode(p_permissao text)
returns boolean
language sql stable security definer
set search_path = public
as $$ select coalesce(p_permissao = any (public.cargo_permissoes(public.meu_cargo())), false) $$;

create or replace function public.exigir_permissao(p_permissao text)
returns void
language plpgsql stable
set search_path = public
as $$
begin
  perform public.exigir_admin();
  if not public.pode(p_permissao) then
    perform public.erro('sem_permissao', 'Seu cargo não tem acesso a esta parte do painel. Fale com o seu gerente.');
  end if;
end;
$$;

-- Quem pode convidar, remover ou mudar o cargo de alguém com este cargo.
create or replace function public.pode_gerir_cargo(p_cargo text)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select public.pode('equipe_gerir') and p_cargo <> 'dono'
    and public.cargo_nivel(public.meu_cargo()) > public.cargo_nivel(p_cargo)
$$;

-- Time do Responsável de setor: o Atendimento (suporte e responsáveis).
create or replace function public.cargo_do_atendimento(p_cargo text)
returns boolean
language sql immutable
as $$ select p_cargo in ('suporte', 'responsavel') $$;

-- Mostra a pessoa da equipe na aba Equipe para quem está logado.
create or replace function public.ve_membro(p_cargo text)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select public.pode('equipe')
    and (public.meu_cargo() in ('dono', 'gerente') or public.cargo_do_atendimento(p_cargo))
$$;

-- O painel pergunta isto ao entrar, para montar o menu e os botões.
create or replace function public.admin_meu_acesso()
returns jsonb
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_cargo text;
begin
  perform public.exigir_admin();
  v_cargo := public.meu_cargo();
  return jsonb_build_object('cargo', v_cargo, 'cargo_nome', public.cargo_nome(v_cargo),
    'permissoes', to_jsonb(public.cargo_permissoes(v_cargo)));
end;
$$;

revoke all on function public.cargo_nivel(text) from public, anon;
revoke all on function public.cargo_nome(text) from public, anon;
revoke all on function public.cargo_permissoes(text) from public, anon;
revoke all on function public.cargo_do_atendimento(text) from public, anon;
revoke all on function public.meu_cargo() from public, anon;
revoke all on function public.pode(text) from public, anon;
revoke all on function public.exigir_permissao(text) from public, anon;
revoke all on function public.pode_gerir_cargo(text) from public, anon;
revoke all on function public.ve_membro(text) from public, anon;
revoke all on function public.admin_meu_acesso() from public, anon;
grant execute on function public.cargo_nivel(text), public.cargo_nome(text), public.cargo_permissoes(text),
  public.cargo_do_atendimento(text), public.meu_cargo(), public.pode(text), public.exigir_permissao(text),
  public.pode_gerir_cargo(text), public.ve_membro(text), public.admin_meu_acesso() to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Cada função do painel passa a conferir a permissão do cargo
-- ---------------------------------------------------------------------------
-- Troca a conferência "é da equipe" pela permissão certa, na definição que está no banco agora.
do $$
declare
  r record;
  v_def text;
  v_novo text;
begin
  for r in select * from (values
    ('admin_resumo', 'inicio'),
    ('admin_cadastros', 'cadastros'),
    ('admin_decidir_cadastro', 'cadastros_decidir'),
    ('admin_revisar_documento', 'cadastros_decidir'),
    ('admin_revisar_certificacao', 'cadastros_decidir'),
    ('admin_pedidos', 'pedidos'),
    ('admin_pedido', 'pedidos'),
    ('admin_emergencias', 'emergencias'),
    ('admin_atender_emergencia', 'emergencias'),
    ('admin_reclamacoes', 'garantia'),
    ('admin_reclamacao_historico', 'garantia'),
    ('admin_avaliacoes_recentes', 'avaliacoes'),
    ('admin_ranking_avaliacoes', 'avaliacoes'),
    ('admin_resumo_avaliacoes', 'avaliacoes'),
    ('admin_ocultar_avaliacao', 'avaliacoes_moderar'),
    ('admin_denuncias', 'denuncias'),
    ('admin_resolver_denuncia', 'denuncias'),
    ('admin_avaliacoes_suspeitas', 'denuncias'),
    ('admin_usuarios', 'pessoas'),
    ('admin_usuario', 'pessoas'),
    ('admin_buscas_por_regiao', 'crescimento'),
    ('admin_mapa_buscas', 'crescimento'),
    ('admin_site', 'crescimento'),
    ('admin_comunicados', 'comunicados'),
    ('admin_contar_publico', 'comunicados'),
    ('admin_enviar_comunicado', 'comunicados'),
    ('admin_especialidades_sugeridas', 'catalogo'),
    ('admin_tabela_precos', 'precos'),
    ('admin_ajustar_preco', 'precos'),
    ('admin_suporte_contagem', 'emails'),
    ('admin_suporte_equipe', 'emails')
  ) as t(funcao, permissao)
  loop
    if to_regproc('public.' || r.funcao) is null then
      raise exception 'Função % não encontrada. Aplique as migrações anteriores antes desta.', r.funcao;
    end if;
    v_def := replace(pg_get_functiondef(to_regproc('public.' || r.funcao)), E'\r\n', E'\n');
    v_novo := replace(v_def, 'perform public.exigir_admin();', format('perform public.exigir_permissao(%L);', r.permissao));
    if v_novo = v_def and position('exigir_permissao' in v_def) = 0 then
      raise exception 'A função % não tem a conferência esperada.', r.funcao;
    end if;
    execute v_novo;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Dados pessoais mascarados para quem não tem "dados_pessoais"
-- ---------------------------------------------------------------------------
create or replace function public.mascarar_cpf(p_cpf text)
returns text
language sql immutable
as $$ select case when p_cpf is null or length(p_cpf) <> 11 then null
  else '***.' || substr(p_cpf, 4, 3) || '.' || substr(p_cpf, 7, 3) || '-**' end $$;

-- A ficha completa vira uma função interna; a pública mascara conforme o cargo.
do $$
begin
  if to_regproc('public.admin_usuario_completo') is null then
    alter function public.admin_usuario(uuid) rename to admin_usuario_completo;
  end if;
end;
$$;
revoke all on function public.admin_usuario_completo(uuid) from public, anon, authenticated;

create or replace function public.admin_usuario(p_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public
as $$
declare
  v jsonb;
  v_docs jsonb;
  v_certs jsonb;
begin
  perform public.exigir_permissao('pessoas');
  v := public.admin_usuario_completo(p_id);
  if v is null or public.pode('dados_pessoais') then return v; end if;

  v := jsonb_set(v, '{perfil,cpf}', to_jsonb(public.mascarar_cpf(v #>> '{perfil,cpf}')));
  v := jsonb_set(v, '{perfil,nascimento}', 'null');
  v := v || jsonb_build_object('dados_mascarados', true);
  if jsonb_typeof(v -> 'profissional') = 'object' then
    select coalesce(jsonb_agg(d || jsonb_build_object('arquivo_path', null)), '[]') into v_docs
      from jsonb_array_elements(v #> '{profissional,documentos}') d;
    select coalesce(jsonb_agg(c || jsonb_build_object('arquivo_path', null)), '[]') into v_certs
      from jsonb_array_elements(v #> '{profissional,certificacoes}') c;
    v := jsonb_set(v, '{profissional,documentos}', v_docs);
    v := jsonb_set(v, '{profissional,certificacoes}', v_certs);
  end if;
  return v;
end;
$$;
revoke all on function public.admin_usuario(uuid) from public, anon;
grant execute on function public.admin_usuario(uuid) to authenticated;

-- Documentos de identidade: só o próprio profissional e quem tem "dados_pessoais".
drop policy if exists "documentos: dono e admin leem" on public.documentos;
create policy "documentos: dono e admin leem" on public.documentos for select to authenticated
  using (profissional_id = auth.uid() or public.pode('dados_pessoais'));

do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'storage' and table_name = 'objects') then
    execute 'drop policy if exists "documentos: dono e admin leem" on storage.objects';
    execute $p$create policy "documentos: dono e admin leem" on storage.objects for select to authenticated
      using (bucket_id = 'documentos' and ((storage.foldername(name))[1] = auth.uid()::text or public.pode('dados_pessoais')))$p$;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Escritas diretas do painel: Profissões e regiões, Configurações, registro
-- ---------------------------------------------------------------------------
drop policy if exists "profissoes: admin escreve" on public.profissoes;
create policy "profissoes: admin escreve" on public.profissoes for insert to authenticated with check (public.pode('catalogo'));
drop policy if exists "profissoes: admin altera" on public.profissoes;
create policy "profissoes: admin altera" on public.profissoes for update to authenticated using (public.pode('catalogo')) with check (public.pode('catalogo'));
drop policy if exists "especialidades: admin escreve" on public.especialidades;
create policy "especialidades: admin escreve" on public.especialidades for insert to authenticated with check (public.pode('catalogo'));
drop policy if exists "especialidades: admin altera" on public.especialidades;
create policy "especialidades: admin altera" on public.especialidades for update to authenticated using (public.pode('catalogo')) with check (public.pode('catalogo'));
drop policy if exists "regioes: admin escreve" on public.regioes;
create policy "regioes: admin escreve" on public.regioes for insert to authenticated with check (public.pode('catalogo'));
drop policy if exists "regioes: admin altera" on public.regioes;
create policy "regioes: admin altera" on public.regioes for update to authenticated using (public.pode('catalogo')) with check (public.pode('catalogo'));
drop policy if exists "cert sugeridas: admin escreve" on public.certificacoes_sugeridas;
create policy "cert sugeridas: admin escreve" on public.certificacoes_sugeridas for all to authenticated using (public.pode('catalogo')) with check (public.pode('catalogo'));
drop policy if exists "config: admin escreve" on public.app_config;
create policy "config: admin escreve" on public.app_config for insert to authenticated with check (public.pode('configuracoes'));
drop policy if exists "config: admin altera" on public.app_config;
create policy "config: admin altera" on public.app_config for update to authenticated using (public.pode('configuracoes')) with check (public.pode('configuracoes'));
drop policy if exists "admin_acoes: admin lê" on public.admin_acoes;
create policy "admin_acoes: admin lê" on public.admin_acoes for select to authenticated using (public.pode('registro_completo'));
drop policy if exists "emails_enviados: admin lê" on public.emails_enviados;
create policy "emails_enviados: admin lê" on public.emails_enviados for select to authenticated using (public.pode('registro_completo'));

-- ---------------------------------------------------------------------------
-- 6. Garantia: o Suporte registra e media; só quem decide fecha
-- ---------------------------------------------------------------------------
create or replace function public.admin_mediar_reclamacao(p_reclamacao bigint, p_status status_reclamacao default null,
  p_texto text default null, p_avisar_partes boolean default false)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_rec public.reclamacoes;
  v_ped public.pedidos;
  v_titulo text;
begin
  perform public.exigir_permissao('garantia');
  if p_status in ('resolvida', 'encerrada') and not public.pode('garantia_decidir') then
    perform public.erro('sem_permissao', 'Só o Responsável de setor ou o gerente fecha uma reclamação da Garantia. Registre a sua nota e passe para eles.');
  end if;
  select * into v_rec from public.reclamacoes where id = p_reclamacao;
  if v_rec.id is null then perform public.erro('nao_encontrado', 'Reclamação não encontrada.'); end if;
  if v_rec.status in ('resolvida', 'encerrada') and p_status is distinct from v_rec.status and not public.pode('garantia_decidir') then
    perform public.erro('sem_permissao', 'Só o Responsável de setor ou o gerente reabre uma reclamação fechada.');
  end if;
  if p_status in ('resolvida', 'encerrada') and coalesce(trim(p_texto), '') = '' and v_rec.resolucao is null then
    perform public.erro('motivo_obrigatorio', 'Escreva a resolução antes de fechar a reclamação.');
  end if;
  select * into v_ped from public.pedidos where id = v_rec.pedido_id;
  update public.reclamacoes set status = coalesce(p_status, status),
    resolucao = case when p_status in ('resolvida', 'encerrada') and coalesce(trim(p_texto), '') <> '' then trim(p_texto) else resolucao end
  where id = p_reclamacao;
  insert into public.reclamacao_historico (reclamacao_id, autor_id, status, texto, interno)
  values (p_reclamacao, auth.uid(), p_status, coalesce(trim(p_texto), ''), not p_avisar_partes);
  if p_avisar_partes then
    v_titulo := case coalesce(p_status, v_rec.status)
      when 'em_mediacao' then 'Garantia iService: estamos mediando'
      when 'resolvida' then 'Garantia iService: reclamação resolvida'
      when 'encerrada' then 'Garantia iService: reclamação encerrada'
      else 'Garantia iService: atualização' end;
    perform public.notificar(v_ped.cliente_id, 'garantia', v_titulo, coalesce(trim(p_texto), ''),
      jsonb_build_object('pedido_id', v_ped.id, 'reclamacao_id', p_reclamacao));
    perform public.notificar(v_ped.profissional_id, 'garantia', v_titulo, coalesce(trim(p_texto), ''),
      jsonb_build_object('pedido_id', v_ped.id, 'reclamacao_id', p_reclamacao));
  end if;
  perform public.registrar_acao('mediar_reclamacao', v_rec.autor_id::text,
    jsonb_build_object('reclamacao_id', p_reclamacao, 'status', p_status, 'avisou', p_avisar_partes));
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Suspender: ninguém suspende alguém da equipe com cargo igual ou acima do seu
-- ---------------------------------------------------------------------------
do $$
declare
  v_def text := replace(pg_get_functiondef('public.admin_suspender(uuid, boolean, text)'::regprocedure), E'\r\n', E'\n');
  v_novo text;
begin
  if position('exigir_permissao' in v_def) = 0 then
    v_novo := replace(v_def, 'perform public.exigir_admin();',
      'perform public.exigir_permissao(''pessoas_suspender'');
  if exists (select 1 from public.equipe e where e.usuario_id = p_usuario and not public.pode_gerir_cargo(e.papel)) then
    perform public.erro(''sem_permissao'', ''Esta pessoa é da equipe. Só quem tem cargo acima dela pode suspender a conta.'');
  end if;');
    if v_novo = v_def then raise exception 'admin_suspender sem a conferência esperada.'; end if;
    execute v_novo;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Equipe
-- ---------------------------------------------------------------------------
drop function if exists public.admin_equipe();
create function public.admin_equipe()
returns table (
  email text, nome text, papel text, cargo_nome text, usuario_id uuid, foto_url text, situacao text,
  convidado_por text, convidado_em timestamptz, entrou_em timestamptz, ultimo_acesso timestamptz, voce boolean,
  pode_gerir boolean, pode_foto boolean, recebe_emails boolean
)
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.exigir_permissao('equipe');
  return query
  select e.email, coalesce(nullif(btrim(p.nome), ''), e.nome), e.papel, public.cargo_nome(e.papel), e.usuario_id, p.foto_url,
    case when p.e_admin then 'ativo' else 'convite_pendente' end,
    (select c.nome from public.perfis c where c.id = e.convidado_por),
    e.convidado_em, e.entrou_em, u.last_sign_in_at, e.usuario_id = auth.uid(),
    e.usuario_id is distinct from auth.uid() and public.pode_gerir_cargo(e.papel),
    e.usuario_id is not null and public.pode_trocar_foto_equipe(e.usuario_id::text),
    e.recebe_emails
  from public.equipe e
  left join public.perfis p on p.id = e.usuario_id
  left join auth.users u on u.id = e.usuario_id
  where e.usuario_id = auth.uid() or public.ve_membro(e.papel)
  order by public.cargo_nivel(e.papel) desc, (p.e_admin is true) desc, e.convidado_em;
end;
$$;

drop function if exists public.admin_convidar_equipe(text, text);
create or replace function public.admin_convidar_equipe(p_email text, p_nome text, p_cargo text default 'suporte')
returns text
language plpgsql security definer
set search_path = public
as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_nome text := btrim(coalesce(p_nome, ''));
  v_cargo text := coalesce(nullif(btrim(p_cargo), ''), 'suporte');
  v_usuario uuid;
begin
  perform public.exigir_permissao('equipe_gerir');
  if v_cargo not in ('gerente', 'responsavel', 'suporte', 'marketing') then
    perform public.erro('cargo_invalido', 'Escolha um cargo da lista.');
  end if;
  if not public.pode_gerir_cargo(v_cargo) then
    perform public.erro('sem_permissao', 'Só o dono convida alguém como ' || public.cargo_nome(v_cargo) || '.');
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    perform public.erro('email_invalido', 'Confira o e-mail digitado.');
  end if;
  if length(v_nome) < 2 then
    perform public.erro('nome_invalido', 'Informe o nome da pessoa.');
  end if;
  if exists (select 1 from public.equipe where email = v_email) then
    perform public.erro('ja_na_equipe', 'Este e-mail já está na equipe.');
  end if;

  select u.id into v_usuario from auth.users u
  where lower(u.email) = v_email and u.email_confirmed_at is not null
    and exists (select 1 from public.perfis p where p.id = u.id)
  limit 1;

  insert into public.equipe (email, nome, papel, usuario_id, convidado_por, entrou_em, recebe_emails)
  values (v_email, left(v_nome, 80), v_cargo, v_usuario, auth.uid(), case when v_usuario is not null then now() end,
    v_cargo <> 'marketing');

  if v_usuario is not null then
    update public.perfis set e_admin = true where id = v_usuario;
  end if;

  perform public.registrar_acao('convidar_equipe', coalesce(v_usuario::text, v_email),
    jsonb_build_object('nome', v_nome, 'email', v_email, 'cargo', v_cargo));
  return case when v_usuario is not null then 'ativo' else 'convite_pendente' end;
end;
$$;

create or replace function public.admin_remover_equipe(p_email text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v public.equipe;
begin
  perform public.exigir_permissao('equipe_gerir');
  select * into v from public.equipe where email = lower(btrim(coalesce(p_email, '')));
  if v.email is null then
    perform public.erro('nao_encontrado', 'Esta pessoa não está mais na equipe.');
  end if;
  if v.papel = 'dono' then
    perform public.erro('dono', 'O dono do painel não pode ser removido.');
  end if;
  if v.usuario_id = auth.uid() then
    perform public.erro('voce_mesmo', 'Você não pode remover o seu próprio acesso.');
  end if;
  if not public.pode_gerir_cargo(v.papel) then
    perform public.erro('sem_permissao', 'Só o dono remove alguém com o cargo ' || public.cargo_nome(v.papel) || '.');
  end if;

  delete from public.equipe where email = v.email;
  if v.usuario_id is not null then
    update public.perfis set e_admin = false where id = v.usuario_id;
  end if;

  perform public.registrar_acao('remover_equipe', coalesce(v.usuario_id::text, v.email),
    jsonb_build_object('nome', v.nome, 'email', v.email, 'cargo', v.papel));
end;
$$;

create or replace function public.admin_mudar_cargo(p_email text, p_cargo text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v public.equipe;
  v_cargo text := btrim(coalesce(p_cargo, ''));
begin
  perform public.exigir_permissao('equipe_gerir');
  select * into v from public.equipe where email = lower(btrim(coalesce(p_email, ''))) for update;
  if v.email is null then perform public.erro('nao_encontrado', 'Esta pessoa não está mais na equipe.'); end if;
  if v.usuario_id = auth.uid() then perform public.erro('voce_mesmo', 'Você não pode mudar o seu próprio cargo.'); end if;
  if v_cargo not in ('gerente', 'responsavel', 'suporte', 'marketing') then
    perform public.erro('cargo_invalido', 'Escolha um cargo da lista. Para passar a posição de dono, use "Passar a posição de dono".');
  end if;
  if not public.pode_gerir_cargo(v.papel) or not public.pode_gerir_cargo(v_cargo) then
    perform public.erro('sem_permissao', 'Só o dono dá ou tira o cargo de Gerente geral.');
  end if;
  if v.papel = v_cargo then return; end if;

  update public.equipe set papel = v_cargo where email = v.email;
  -- Quem sai do Atendimento deixa de receber e-mails; os que estavam com a pessoa voltam ao rodízio.
  if v_cargo = 'marketing' then
    update public.equipe set recebe_emails = false where email = v.email;
    update public.suporte_conversas set responsavel = null where responsavel = v.email and status <> 'encerrado';
    perform public.suporte_distribuir_pendentes();
  end if;
  perform public.registrar_acao('mudar_cargo', coalesce(v.usuario_id::text, v.email),
    jsonb_build_object('nome', v.nome, 'email', v.email, 'de', v.papel, 'para', v_cargo));
end;
$$;

create or replace function public.admin_transferir_dono(p_email text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v public.equipe;
begin
  perform public.exigir_admin();
  if public.meu_cargo() <> 'dono' then perform public.erro('sem_permissao', 'Só o dono passa a posição de dono.'); end if;
  select * into v from public.equipe where email = lower(btrim(coalesce(p_email, ''))) for update;
  if v.email is null then perform public.erro('nao_encontrado', 'Esta pessoa não está na equipe.'); end if;
  if v.usuario_id is null or v.usuario_id = auth.uid()
     or not exists (select 1 from public.perfis where id = v.usuario_id and e_admin) then
    perform public.erro('nao_encontrado', 'Escolha alguém da equipe que já tenha feito o primeiro acesso.');
  end if;
  update public.equipe set papel = 'gerente' where usuario_id = auth.uid();
  update public.equipe set papel = 'dono' where email = v.email;
  perform public.registrar_acao('transferir_dono', v.usuario_id::text, jsonb_build_object('nome', v.nome, 'email', v.email));
end;
$$;

revoke all on function public.admin_equipe() from public, anon;
revoke all on function public.admin_convidar_equipe(text, text, text) from public, anon;
revoke all on function public.admin_remover_equipe(text) from public, anon;
revoke all on function public.admin_mudar_cargo(text, text) from public, anon;
revoke all on function public.admin_transferir_dono(text) from public, anon;
revoke all on function public.mascarar_cpf(text) from public, anon;
grant execute on function public.admin_equipe(), public.admin_convidar_equipe(text, text, text), public.admin_remover_equipe(text),
  public.admin_mudar_cargo(text, text), public.admin_transferir_dono(text), public.mascarar_cpf(text) to authenticated;

-- Foto de colega: a própria, alguém com cargo abaixo, ou o Responsável de setor para o Suporte.
create or replace function public.pode_trocar_foto_equipe(p_pasta text)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select p_pasta is not null
    and public.e_admin()
    and exists (
      select 1 from public.equipe e
      where e.usuario_id is not null
        and e.usuario_id::text = p_pasta
        and (e.usuario_id = auth.uid()
          or public.pode_gerir_cargo(e.papel)
          or (public.meu_cargo() = 'responsavel' and e.papel = 'suporte'))
    )
$$;

do $$
declare
  v_def text := replace(pg_get_functiondef('public.admin_foto_equipe(uuid, text)'::regprocedure), E'\r\n', E'\n');
  v_novo text;
begin
  if position('pode_trocar_foto_equipe' in v_def) = 0 then
    v_novo := replace(v_def, replace($a$  if v.papel = 'dono' and p_usuario <> auth.uid() then
    perform public.erro('dono', 'Só o dono do painel troca a própria foto.');
  end if;$a$, E'\r\n', E'\n'), $b$  if not public.pode_trocar_foto_equipe(p_usuario::text) then
    perform public.erro('sem_permissao', case when v.papel = 'dono' then 'Só o dono do painel troca a própria foto.'
      else 'Seu cargo não troca a foto desta pessoa.' end);
  end if;$b$);
    if v_novo = v_def then raise exception 'admin_foto_equipe diferente do esperado.'; end if;
    execute v_novo;
  end if;
end;
$$;

-- Registro da equipe: dono e gerente veem tudo; o Responsável de setor vê o próprio time.
create or replace function public.admin_registro(p_limite integer default 100)
returns table (id bigint, admin text, acao text, alvo text, alvo_nome text, dados jsonb, criada_em timestamptz)
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.exigir_permissao('registro');
  return query
  select a.id, (select pe.nome from public.perfis pe where pe.id = a.admin_id), a.acao, a.alvo,
    (select pe.nome from public.perfis pe where pe.id::text = a.alvo), a.dados, a.criada_em
  from public.admin_acoes a
  where public.pode('registro_completo')
     or a.admin_id = auth.uid()
     or exists (select 1 from public.equipe e where e.usuario_id = a.admin_id and public.cargo_do_atendimento(e.papel))
  order by a.criada_em desc limit p_limite;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Caixa de e-mails: o Suporte vê os próprios e os sem responsável
-- ---------------------------------------------------------------------------
create or replace function public.suporte_pode_abrir(p_responsavel text)
returns boolean
language sql stable security definer
set search_path = public
as $$ select public.pode('emails_todos') or p_responsavel is null or p_responsavel = public.suporte_meu_email() $$;
revoke all on function public.suporte_pode_abrir(text) from public, anon;
grant execute on function public.suporte_pode_abrir(text) to authenticated;

create or replace function public.suporte_exigir_conversa(p_id bigint)
returns public.suporte_conversas
language plpgsql stable security definer
set search_path = public
as $$
declare
  v public.suporte_conversas;
begin
  perform public.exigir_permissao('emails');
  select * into v from public.suporte_conversas where id = p_id;
  if v.id is null then perform public.erro('nao_encontrado', 'Conversa não encontrada.'); end if;
  if not public.suporte_pode_abrir(v.responsavel) then
    perform public.erro('sem_permissao', 'Esta conversa está com outra pessoa da equipe.');
  end if;
  return v;
end;
$$;
revoke all on function public.suporte_exigir_conversa(bigint) from public, anon;
grant execute on function public.suporte_exigir_conversa(bigint) to authenticated;

do $$
declare
  r record;
  v_def text;
  v_novo text;
begin
  for r in select * from (values
    -- Lista: sem "emails_todos", só as próprias e as sem responsável.
    ('admin_suporte_conversas(text,text,text,integer,integer)', 'perform public.exigir_admin();',
     'perform public.exigir_permissao(''emails'');
  if not public.pode(''emails_todos'') and coalesce(p_quem, ''todos'') not in (''meus'', ''sem_responsavel'') then
    p_quem := ''meus_e_livres'';
  end if;'),
    ('admin_suporte_conversas(text,text,text,integer,integer)', 'or c.responsavel = lower(p_quem))',
     'or (p_quem = ''meus_e_livres'' and (c.responsavel = v_eu or c.responsavel is null))
        or (p_quem not in (''meus'', ''sem_responsavel'', ''meus_e_livres'') and c.responsavel = lower(p_quem)))'),
    ('admin_suporte_conversa(bigint)', 'perform public.exigir_admin();', 'perform public.suporte_exigir_conversa(p_id);'),
    ('admin_suporte_status(bigint,text)', 'perform public.exigir_admin();', 'perform public.suporte_exigir_conversa(p_id);'),
    ('admin_suporte_nota(bigint,text)', 'perform public.exigir_admin();', 'perform public.suporte_exigir_conversa(p_id);'),
    ('admin_suporte_preparar_envio(bigint,text,text,text)', 'perform public.exigir_admin();',
     'perform public.exigir_permissao(''emails'');
  if p_id is not null then perform public.suporte_exigir_conversa(p_id); end if;'),
    ('admin_suporte_preparar_reenvio(bigint)', 'perform public.exigir_admin();',
     'perform public.exigir_permissao(''emails'');
  perform public.suporte_exigir_conversa((select conversa_id from public.suporte_mensagens where id = p_mensagem));'),
    -- Lista de quem pode receber uma conversa: o Marketing não atende e-mails.
    ('admin_suporte_equipe()', 'left join public.perfis p on p.id = e.usuario_id
  order by coalesce(p.e_admin, false) desc',
     'left join public.perfis p on p.id = e.usuario_id
  where e.papel <> ''marketing''
  order by coalesce(p.e_admin, false) desc'),
    -- Transferir: quem vê todos transfere qualquer uma; o Suporte só as próprias (ou assume as sem responsável).
    ('admin_suporte_transferir(bigint,text)', 'perform public.exigir_admin();',
     'perform public.suporte_exigir_conversa(p_id);
  if exists (select 1 from public.equipe e where e.email = v_email and e.papel = ''marketing'') then
    perform public.erro(''sem_permissao'', ''O cargo Marketing não atende e-mails do suporte.'');
  end if;'),
    -- Ligar e desligar "Recebe e-mails": dono e gerente para todos, o Responsável para o Atendimento.
    ('admin_suporte_rodizio(text,boolean)', 'perform public.exigir_admin();',
     'perform public.exigir_permissao(''emails_todos'');
  if not public.pode(''registro_completo'')
     and not exists (select 1 from public.equipe e where e.email = v_email and public.cargo_do_atendimento(e.papel)) then
    perform public.erro(''sem_permissao'', ''Você liga e desliga o rodízio só para o time de Atendimento.'');
  end if;
  if p_recebe and exists (select 1 from public.equipe e where e.email = v_email and e.papel = ''marketing'') then
    perform public.erro(''sem_permissao'', ''O cargo Marketing não recebe e-mails do suporte.'');
  end if;')
  ) as t(funcao, antes, depois)
  loop
    v_def := replace(pg_get_functiondef(('public.' || r.funcao)::regprocedure), E'\r\n', E'\n');
    r.antes := replace(r.antes, E'\r\n', E'\n');
    if position(r.antes in v_def) = 0 then
      if position('exigir_permissao' in v_def) > 0 or position('suporte_exigir_conversa' in v_def) > 0 then
        continue; -- já aplicado
      end if;
      raise exception 'A função % está diferente do esperado.', r.funcao;
    end if;
    v_novo := replace(v_def, r.antes, replace(r.depois, E'\r\n', E'\n'));
    execute v_novo;
  end loop;
end;
$$;

-- O HTML original de uma mensagem também segue a conversa.
create or replace function public.admin_suporte_html(p_mensagem bigint)
returns text
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.suporte_exigir_conversa((select conversa_id from public.suporte_mensagens where id = p_mensagem));
  return (select html from public.suporte_mensagens where id = p_mensagem);
end;
$$;

-- Marketing não entra no rodízio de e-mails.
update public.equipe set recebe_emails = false where papel = 'marketing';
