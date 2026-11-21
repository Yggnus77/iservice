-- Permissões por cargo e por pessoa (21/11/2026).
--
-- Pedido do dono:
--   1. Tela "Cargos": o que cada cargo acessa passa a ser editável. A mudança vale para todos do cargo.
--   2. Botão "Permissões" na Equipe: liga ou desliga telas e ações para uma pessoa, além do cargo dela.
--   3. O Gerente geral passa a ter o mesmo acesso do dono, inclusive Configurações, Cargos e Permissões,
--      e gere outros gerentes. A única diferença: ninguém além do próprio dono mexe no dono
--      (remover, mudar o cargo, suspender, mudar dados ou permissões). Passar a posição de dono
--      continua sendo só do dono.
--
-- Regras (no banco, não só na tela):
--   - O dono tem sempre tudo; o cargo Dono não é editável.
--   - "Início" fica sempre ligado para todos.
--   - Quem edita precisa da permissão "cargos" e de poder gerir aquele cargo (o dono e o gerente geral
--     gerem todos os cargos, menos o de Dono; os demais, só os cargos abaixo do seu).
--   - Ninguém muda as próprias permissões, e ninguém dá uma permissão que ele mesmo não tem.
--   - Mudar o cargo de alguém apaga as exceções pessoais dele (começa do zero no cargo novo).
--   - Tudo vai para o Registro da equipe.

-- ---------------------------------------------------------------------------
-- 1. Lista das permissões (o painel monta as chaves a partir daqui)
-- ---------------------------------------------------------------------------
create or replace function public.permissoes_catalogo()
returns table (chave text, grupo text, nome text, descricao text, ordem integer)
language sql immutable
as $$
  select * from (values
    ('inicio', 'Geral', 'Início', 'Números do dia. Sempre ligado.', 1),
    ('emails', 'Operação', 'E-mails do suporte', 'Atende os próprios e-mails e os sem responsável.', 10),
    ('emails_todos', 'Operação', 'E-mails de todos', 'Vê e transfere a conversa de qualquer pessoa e liga ou desliga o rodízio.', 11),
    ('cadastros', 'Operação', 'Cadastros', 'Vê os cadastros de profissionais em análise.', 12),
    ('cadastros_decidir', 'Operação', 'Aprovar cadastros', 'Aprova ou recusa cadastros, documentos e certificações.', 13),
    ('dados_pessoais', 'Operação', 'Dados pessoais completos', 'CPF, nascimento e documentos sem máscara.', 14),
    ('pedidos', 'Operação', 'Pedidos e pagamentos', 'Pedidos, Pagamentos e a fila Precisa de atenção.', 15),
    ('emergencias', 'Operação', 'Emergências e plantão', 'Emergências e a tela Horário, plantão e prazos.', 16),
    ('garantia', 'Operação', 'Garantia iService', 'Registra e media reclamações.', 17),
    ('garantia_decidir', 'Operação', 'Fechar reclamações', 'Fecha e reabre reclamações da Garantia.', 18),
    ('avaliacoes', 'Operação', 'Avaliações', 'Vê as avaliações e o ranking.', 19),
    ('avaliacoes_moderar', 'Operação', 'Ocultar avaliações', 'Esconde avaliações que quebram as regras.', 20),
    ('denuncias', 'Operação', 'Denúncias', 'Denúncias e avaliações suspeitas.', 21),
    ('pessoas', 'Operação', 'Pessoas', 'Consulta as contas de clientes e profissionais.', 22),
    ('pessoas_suspender', 'Operação', 'Suspender contas', 'Suspende e adverte contas.', 23),
    ('relatorios', 'Crescimento', 'Relatórios', 'Relatórios e indicadores.', 30),
    ('captacao', 'Crescimento', 'Captação', 'Funil de cadastros, metas por profissão e quem indicou.', 31),
    ('crescimento', 'Crescimento', 'Buscas, site e sugestões', 'Buscas e mapa, Site e downloads e Sugestões de profissões.', 32),
    ('comunicados', 'Crescimento', 'Comunicados e Central de Ajuda', 'Manda comunicados e edita a Central de Ajuda.', 33),
    ('catalogo', 'Catálogo', 'Profissões e regiões', 'Cria e altera profissões, especialidades e regiões.', 40),
    ('precos', 'Catálogo', 'Preços e mínimos', 'Ajusta preços de referência e valores mínimos.', 41),
    ('configuracoes', 'Catálogo', 'Configurações', 'Configurações gerais da plataforma.', 42),
    ('equipe', 'Equipe', 'Ver a equipe', 'Abre a tela Equipe.', 50),
    ('equipe_gerir', 'Equipe', 'Convidar e remover', 'Convida, remove e muda o cargo de quem está abaixo.', 51),
    ('registro', 'Equipe', 'Registro da equipe', 'Vê o que o próprio time fez no painel.', 52),
    ('registro_completo', 'Equipe', 'Registro completo', 'Vê o que todos fizeram no painel.', 53),
    ('cargos', 'Equipe', 'Cargos e permissões', 'Edita o que cada cargo e cada pessoa acessa.', 54)
  ) as t(chave, grupo, nome, descricao, ordem)
$$;

create or replace function public.permissoes_todas()
returns text[]
language sql immutable
as $$ select array_agg(chave order by ordem) from public.permissoes_catalogo() $$;

-- Só chaves conhecidas, sem repetição, na ordem da lista, com "inicio" sempre.
create or replace function public.permissoes_validas(p text[])
returns text[]
language sql immutable
as $$
  select coalesce(array_agg(c.chave order by c.ordem), '{}')
  from public.permissoes_catalogo() c
  where c.chave = 'inicio' or c.chave = any (coalesce(p, '{}'))
$$;

-- O padrão de cada cargo (o que valia até hoje; o gerente geral agora tem tudo).
create or replace function public.cargo_permissoes_padrao(p_cargo text)
returns text[]
language sql immutable
as $$
  select case p_cargo
    when 'dono' then public.permissoes_todas()
    when 'gerente' then public.permissoes_todas()
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

-- ---------------------------------------------------------------------------
-- 2. Tabelas
-- ---------------------------------------------------------------------------
-- O que cada cargo acessa, quando foi mudado na tela Cargos. Sem linha, vale o padrão.
create table if not exists public.cargo_acessos (
  cargo text primary key check (cargo in ('gerente', 'responsavel', 'suporte', 'marketing', 'captacao')),
  permissoes text[] not null,
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid references public.perfis (id) on delete set null
);
alter table public.cargo_acessos enable row level security;
revoke all on public.cargo_acessos from anon, authenticated;

-- Exceções de uma pessoa: ligada = true dá além do cargo; false tira do cargo.
create table if not exists public.equipe_permissoes (
  email text not null references public.equipe (email) on update cascade on delete cascade,
  permissao text not null,
  ligada boolean not null,
  mudado_em timestamptz not null default now(),
  mudado_por uuid references public.perfis (id) on delete set null,
  primary key (email, permissao)
);
alter table public.equipe_permissoes enable row level security;
revoke all on public.equipe_permissoes from anon, authenticated;
-- Leitura e escrita só pelas funções admin_* abaixo.

-- ---------------------------------------------------------------------------
-- 3. Permissões de cada cargo e de cada pessoa
-- ---------------------------------------------------------------------------
-- Deixa de ser fixa: lê a tela Cargos. O dono tem sempre tudo.
create or replace function public.cargo_permissoes(p_cargo text)
returns text[]
language sql stable security definer
set search_path = public
as $$
  select case
    when p_cargo is null then '{}'::text[]
    when p_cargo = 'dono' then public.permissoes_todas()
    else coalesce((select public.permissoes_validas(a.permissoes) from public.cargo_acessos a where a.cargo = p_cargo),
      public.cargo_permissoes_padrao(p_cargo)) end
$$;

-- Cargo + exceções da pessoa.
create or replace function public.permissoes_do_membro(p_email text)
returns text[]
language sql stable security definer
set search_path = public
as $$
  select case when e.papel = 'dono' then public.permissoes_todas()
    else public.permissoes_validas(array(
      select c from unnest(public.cargo_permissoes(e.papel)) c
      where not exists (select 1 from public.equipe_permissoes x where x.email = e.email and x.permissao = c and not x.ligada)
      union
      select x.permissao from public.equipe_permissoes x where x.email = e.email and x.ligada)) end
  from public.equipe e where e.email = p_email
$$;

-- Quem está logado. Conta com e_admin fora da lista da equipe fica com o acesso do Suporte, como antes.
create or replace function public.minhas_permissoes()
returns text[]
language sql stable security definer
set search_path = public
as $$
  select case when not public.e_admin() then '{}'::text[]
    else coalesce((select public.permissoes_do_membro(e.email) from public.equipe e where e.usuario_id = auth.uid() limit 1),
      public.cargo_permissoes('suporte')) end
$$;

create or replace function public.pode(p_permissao text)
returns boolean
language sql stable security definer
set search_path = public
as $$ select coalesce(p_permissao = any (public.minhas_permissoes()), false) $$;

-- O dono e o gerente geral gerem todos os cargos, menos o de Dono. Os demais, só os abaixo do seu.
create or replace function public.pode_gerir_cargo(p_cargo text)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select public.pode('equipe_gerir') and p_cargo is distinct from 'dono'
    and (public.meu_cargo() in ('dono', 'gerente') or public.cargo_nivel(public.meu_cargo()) > public.cargo_nivel(p_cargo))
$$;

-- Quem pode mexer nas permissões de um cargo: tem "cargos" e gere aquele cargo.
create or replace function public.pode_editar_cargo(p_cargo text)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select public.pode('cargos') and p_cargo is distinct from 'dono'
    and (public.meu_cargo() in ('dono', 'gerente') or public.cargo_nivel(public.meu_cargo()) > public.cargo_nivel(p_cargo))
$$;

-- A Equipe inteira para quem tem acesso completo (dono e gerente); o Atendimento para o Responsável.
create or replace function public.ve_membro(p_cargo text)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select public.pode('equipe')
    and (public.meu_cargo() in ('dono', 'gerente') or public.pode('cargos') or public.cargo_do_atendimento(p_cargo))
$$;

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
    'permissoes', to_jsonb(public.minhas_permissoes()),
    'personalizado', exists (select 1 from public.equipe e join public.equipe_permissoes x on x.email = e.email
      where e.usuario_id = auth.uid()));
end;
$$;

revoke all on function public.permissoes_catalogo() from public, anon;
revoke all on function public.permissoes_todas() from public, anon;
revoke all on function public.permissoes_validas(text[]) from public, anon;
revoke all on function public.cargo_permissoes_padrao(text) from public, anon;
revoke all on function public.cargo_permissoes(text) from public, anon;
revoke all on function public.permissoes_do_membro(text) from public, anon, authenticated;
revoke all on function public.minhas_permissoes() from public, anon;
revoke all on function public.pode(text) from public, anon;
revoke all on function public.pode_gerir_cargo(text) from public, anon;
revoke all on function public.pode_editar_cargo(text) from public, anon;
revoke all on function public.ve_membro(text) from public, anon;
revoke all on function public.admin_meu_acesso() from public, anon;
grant execute on function public.permissoes_catalogo(), public.permissoes_todas(), public.permissoes_validas(text[]),
  public.cargo_permissoes_padrao(text), public.cargo_permissoes(text), public.minhas_permissoes(), public.pode(text),
  public.pode_gerir_cargo(text), public.pode_editar_cargo(text), public.ve_membro(text), public.admin_meu_acesso() to authenticated;

-- Mudou de cargo: as exceções pessoais somem (começa do zero no cargo novo).
create or replace function public.equipe_limpar_permissoes()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if new.papel is distinct from old.papel then
    delete from public.equipe_permissoes where email = new.email;
  end if;
  return new;
end;
$$;
revoke all on function public.equipe_limpar_permissoes() from public, anon, authenticated;
drop trigger if exists equipe_limpar_permissoes on public.equipe;
create trigger equipe_limpar_permissoes after update of papel on public.equipe
  for each row execute function public.equipe_limpar_permissoes();

-- ---------------------------------------------------------------------------
-- 4. Tela Cargos
-- ---------------------------------------------------------------------------
create or replace function public.admin_cargos()
returns jsonb
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.exigir_permissao('cargos');
  return jsonb_build_object(
    'catalogo', (select jsonb_agg(to_jsonb(c) order by c.ordem) from public.permissoes_catalogo() c),
    'minhas', to_jsonb(public.minhas_permissoes()),
    'cargos', (select jsonb_agg(jsonb_build_object(
        'cargo', k.cargo, 'nome', public.cargo_nome(k.cargo),
        'permissoes', to_jsonb(public.cargo_permissoes(k.cargo)),
        'padrao', to_jsonb(public.cargo_permissoes_padrao(k.cargo)),
        'editado', a.cargo is not null, 'atualizado_em', a.atualizado_em,
        'atualizado_por', (select p.nome from public.perfis p where p.id = a.atualizado_por),
        'pode_editar', public.pode_editar_cargo(k.cargo),
        'pessoas', (select count(*) from public.equipe e where e.papel = k.cargo))
      order by k.ordem)
      from (values ('dono', 1), ('gerente', 2), ('responsavel', 3), ('suporte', 4), ('marketing', 5), ('captacao', 6)) k(cargo, ordem)
      left join public.cargo_acessos a on a.cargo = k.cargo));
end;
$$;

-- p_permissoes null = volta ao padrão do cargo.
create or replace function public.admin_salvar_cargo(p_cargo text, p_permissoes text[])
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_cargo text := btrim(coalesce(p_cargo, ''));
  v_antes text[];
  v_depois text[];
  v_minhas text[];
  v_ligou text[];
  v_desligou text[];
begin
  perform public.exigir_permissao('cargos');
  if v_cargo = 'dono' then
    perform public.erro('dono', 'O cargo Dono tem sempre acesso a tudo e não pode ser mudado.');
  end if;
  if v_cargo not in ('gerente', 'responsavel', 'suporte', 'marketing', 'captacao') then
    perform public.erro('cargo_invalido', 'Escolha um cargo da lista.');
  end if;
  if not public.pode_editar_cargo(v_cargo) then
    perform public.erro('sem_permissao', 'Você só muda as permissões dos cargos abaixo do seu.');
  end if;
  if p_permissoes is not null and exists (select 1 from unnest(p_permissoes) c where c not in (select chave from public.permissoes_catalogo())) then
    perform public.erro('permissao_invalida', 'Uma das permissões não existe. Recarregue a página.');
  end if;

  v_antes := public.cargo_permissoes(v_cargo);
  v_depois := case when p_permissoes is null then public.cargo_permissoes_padrao(v_cargo)
    else public.permissoes_validas(p_permissoes) end;
  v_minhas := public.minhas_permissoes();
  v_ligou := array(select c from unnest(v_depois) c where c <> all (v_antes));
  v_desligou := array(select c from unnest(v_antes) c where c <> all (v_depois));

  if exists (select 1 from unnest(v_ligou) c where c <> all (v_minhas)) then
    perform public.erro('sem_permissao', 'Você não pode dar a um cargo um acesso que você mesmo não tem.');
  end if;
  if v_cargo = public.meu_cargo() and 'cargos' = any (v_desligou) then
    perform public.erro('voce_mesmo', 'Você não pode tirar "Cargos e permissões" do seu próprio cargo. Peça ao dono.');
  end if;

  if p_permissoes is null then
    delete from public.cargo_acessos where cargo = v_cargo;
  else
    insert into public.cargo_acessos (cargo, permissoes, atualizado_em, atualizado_por)
    values (v_cargo, v_depois, now(), auth.uid())
    on conflict (cargo) do update set permissoes = excluded.permissoes, atualizado_em = now(), atualizado_por = auth.uid();
  end if;

  if v_ligou <> '{}' or v_desligou <> '{}' or p_permissoes is null then
    perform public.registrar_acao('editar_cargo', v_cargo, jsonb_build_object(
      'cargo', v_cargo, 'cargo_nome', public.cargo_nome(v_cargo), 'padrao', p_permissoes is null,
      'ligou', v_ligou, 'desligou', v_desligou,
      'ligou_nomes', (select coalesce(jsonb_agg(c.nome order by c.ordem), '[]') from public.permissoes_catalogo() c where c.chave = any (v_ligou)),
      'desligou_nomes', (select coalesce(jsonb_agg(c.nome order by c.ordem), '[]') from public.permissoes_catalogo() c where c.chave = any (v_desligou))));
  end if;
end;
$$;

revoke all on function public.admin_cargos() from public, anon;
revoke all on function public.admin_salvar_cargo(text, text[]) from public, anon;
grant execute on function public.admin_cargos(), public.admin_salvar_cargo(text, text[]) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Botão Permissões na Equipe
-- ---------------------------------------------------------------------------
create or replace function public.pode_permissoes_membro(p_membro public.equipe)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select p_membro.papel <> 'dono' and p_membro.usuario_id is distinct from auth.uid()
    and public.pode_editar_cargo(p_membro.papel)
$$;
revoke all on function public.pode_permissoes_membro(public.equipe) from public, anon, authenticated;

create or replace function public.admin_permissoes_membro(p_email text)
returns jsonb
language plpgsql stable security definer
set search_path = public
as $$
declare
  v public.equipe;
begin
  perform public.exigir_permissao('cargos');
  select * into v from public.equipe where email = lower(btrim(coalesce(p_email, '')));
  if v.email is null then perform public.erro('nao_encontrado', 'Esta pessoa não está mais na equipe.'); end if;
  return jsonb_build_object(
    'email', v.email, 'nome', v.nome, 'cargo', v.papel, 'cargo_nome', public.cargo_nome(v.papel),
    'pode_editar', public.pode_permissoes_membro(v),
    'catalogo', (select jsonb_agg(to_jsonb(c) order by c.ordem) from public.permissoes_catalogo() c),
    'minhas', to_jsonb(public.minhas_permissoes()),
    'do_cargo', to_jsonb(public.cargo_permissoes(v.papel)),
    'efetivas', to_jsonb(public.permissoes_do_membro(v.email)),
    'excecoes', (select coalesce(jsonb_agg(jsonb_build_object('permissao', x.permissao, 'ligada', x.ligada)), '[]')
      from public.equipe_permissoes x where x.email = v.email));
end;
$$;

-- p_permissoes = como a pessoa deve ficar. O que difere do cargo vira exceção. null = volta ao cargo.
create or replace function public.admin_salvar_permissoes_membro(p_email text, p_permissoes text[])
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v public.equipe;
  v_cargo text[];
  v_antes text[];
  v_depois text[];
  v_minhas text[];
  v_ligou text[];
  v_desligou text[];
begin
  perform public.exigir_permissao('cargos');
  select * into v from public.equipe where email = lower(btrim(coalesce(p_email, ''))) for update;
  if v.email is null then perform public.erro('nao_encontrado', 'Esta pessoa não está mais na equipe.'); end if;
  if v.papel = 'dono' then
    perform public.erro('dono', 'O dono tem sempre acesso a tudo. Só ele mesmo mexe no próprio acesso.');
  end if;
  if v.usuario_id = auth.uid() then
    perform public.erro('voce_mesmo', 'Você não pode mudar as suas próprias permissões.');
  end if;
  if not public.pode_permissoes_membro(v) then
    perform public.erro('sem_permissao', 'Você só muda as permissões de quem tem cargo abaixo do seu.');
  end if;
  if p_permissoes is not null and exists (select 1 from unnest(p_permissoes) c where c not in (select chave from public.permissoes_catalogo())) then
    perform public.erro('permissao_invalida', 'Uma das permissões não existe. Recarregue a página.');
  end if;

  v_cargo := public.cargo_permissoes(v.papel);
  v_antes := public.permissoes_do_membro(v.email);
  v_depois := case when p_permissoes is null then v_cargo else public.permissoes_validas(p_permissoes) end;
  v_minhas := public.minhas_permissoes();
  v_ligou := array(select c from unnest(v_depois) c where c <> all (v_antes));
  v_desligou := array(select c from unnest(v_antes) c where c <> all (v_depois));

  if exists (select 1 from unnest(v_ligou) c where c <> all (v_minhas)) then
    perform public.erro('sem_permissao', 'Você não pode dar um acesso que você mesmo não tem.');
  end if;

  delete from public.equipe_permissoes where email = v.email;
  insert into public.equipe_permissoes (email, permissao, ligada, mudado_por)
  select v.email, c, true, auth.uid() from unnest(v_depois) c where c <> all (v_cargo)
  union all
  select v.email, c, false, auth.uid() from unnest(v_cargo) c where c <> all (v_depois);

  if v_ligou <> '{}' or v_desligou <> '{}' then
    perform public.registrar_acao('permissoes_equipe', coalesce(v.usuario_id::text, v.email), jsonb_build_object(
      'nome', v.nome, 'email', v.email, 'cargo', v.papel, 'cargo_nome', public.cargo_nome(v.papel),
      'padrao', p_permissoes is null, 'ligou', v_ligou, 'desligou', v_desligou,
      'ligou_nomes', (select coalesce(jsonb_agg(c.nome order by c.ordem), '[]') from public.permissoes_catalogo() c where c.chave = any (v_ligou)),
      'desligou_nomes', (select coalesce(jsonb_agg(c.nome order by c.ordem), '[]') from public.permissoes_catalogo() c where c.chave = any (v_desligou))));
  end if;
end;
$$;

revoke all on function public.admin_permissoes_membro(text) from public, anon;
revoke all on function public.admin_salvar_permissoes_membro(text, text[]) from public, anon;
grant execute on function public.admin_permissoes_membro(text), public.admin_salvar_permissoes_membro(text, text[]) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Lista da equipe: diz quem tem permissões próprias e se dá para mexer nelas
-- ---------------------------------------------------------------------------
drop function if exists public.admin_equipe();
create function public.admin_equipe()
returns table (
  email text, nome text, papel text, cargo_nome text, usuario_id uuid, foto_url text, situacao text,
  convidado_por text, convidado_em timestamptz, entrou_em timestamptz, ultimo_acesso timestamptz, voce boolean,
  pode_gerir boolean, pode_foto boolean, recebe_emails boolean,
  pode_editar boolean, email_login text, senha_alterada_em timestamptz, telefone text,
  pode_permissoes boolean, permissoes_proprias integer
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
    e.recebe_emails,
    public.pode_editar_membro(e),
    u.email::text,
    (select max(a.criada_em) from public.admin_acoes a where a.acao = 'senha_equipe' and a.alvo = e.usuario_id::text),
    case when public.pode_editar_membro(e) then p.telefone end,
    public.pode_permissoes_membro(e),
    (select count(*)::integer from public.equipe_permissoes x where x.email = e.email)
  from public.equipe e
  left join public.perfis p on p.id = e.usuario_id
  left join auth.users u on u.id = e.usuario_id
  where e.usuario_id = auth.uid() or public.ve_membro(e.papel)
  order by public.cargo_nivel(e.papel) desc, (p.e_admin is true) desc, e.convidado_em;
end;
$$;
revoke all on function public.admin_equipe() from public, anon;
grant execute on function public.admin_equipe() to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Ajustes nas funções que já existem
-- ---------------------------------------------------------------------------
do $$
declare
  r record;
  v_def text;
begin
  for r in select * from (values
    -- Plantão e aviso de emergência: valem as permissões da pessoa, não só as do cargo.
    ('avisar_emergencia()', 'public.cargo_permissoes(e.papel)', 'public.permissoes_do_membro(e.email)'),
    ('admin_atendimento()', 'public.cargo_permissoes(e.papel)', 'public.permissoes_do_membro(e.email)'),
    ('admin_definir_plantao(text,boolean)', 'public.cargo_permissoes(papel)', 'public.permissoes_do_membro(email)'),
    -- Mensagens: o gerente geral também gere gerentes.
    ('admin_convidar_equipe(text,text,text)', '''Só o dono convida alguém como ''', '''Você não convida alguém como '''),
    ('admin_remover_equipe(text)', '''Só o dono remove alguém com o cargo ''', '''Você não remove alguém com o cargo '''),
    ('admin_mudar_cargo(text,text)', '''Só o dono dá ou tira o cargo de Gerente geral.''',
     '''Você só muda o cargo de quem está abaixo de você, e ninguém muda o cargo do dono.''')
  ) as t(funcao, antes, depois)
  loop
    v_def := replace(pg_get_functiondef(('public.' || r.funcao)::regprocedure), E'\r\n', E'\n');
    if position(r.antes in v_def) = 0 then
      continue; -- já aplicado (ou texto da mensagem já mudou)
    end if;
    execute replace(v_def, r.antes, r.depois);
  end loop;
end;
$$;
