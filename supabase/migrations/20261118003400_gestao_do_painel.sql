-- Ferramentas de gestão do painel (18/11/2026)
--
--  1. Cargo "relatorios": Relatórios por período (dono, gerente, responsável de setor e marketing).
--  2. Anotações internas na conta da pessoa e no pedido (só a equipe vê).
--  3. Advertência e suspensão com prazo (volta sozinha no fim do prazo).
--  4. Validade de documentos e certificações, com aviso ao profissional antes de vencer.
--  5. Respostas prontas na caixa de e-mail do suporte.
--  6. Fila "Precisa de atenção": pedidos travados e profissionais com sinais de problema.
--  7. Relatórios por período (números, por dia, por profissão, por região e os melhores profissionais).
--  8. Cadastros incompletos com lembrete ao profissional.
--  9. Contagem do menu (Precisa de atenção).
--
-- Tudo com conferência de cargo (exigir_permissao) e registro das ações da equipe (admin_acoes).

-- ---------------------------------------------------------------------------
-- 1. Permissão nova: relatorios
-- ---------------------------------------------------------------------------
create or replace function public.cargo_permissoes(p_cargo text)
returns text[]
language sql immutable
as $$
  select case p_cargo
    when 'dono' then array[
      'inicio', 'emails', 'emails_todos', 'cadastros', 'cadastros_decidir', 'dados_pessoais', 'pedidos', 'emergencias',
      'garantia', 'garantia_decidir', 'avaliacoes', 'avaliacoes_moderar', 'denuncias', 'pessoas', 'pessoas_suspender',
      'crescimento', 'comunicados', 'catalogo', 'precos', 'configuracoes', 'equipe', 'equipe_gerir', 'registro', 'registro_completo',
      'relatorios']
    when 'gerente' then array[
      'inicio', 'emails', 'emails_todos', 'cadastros', 'cadastros_decidir', 'dados_pessoais', 'pedidos', 'emergencias',
      'garantia', 'garantia_decidir', 'avaliacoes', 'avaliacoes_moderar', 'denuncias', 'pessoas', 'pessoas_suspender',
      'crescimento', 'comunicados', 'catalogo', 'precos', 'equipe', 'equipe_gerir', 'registro', 'registro_completo',
      'relatorios']
    when 'responsavel' then array[
      'inicio', 'emails', 'emails_todos', 'cadastros', 'cadastros_decidir', 'dados_pessoais', 'pedidos', 'emergencias',
      'garantia', 'garantia_decidir', 'avaliacoes', 'avaliacoes_moderar', 'denuncias', 'pessoas', 'pessoas_suspender',
      'equipe', 'registro', 'relatorios']
    when 'suporte' then array[
      'inicio', 'emails', 'cadastros', 'pedidos', 'emergencias', 'garantia', 'pessoas']
    when 'marketing' then array[
      'inicio', 'avaliacoes', 'crescimento', 'comunicados', 'relatorios']
    else '{}'::text[] end
$$;
revoke all on function public.cargo_permissoes(text) from public, anon;
grant execute on function public.cargo_permissoes(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Anotações internas
-- ---------------------------------------------------------------------------
create table if not exists public.notas_internas (
  id bigint generated always as identity primary key,
  alvo_tipo text not null check (alvo_tipo in ('pessoa', 'pedido')),
  alvo_id uuid not null,
  autor_id uuid references public.perfis (id) on delete set null,
  texto text not null check (char_length(btrim(texto)) between 1 and 2000),
  fixada boolean not null default false,
  criada_em timestamptz not null default now()
);
create index if not exists notas_internas_alvo on public.notas_internas (alvo_tipo, alvo_id, criada_em desc);
alter table public.notas_internas enable row level security;
revoke all on public.notas_internas from anon, authenticated;

create or replace function public.nota_permissao(p_tipo text)
returns text
language sql immutable
as $$ select case p_tipo when 'pessoa' then 'pessoas' when 'pedido' then 'pedidos' end $$;

create or replace function public.admin_notas(p_tipo text, p_alvo uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public
as $$
begin
  if public.nota_permissao(p_tipo) is null then perform public.erro('invalido', 'Tipo de anotação inválido.'); end if;
  perform public.exigir_permissao(public.nota_permissao(p_tipo));
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', n.id, 'texto', n.texto, 'fixada', n.fixada, 'criada_em', n.criada_em,
        'autor', coalesce(a.nome, 'Equipe'), 'autor_foto', a.foto_url, 'minha', n.autor_id = auth.uid(),
        'pode_apagar', n.autor_id = auth.uid() or public.pode('registro_completo'))
      order by n.fixada desc, n.criada_em desc)
    from public.notas_internas n left join public.perfis a on a.id = n.autor_id
    where n.alvo_tipo = p_tipo and n.alvo_id = p_alvo), '[]'::jsonb);
end;
$$;

create or replace function public.admin_anotar(p_tipo text, p_alvo uuid, p_texto text)
returns bigint
language plpgsql security definer
set search_path = public
as $$
declare
  v_id bigint;
begin
  if public.nota_permissao(p_tipo) is null then perform public.erro('invalido', 'Tipo de anotação inválido.'); end if;
  perform public.exigir_permissao(public.nota_permissao(p_tipo));
  if coalesce(btrim(p_texto), '') = '' then perform public.erro('texto_obrigatorio', 'Escreva a anotação.'); end if;
  if char_length(btrim(p_texto)) > 2000 then perform public.erro('texto_longo', 'A anotação pode ter até 2.000 letras.'); end if;
  if p_tipo = 'pessoa' and not exists (select 1 from public.perfis where id = p_alvo) then
    perform public.erro('nao_encontrado', 'Pessoa não encontrada.');
  end if;
  if p_tipo = 'pedido' and not exists (select 1 from public.pedidos where id = p_alvo) then
    perform public.erro('nao_encontrado', 'Pedido não encontrado.');
  end if;
  insert into public.notas_internas (alvo_tipo, alvo_id, autor_id, texto) values (p_tipo, p_alvo, auth.uid(), btrim(p_texto))
  returning id into v_id;
  perform public.registrar_acao('anotar', null, jsonb_build_object('tipo', p_tipo, 'alvo', p_alvo, 'nota_id', v_id));
  return v_id;
end;
$$;

create or replace function public.admin_fixar_nota(p_id bigint, p_fixada boolean)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v public.notas_internas;
begin
  select * into v from public.notas_internas where id = p_id;
  if v.id is null then perform public.erro('nao_encontrado', 'Anotação não encontrada.'); end if;
  perform public.exigir_permissao(public.nota_permissao(v.alvo_tipo));
  update public.notas_internas set fixada = coalesce(p_fixada, false) where id = p_id;
end;
$$;

create or replace function public.admin_apagar_nota(p_id bigint)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v public.notas_internas;
begin
  select * into v from public.notas_internas where id = p_id;
  if v.id is null then perform public.erro('nao_encontrado', 'Anotação não encontrada.'); end if;
  perform public.exigir_permissao(public.nota_permissao(v.alvo_tipo));
  if v.autor_id is distinct from auth.uid() and not public.pode('registro_completo') then
    perform public.erro('sem_permissao', 'Só quem escreveu, o gerente ou o dono apagam esta anotação.');
  end if;
  delete from public.notas_internas where id = p_id;
  perform public.registrar_acao('apagar_nota', null, jsonb_build_object('tipo', v.alvo_tipo, 'alvo', v.alvo_id, 'texto', v.texto));
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Advertência e suspensão com prazo
-- ---------------------------------------------------------------------------
alter table public.perfis add column if not exists suspenso_ate timestamptz;

create table if not exists public.advertencias (
  id bigint generated always as identity primary key,
  usuario_id uuid not null references public.perfis (id) on delete cascade,
  motivo text not null check (char_length(btrim(motivo)) between 3 and 500),
  admin_id uuid references public.perfis (id) on delete set null,
  criada_em timestamptz not null default now()
);
create index if not exists advertencias_usuario on public.advertencias (usuario_id, criada_em desc);
alter table public.advertencias enable row level security;
revoke all on public.advertencias from anon, authenticated;

-- Reativar a conta (pelo painel ou no fim do prazo) apaga o prazo.
create or replace function public.limpar_prazo_suspensao()
returns trigger
language plpgsql
as $$
begin
  if new.suspenso_em is null then new.suspenso_ate := null; end if;
  return new;
end;
$$;
drop trigger if exists limpar_prazo_suspensao on public.perfis;
create trigger limpar_prazo_suspensao before update of suspenso_em, suspenso_ate on public.perfis
  for each row execute function public.limpar_prazo_suspensao();
revoke all on function public.limpar_prazo_suspensao() from public, anon, authenticated;

create or replace function public.admin_advertir(p_usuario uuid, p_motivo text)
returns integer
language plpgsql security definer
set search_path = public
as $$
declare
  v_total integer;
begin
  perform public.exigir_permissao('pessoas_suspender');
  if p_usuario = auth.uid() then perform public.erro('sem_permissao', 'Você não pode advertir a própria conta.'); end if;
  if not exists (select 1 from public.perfis where id = p_usuario and excluido_em is null) then
    perform public.erro('nao_encontrado', 'Pessoa não encontrada.');
  end if;
  if coalesce(char_length(btrim(p_motivo)), 0) < 3 then perform public.erro('motivo_obrigatorio', 'Escreva o motivo da advertência.'); end if;
  if char_length(btrim(p_motivo)) > 500 then perform public.erro('texto_longo', 'O motivo pode ter até 500 letras.'); end if;
  insert into public.advertencias (usuario_id, motivo, admin_id) values (p_usuario, btrim(p_motivo), auth.uid());
  select count(*) into v_total from public.advertencias where usuario_id = p_usuario;
  perform public.notificar(p_usuario, 'advertencia', 'Aviso da equipe iService',
    btrim(p_motivo) || '. Se isso acontecer de novo, sua conta pode ser suspensa. Dúvidas: suporte@iservice.app.br.');
  perform public.registrar_acao('advertir', p_usuario::text, jsonb_build_object('motivo', btrim(p_motivo), 'total', v_total));
  return v_total;
end;
$$;

-- p_dias nulo = suspensão sem data para voltar (como antes).
create or replace function public.admin_suspender_por(p_usuario uuid, p_dias integer, p_motivo text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_ate timestamptz;
  v_motivo text;
begin
  perform public.exigir_permissao('pessoas_suspender');
  if p_dias is not null and (p_dias < 1 or p_dias > 365) then
    perform public.erro('prazo_invalido', 'Escolha um prazo de 1 a 365 dias.');
  end if;
  if coalesce(btrim(p_motivo), '') = '' then perform public.erro('motivo_obrigatorio', 'Escreva o motivo da suspensão.'); end if;
  if p_dias is not null then
    v_ate := now() + make_interval(days => p_dias);
    v_motivo := btrim(p_motivo) || ' (por ' || p_dias || case when p_dias = 1 then ' dia' else ' dias' end
      || ', até ' || to_char(v_ate at time zone 'America/Sao_Paulo', 'DD/MM/YYYY') || ')';
  else
    v_motivo := btrim(p_motivo);
  end if;
  -- Se já estava suspensa, a nova decisão vale (prazo novo ou sem prazo).
  update public.perfis set motivo_suspensao = v_motivo where id = p_usuario and suspenso_em is not null;
  perform public.admin_suspender(p_usuario, true, v_motivo);
  update public.perfis set suspenso_ate = v_ate where id = p_usuario;
  begin
    update auth.users set banned_until = coalesce(v_ate, 'infinity') where id = p_usuario;
  exception when others then null;
  end;
end;
$$;

-- Roda sozinho a cada 10 minutos: quem chegou ao fim do prazo volta a usar a plataforma.
create or replace function public.reativar_suspensoes_vencidas()
returns integer
language plpgsql security definer
set search_path = public
as $$
declare
  r record;
  n integer := 0;
begin
  for r in select id from public.perfis where suspenso_em is not null and suspenso_ate is not null and suspenso_ate <= now() loop
    update public.perfis set suspenso_em = null, motivo_suspensao = null, suspenso_ate = null where id = r.id;
    update public.profissionais set status = case when aprovado_em is not null then 'aprovado' else 'em_analise' end::public.status_cadastro,
      motivo_status = null
    where id = r.id and status = 'suspenso';
    begin
      update auth.users set banned_until = null where id = r.id;
    exception when others then null;
    end;
    perform public.notificar(r.id, 'conta_reativada', 'Sua conta foi reativada', 'O prazo da suspensão terminou. Você já pode usar o iService normalmente.');
    insert into public.admin_acoes (admin_id, acao, alvo, dados)
      values (null, 'reativar', r.id::text, jsonb_build_object('motivo', 'Fim do prazo da suspensão'));
    n := n + 1;
  end loop;
  return n;
end;
$$;
revoke all on function public.reativar_suspensoes_vencidas() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Validade de documentos e certificações
-- ---------------------------------------------------------------------------
alter table public.documentos add column if not exists valido_ate date;
alter table public.documentos add column if not exists aviso_validade_em timestamptz;
alter table public.documentos add column if not exists aviso_vencido_em timestamptz;
alter table public.certificacoes add column if not exists valido_ate date;
alter table public.certificacoes add column if not exists aviso_validade_em timestamptz;
alter table public.certificacoes add column if not exists aviso_vencido_em timestamptz;

-- Certidão de antecedentes aprovada vale 6 meses (a equipe pode mudar a data).
create or replace function public.validade_padrao_documento()
returns trigger
language plpgsql
as $$
begin
  if new.tipo = 'antecedentes' and new.status = 'aprovado' and old.status is distinct from 'aprovado' and new.valido_ate is null then
    new.valido_ate := (coalesce(new.revisado_em, now()) at time zone 'America/Sao_Paulo')::date + 182;
  end if;
  return new;
end;
$$;
drop trigger if exists validade_padrao_documento on public.documentos;
create trigger validade_padrao_documento before update of status on public.documentos
  for each row execute function public.validade_padrao_documento();
revoke all on function public.validade_padrao_documento() from public, anon, authenticated;

-- Certidões já aprovadas: 6 meses contados da aprovação.
update public.documentos set valido_ate = (coalesce(revisado_em, criado_em) at time zone 'America/Sao_Paulo')::date + 182
where tipo = 'antecedentes' and status = 'aprovado' and valido_ate is null;

create or replace function public.admin_definir_validade(p_tipo text, p_id bigint, p_valido_ate date)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_pro uuid;
  v_nome text;
begin
  perform public.exigir_permissao('cadastros_decidir');
  if p_tipo = 'documento' then
    update public.documentos set valido_ate = p_valido_ate, aviso_validade_em = null, aviso_vencido_em = null
    where id = p_id returning profissional_id, tipo::text into v_pro, v_nome;
  elsif p_tipo = 'certificacao' then
    update public.certificacoes set valido_ate = p_valido_ate, aviso_validade_em = null, aviso_vencido_em = null
    where id = p_id returning profissional_id, nome into v_pro, v_nome;
  else
    perform public.erro('invalido', 'Tipo inválido.');
  end if;
  if v_pro is null then perform public.erro('nao_encontrado', 'Documento não encontrado.'); end if;
  perform public.registrar_acao('validade_documento', v_pro::text,
    jsonb_build_object('tipo', p_tipo, 'documento', v_nome, 'valido_ate', p_valido_ate));
end;
$$;

-- Documentos e certificações aprovados que vencem em até p_dias (ou já venceram).
create or replace function public.validades_lista(p_dias integer, p_profissional uuid default null)
returns setof jsonb
language sql stable security definer
set search_path = public
as $$
  with hoje as (select (now() at time zone 'America/Sao_Paulo')::date as d)
  select jsonb_build_object('chave', 'doc:documento:' || d.id || ':' || d.valido_ate, 'tipo', 'documento', 'id', d.id, 'profissional_id', d.profissional_id, 'nome', pe.nome, 'foto_url', pe.foto_url,
      'documento', case d.tipo when 'antecedentes' then 'Certidão de antecedentes' when 'documento_frente' then 'Documento (frente)'
        when 'documento_verso' then 'Documento (verso)' when 'selfie_documento' then 'Selfie com documento' else 'Comprovante de endereço' end,
      'tipo_documento', d.tipo, 'valido_ate', d.valido_ate, 'dias', d.valido_ate - h.d, 'vencido', d.valido_ate < h.d,
      'avisado_em', coalesce(d.aviso_vencido_em, d.aviso_validade_em),
      'novo_enviado', exists (select 1 from public.documentos n where n.profissional_id = d.profissional_id and n.tipo = d.tipo
        and n.id > d.id and n.status = 'pendente'))
  from public.documentos d join public.perfis pe on pe.id = d.profissional_id, hoje h
  where d.status = 'aprovado' and d.valido_ate is not null and d.valido_ate <= h.d + p_dias
    and (p_profissional is null or d.profissional_id = p_profissional)
    and not exists (select 1 from public.documentos n where n.profissional_id = d.profissional_id and n.tipo = d.tipo
      and n.id > d.id and n.status = 'aprovado')
  union all
  select jsonb_build_object('chave', 'doc:certificacao:' || c.id || ':' || c.valido_ate, 'tipo', 'certificacao', 'id', c.id, 'profissional_id', c.profissional_id, 'nome', pe.nome, 'foto_url', pe.foto_url,
      'documento', 'Certificação: ' || c.nome, 'tipo_documento', 'certificacao', 'valido_ate', c.valido_ate, 'dias', c.valido_ate - h.d,
      'vencido', c.valido_ate < h.d, 'avisado_em', coalesce(c.aviso_vencido_em, c.aviso_validade_em), 'novo_enviado', false)
  from public.certificacoes c join public.perfis pe on pe.id = c.profissional_id, hoje h
  where c.status = 'aprovado' and c.valido_ate is not null and c.valido_ate <= h.d + p_dias
    and (p_profissional is null or c.profissional_id = p_profissional)
$$;
revoke all on function public.validades_lista(integer, uuid) from public, anon, authenticated;

create or replace function public.admin_validades(p_dias integer default 30, p_profissional uuid default null)
returns jsonb
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.exigir_permissao('cadastros');
  return coalesce((select jsonb_agg(x order by (x ->> 'valido_ate')) from public.validades_lista(greatest(0, least(coalesce(p_dias, 30), 365)), p_profissional) x), '[]'::jsonb);
end;
$$;

-- Todo dia de manhã: avisa 30 dias antes e no dia em que vence.
create or replace function public.avisar_validades()
returns integer
language plpgsql security definer
set search_path = public
as $$
declare
  r record;
  n integer := 0;
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_doc text;
begin
  for r in select 'documento' as tipo, d.id, d.profissional_id, d.tipo::text as qual, null::text as nome, d.valido_ate,
                  d.aviso_validade_em, d.aviso_vencido_em
           from public.documentos d where d.status = 'aprovado' and d.valido_ate is not null and d.valido_ate <= v_hoje + 30
             and not exists (select 1 from public.documentos n where n.profissional_id = d.profissional_id and n.tipo = d.tipo and n.id > d.id and n.status <> 'recusado')
           union all
           select 'certificacao', c.id, c.profissional_id, 'certificacao', c.nome, c.valido_ate, c.aviso_validade_em, c.aviso_vencido_em
           from public.certificacoes c where c.status = 'aprovado' and c.valido_ate is not null and c.valido_ate <= v_hoje + 30 loop
    v_doc := case when r.tipo = 'certificacao' then 'a certificação "' || r.nome || '"'
      when r.qual = 'antecedentes' then 'sua certidão de antecedentes' else 'seu documento' end;
    if r.valido_ate < v_hoje and r.aviso_vencido_em is null then
      perform public.notificar(r.profissional_id, 'documento_vencido', 'Documento vencido',
        'A validade de ' || v_doc || ' terminou em ' || to_char(r.valido_ate, 'DD/MM/YYYY') || '. Envie um novo pelo app para continuar atendendo.',
        jsonb_build_object('tipo', r.tipo, 'id', r.id));
      if r.tipo = 'documento' then update public.documentos set aviso_vencido_em = now() where id = r.id;
      else update public.certificacoes set aviso_vencido_em = now() where id = r.id; end if;
      n := n + 1;
    elsif r.valido_ate >= v_hoje and r.aviso_validade_em is null then
      perform public.notificar(r.profissional_id, 'documento_vencendo', 'Seu documento vai vencer',
        'A validade de ' || v_doc || ' termina em ' || to_char(r.valido_ate, 'DD/MM/YYYY') || '. Já pode enviar um novo pelo app.',
        jsonb_build_object('tipo', r.tipo, 'id', r.id));
      if r.tipo = 'documento' then update public.documentos set aviso_validade_em = now() where id = r.id;
      else update public.certificacoes set aviso_validade_em = now() where id = r.id; end if;
      n := n + 1;
    end if;
  end loop;
  return n;
end;
$$;
revoke all on function public.avisar_validades() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. Respostas prontas da caixa de e-mail
-- ---------------------------------------------------------------------------
create table if not exists public.suporte_respostas (
  id bigint generated always as identity primary key,
  titulo text not null check (char_length(btrim(titulo)) between 2 and 80),
  texto text not null check (char_length(btrim(texto)) between 2 and 5000),
  usos integer not null default 0,
  criado_por uuid references public.perfis (id) on delete set null,
  atualizado_em timestamptz not null default now()
);
create unique index if not exists suporte_respostas_titulo on public.suporte_respostas (lower(titulo));
alter table public.suporte_respostas enable row level security;
revoke all on public.suporte_respostas from anon, authenticated;

insert into public.suporte_respostas (titulo, texto) values
  ('Boas-vindas ao atendimento', E'Olá, {nome}!\n\nObrigado por falar com o iService. Recebemos a sua mensagem (protocolo {protocolo}) e já estamos cuidando dela. Respondemos o quanto antes.\n\nUm abraço,\n{atendente}'),
  ('Esqueci minha senha', E'Olá, {nome}!\n\nPara criar uma senha nova, abra o app, toque em "Entrar" e depois em "Esqueci minha senha". Enviamos um link para o seu e-mail. Se não aparecer em alguns minutos, olhe também a caixa de spam.\n\nQualquer coisa, é só responder este e-mail.\n\n{atendente}'),
  ('Cadastro em análise', E'Olá, {nome}!\n\nRecebemos o seu cadastro de profissional e ele está na fila de conferência. Olhamos documento, selfie e, quando a profissão exige, a certidão de antecedentes. Você recebe um aviso no app assim que for aprovado.\n\n{atendente}'),
  ('Enviar documento de novo', E'Olá, {nome}!\n\nPrecisamos que você envie de novo uma foto do documento pelo app, em Perfil > Cadastro. Dicas: boa luz, sem reflexo, documento inteiro na foto e dados legíveis.\n\nAssim que chegar, conferimos rapidinho.\n\n{atendente}'),
  ('Como funciona a Garantia iService', E'Olá, {nome}!\n\nA Garantia iService vale por 30 dias depois que o serviço é concluído. Se algo não ficou como combinado, abra o pedido no app e toque em "Abrir reclamação". A nossa equipe conversa com você e com o profissional para resolver.\n\n{atendente}'),
  ('Pagamento direto ao profissional', E'Olá, {nome}!\n\nNo iService o pagamento é feito direto ao profissional, do jeito que vocês combinarem (Pix, dinheiro ou cartão, se ele aceitar). O app não cobra nada de você pelo pedido.\n\n{atendente}'),
  ('Excluir a conta', E'Olá, {nome}!\n\nPara excluir a sua conta, abra o app, vá em Perfil > Excluir conta, ou use a página https://iservice.app.br/excluir-conta.html. Seus dados são apagados conforme a nossa Política de Privacidade.\n\n{atendente}'),
  ('Encerrar atendimento', E'Olá, {nome}!\n\nQue bom que deu certo. Vamos encerrar este atendimento (protocolo {protocolo}). Se precisar de algo mais, é só responder este e-mail que ele volta para nós.\n\nObrigado por usar o iService!\n{atendente}')
on conflict do nothing;

create or replace function public.admin_respostas_prontas()
returns jsonb
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.exigir_permissao('emails');
  return coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'titulo', r.titulo, 'texto', r.texto, 'usos', r.usos,
      'atualizado_em', r.atualizado_em) order by r.usos desc, r.titulo) from public.suporte_respostas r), '[]'::jsonb);
end;
$$;

create or replace function public.admin_salvar_resposta(p_id bigint, p_titulo text, p_texto text)
returns bigint
language plpgsql security definer
set search_path = public
as $$
declare
  v_id bigint;
begin
  perform public.exigir_permissao('emails_todos');
  if coalesce(char_length(btrim(p_titulo)), 0) < 2 then perform public.erro('titulo_obrigatorio', 'Dê um nome curto para a resposta.'); end if;
  if char_length(btrim(p_titulo)) > 80 then perform public.erro('texto_longo', 'O nome pode ter até 80 letras.'); end if;
  if coalesce(char_length(btrim(p_texto)), 0) < 2 then perform public.erro('texto_obrigatorio', 'Escreva o texto da resposta.'); end if;
  if char_length(btrim(p_texto)) > 5000 then perform public.erro('texto_longo', 'O texto pode ter até 5.000 letras.'); end if;
  if exists (select 1 from public.suporte_respostas where lower(titulo) = lower(btrim(p_titulo)) and id is distinct from p_id) then
    perform public.erro('repetida', 'Já existe uma resposta com esse nome.');
  end if;
  if p_id is null then
    insert into public.suporte_respostas (titulo, texto, criado_por) values (btrim(p_titulo), btrim(p_texto), auth.uid()) returning id into v_id;
  else
    update public.suporte_respostas set titulo = btrim(p_titulo), texto = btrim(p_texto), atualizado_em = now() where id = p_id returning id into v_id;
    if v_id is null then perform public.erro('nao_encontrado', 'Resposta não encontrada.'); end if;
  end if;
  perform public.registrar_acao('salvar_resposta_pronta', null, jsonb_build_object('id', v_id, 'titulo', btrim(p_titulo)));
  return v_id;
end;
$$;

create or replace function public.admin_apagar_resposta(p_id bigint)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_titulo text;
begin
  perform public.exigir_permissao('emails_todos');
  delete from public.suporte_respostas where id = p_id returning titulo into v_titulo;
  if v_titulo is null then perform public.erro('nao_encontrado', 'Resposta não encontrada.'); end if;
  perform public.registrar_acao('apagar_resposta_pronta', null, jsonb_build_object('id', p_id, 'titulo', v_titulo));
end;
$$;

create or replace function public.admin_usar_resposta(p_id bigint)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  perform public.exigir_permissao('emails');
  update public.suporte_respostas set usos = usos + 1 where id = p_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Precisa de atenção
-- ---------------------------------------------------------------------------
-- O que alguém da equipe marcou como "já tratei". Volta a aparecer depois de 30 dias,
-- ou antes, quando o problema muda (a chave muda).
create table if not exists public.atencao_vistos (
  chave text primary key check (char_length(chave) <= 200),
  admin_id uuid references public.perfis (id) on delete set null,
  visto_em timestamptz not null default now()
);
alter table public.atencao_vistos enable row level security;
revoke all on public.atencao_vistos from anon, authenticated;

create or replace function public.atencao_visto(p_chave text)
returns boolean
language sql stable security definer
set search_path = public
as $$ select exists (select 1 from public.atencao_vistos v where v.chave = p_chave and v.visto_em > now() - interval '30 days') $$;
revoke all on function public.atencao_visto(text) from public, anon, authenticated;

-- Pedidos travados ou que deram errado nas últimas 24 horas.
create or replace function public.atencao_pedidos_lista()
returns setof jsonb
language sql stable security definer
set search_path = public
as $$
  with itens as (
    select p.*, 'nao_saiu'::text as tipo,
      case p.quando when 'combinado' then p.combinado_para else p.aceito_em end as desde,
      case p.quando when 'combinado' then 'Aceito, mas o profissional não saiu para o local no horário marcado'
        else 'Aceito há muito tempo e o profissional ainda não saiu para o local' end as texto, 2 as gravidade
    from public.pedidos p
    where p.status = 'aceito' and (
      (p.quando = 'combinado' and p.combinado_para < now() - interval '20 minutes')
      or (p.quando = 'agora' and p.aceito_em < now() - interval '40 minutes')
      or (p.quando = 'hoje' and p.aceito_em < now() - interval '5 hours'))
    union all
    select p.*, 'demorando_chegar', p.a_caminho_em, 'A caminho há mais de 1h30 e ainda não chegou', 2
    from public.pedidos p where p.status = 'a_caminho' and p.a_caminho_em < now() - interval '90 minutes'
    union all
    select p.*, 'servico_longo', p.iniciado_em, 'Serviço em andamento há mais de 10 horas (pode ter esquecido de concluir)', 1
    from public.pedidos p where p.status = 'em_atendimento' and p.iniciado_em < now() - interval '10 hours'
    union all
    select p.*, 'cancelou_apos_aceite', p.encerrado_em, 'O profissional cancelou depois de aceitar', 2
    from public.pedidos p
    where p.status = 'cancelado' and p.cancelado_por = p.profissional_id and p.aceito_em is not null
      and p.encerrado_em > now() - interval '24 hours'
    union all
    select p.*, 'cliente_sem_atendimento', p.encerrado_em,
      case p.status when 'expirado' then 'Ninguém respondeu e o cliente não pediu a outro profissional'
        else 'O profissional recusou e o cliente não pediu a outro' end, 1
    from public.pedidos p
    where p.status in ('recusado', 'expirado') and p.encerrado_em > now() - interval '24 hours'
      and not exists (select 1 from public.pedidos o where o.cliente_id = p.cliente_id and o.criado_em > p.criado_em)
  )
  select jsonb_build_object('chave', i.tipo || ':' || i.id, 'tipo', i.tipo, 'texto', i.texto, 'gravidade', i.gravidade, 'desde', i.desde,
      'pedido_id', i.id, 'codigo', i.codigo, 'status', i.status, 'quando', i.quando, 'combinado_para', i.combinado_para,
      'profissao', (select f.nome from public.profissoes f where f.id = i.profissao_id),
      'regiao', (select r.nome from public.regioes r where r.id = i.regiao_id),
      'cliente_id', i.cliente_id, 'cliente', (select c.nome from public.perfis c where c.id = i.cliente_id),
      'profissional_id', i.profissional_id, 'profissional', (select c.nome from public.perfis c where c.id = i.profissional_id))
  from itens i
  where not public.atencao_visto(i.tipo || ':' || i.id)
  order by i.gravidade desc, i.desde
$$;
revoke all on function public.atencao_pedidos_lista() from public, anon, authenticated;

-- Profissionais aprovados com sinais de problema.
create or replace function public.alertas_profissionais_lista(p_profissional uuid default null)
returns setof jsonb
language sql stable security definer
set search_path = public
as $$
  with base as (
    select pr.id, pe.nome, pe.foto_url, pr.nota_media, pr.total_avaliacoes, pr.status,
      (select count(*) from public.pedidos p where p.profissional_id = pr.id and p.criado_em > now() - interval '30 days') as recebidos,
      (select count(*) from public.pedidos p where p.profissional_id = pr.id and p.criado_em > now() - interval '30 days' and p.aceito_em is not null) as aceitos,
      (select count(*) from public.pedidos p where p.profissional_id = pr.id and p.criado_em > now() - interval '30 days' and p.status = 'expirado') as sem_resposta,
      (select count(*) from public.pedidos p where p.profissional_id = pr.id and p.encerrado_em > now() - interval '30 days'
        and p.status = 'cancelado' and p.cancelado_por = pr.id and p.aceito_em is not null) as cancelou,
      (select count(*) from public.denuncias d where d.alvo_id = pr.id and d.status in ('aberta', 'em_analise')) as denuncias,
      (select count(*) from public.reclamacoes r join public.pedidos p on p.id = r.pedido_id
        where p.profissional_id = pr.id and r.criada_em > now() - interval '90 days') as reclamacoes,
      (select count(*) from public.advertencias a where a.usuario_id = pr.id and a.criada_em > now() - interval '90 days') as advertencias,
      (select count(*) from (select 1 from public.avaliacoes a where a.profissional_id = pr.id and not a.oculta order by a.criada_em desc limit 10) u) as n_ult,
      (select avg(u.nota) from (select a.nota from public.avaliacoes a where a.profissional_id = pr.id and not a.oculta order by a.criada_em desc limit 10) u) as nota_ult
    from public.profissionais pr join public.perfis pe on pe.id = pr.id
    where pr.status = 'aprovado' and pe.suspenso_em is null and (p_profissional is null or pr.id = p_profissional)
  ), motivos as (
    select b.*, array_remove(array[
        case when b.cancelou >= 3 then jsonb_build_object('codigo', 'cancelou', 'nivel', 'alto',
          'texto', 'Cancelou ' || b.cancelou || ' serviços depois de aceitar (30 dias)') end,
        case when b.denuncias >= 1 then jsonb_build_object('codigo', 'denuncia', 'nivel', 'alto',
          'texto', b.denuncias || case when b.denuncias = 1 then ' denúncia aberta' else ' denúncias abertas' end) end,
        case when b.reclamacoes >= 2 then jsonb_build_object('codigo', 'garantia', 'nivel', 'alto',
          'texto', b.reclamacoes || ' reclamações da garantia (90 dias)') end,
        case when b.n_ult >= 3 and b.nota_ult < 3.5 then jsonb_build_object('codigo', 'nota', 'nivel', 'alto',
          'texto', 'Nota das últimas ' || b.n_ult || ' avaliações: ' || replace(to_char(b.nota_ult, 'FM0.0'), '.', ','))
          when b.n_ult >= 3 and b.nota_ult < 4.0 then jsonb_build_object('codigo', 'nota', 'nivel', 'medio',
          'texto', 'Nota das últimas ' || b.n_ult || ' avaliações: ' || replace(to_char(b.nota_ult, 'FM0.0'), '.', ',')) end,
        case when b.sem_resposta >= 3 then jsonb_build_object('codigo', 'sem_resposta', 'nivel', 'medio',
          'texto', 'Deixou ' || b.sem_resposta || ' pedidos sem resposta (30 dias)') end,
        case when b.recebidos >= 5 and b.aceitos::numeric / b.recebidos < 0.5 then jsonb_build_object('codigo', 'aceite', 'nivel', 'medio',
          'texto', 'Aceitou só ' || round(100.0 * b.aceitos / b.recebidos) || '% dos pedidos (30 dias)') end
      ], null) as lista
    from base b
  )
  select jsonb_build_object('chave', 'prof:' || m.id || ':' || (select string_agg(x ->> 'codigo', ',' order by x ->> 'codigo') from unnest(m.lista) x),
      'profissional_id', m.id, 'nome', m.nome, 'foto_url', m.foto_url, 'nota_media', m.nota_media, 'total_avaliacoes', m.total_avaliacoes,
      'advertencias', m.advertencias, 'motivos', to_jsonb(m.lista),
      'gravidade', case when exists (select 1 from unnest(m.lista) x where x ->> 'nivel' = 'alto') then 2 else 1 end)
  from motivos m
  where cardinality(m.lista) > 0
    and (p_profissional is not null or not public.atencao_visto(
      'prof:' || m.id || ':' || (select string_agg(x ->> 'codigo', ',' order by x ->> 'codigo') from unnest(m.lista) x)))
  order by case when exists (select 1 from unnest(m.lista) x where x ->> 'nivel' = 'alto') then 0 else 1 end, cardinality(m.lista) desc, m.nome
$$;
revoke all on function public.alertas_profissionais_lista(uuid) from public, anon, authenticated;

create or replace function public.admin_atencao()
returns jsonb
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.exigir_admin();
  if not (public.pode('pedidos') or public.pode('pessoas') or public.pode('cadastros')) then
    perform public.erro('sem_permissao', 'Seu cargo não tem acesso a esta parte do painel. Fale com o seu gerente.');
  end if;
  return jsonb_build_object(
    'pedidos', case when public.pode('pedidos') then coalesce((select jsonb_agg(x) from public.atencao_pedidos_lista() x), '[]'::jsonb) end,
    'profissionais', case when public.pode('pessoas') then coalesce((select jsonb_agg(x) from public.alertas_profissionais_lista(null) x), '[]'::jsonb) end,
    'documentos', case when public.pode('cadastros') then coalesce((select jsonb_agg(x order by (x ->> 'valido_ate')) from public.validades_lista(30, null) x
        where not public.atencao_visto(x ->> 'chave')), '[]'::jsonb) end);
end;
$$;

create or replace function public.admin_atencao_contagem()
returns jsonb
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_ped integer := 0;
  v_pro integer := 0;
  v_doc integer := 0;
begin
  perform public.exigir_admin();
  if public.pode('pedidos') then select count(*) into v_ped from public.atencao_pedidos_lista(); end if;
  if public.pode('pessoas') then select count(*) into v_pro from public.alertas_profissionais_lista(null); end if;
  if public.pode('cadastros') then
    select count(*) into v_doc from public.validades_lista(30, null) x where not public.atencao_visto(x ->> 'chave');
  end if;
  return jsonb_build_object('pedidos', v_ped, 'profissionais', v_pro, 'documentos', v_doc, 'total', v_ped + v_pro + v_doc);
end;
$$;

create or replace function public.admin_atencao_tratado(p_chave text, p_observacao text default null)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  perform public.exigir_permissao(case split_part(p_chave, ':', 1) when 'prof' then 'pessoas' when 'doc' then 'cadastros' else 'pedidos' end);
  if coalesce(p_chave, '') = '' or char_length(p_chave) > 200 then perform public.erro('invalido', 'Item inválido.'); end if;
  insert into public.atencao_vistos (chave, admin_id, visto_em) values (p_chave, auth.uid(), now())
  on conflict (chave) do update set admin_id = excluded.admin_id, visto_em = excluded.visto_em;
  perform public.registrar_acao('atencao_tratado',
    case split_part(p_chave, ':', 1) when 'prof' then split_part(p_chave, ':', 2) when 'doc' then null else split_part(p_chave, ':', 2) end,
    jsonb_build_object('chave', p_chave, 'observacao', nullif(btrim(coalesce(p_observacao, '')), '')));
end;
$$;

-- Dados extras da ficha da pessoa: anotações, advertências, prazo da suspensão, alertas e validades.
create or replace function public.admin_gestao_pessoa(p_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.exigir_permissao('pessoas');
  return jsonb_build_object(
    'suspenso_ate', (select suspenso_ate from public.perfis where id = p_id),
    'advertencias', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'motivo', a.motivo, 'criada_em', a.criada_em,
        'admin', coalesce(ad.nome, 'Equipe')) order by a.criada_em desc)
      from public.advertencias a left join public.perfis ad on ad.id = a.admin_id where a.usuario_id = p_id), '[]'::jsonb),
    'alertas', coalesce((select x -> 'motivos' from public.alertas_profissionais_lista(p_id) x limit 1), '[]'::jsonb),
    'validades', case when public.pode('cadastros')
      then coalesce((select jsonb_agg(x order by (x ->> 'valido_ate')) from public.validades_lista(30, p_id) x), '[]'::jsonb) end);
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Relatórios por período
-- ---------------------------------------------------------------------------
create or replace function public.relatorio_totais(p_ini timestamptz, p_fim timestamptz)
returns jsonb
language sql stable security definer
set search_path = public
as $$
  select jsonb_build_object(
    'pedidos', count(*),
    'concluidos', count(*) filter (where p.status = 'concluido'),
    'em_andamento', count(*) filter (where p.status in ('solicitado', 'aceito', 'a_caminho', 'em_atendimento')),
    'aceitos', count(*) filter (where p.aceito_em is not null),
    'recusados', count(*) filter (where p.status = 'recusado'),
    'sem_resposta', count(*) filter (where p.status = 'expirado'),
    'cancelados_cliente', count(*) filter (where p.status = 'cancelado' and p.cancelado_por = p.cliente_id),
    'cancelados_profissional', count(*) filter (where p.status = 'cancelado' and p.cancelado_por = p.profissional_id),
    'cancelados_equipe', count(*) filter (where p.status = 'cancelado' and p.cancelado_por is distinct from p.cliente_id
      and p.cancelado_por is distinct from p.profissional_id),
    'taxa_aceite', round(100.0 * count(*) filter (where p.aceito_em is not null)
      / nullif(count(*) filter (where p.status not in ('solicitado') or p.aceito_em is not null), 0), 1),
    'tempo_resposta_min', round((percentile_cont(0.5) within group (order by extract(epoch from (coalesce(p.respondido_em, p.aceito_em) - p.criado_em)) / 60.0)
      filter (where coalesce(p.respondido_em, p.aceito_em) is not null))::numeric, 1),
    'valor_concluido', coalesce(sum(coalesce(p.valor_cobrado, p.preco_informado + p.taxa_urgencia + p.taxa_fora_horario))
      filter (where p.status = 'concluido'), 0),
    'ticket_medio', round(avg(coalesce(p.valor_cobrado, p.preco_informado + p.taxa_urgencia + p.taxa_fora_horario))
      filter (where p.status = 'concluido'), 2),
    'clientes_que_pediram', count(distinct p.cliente_id),
    'profissionais_que_atenderam', count(distinct p.profissional_id) filter (where p.status = 'concluido'),
    'urgentes', count(*) filter (where p.quando = 'agora'),
    'agendados', count(*) filter (where p.quando = 'combinado'),
    'avaliacoes', (select count(*) from public.avaliacoes a where a.criada_em >= p_ini and a.criada_em < p_fim),
    'nota_media', (select round(avg(a.nota), 2) from public.avaliacoes a where a.criada_em >= p_ini and a.criada_em < p_fim and not a.oculta),
    'clientes_novos', (select count(*) from public.perfis x where x.e_cliente and x.criado_em >= p_ini and x.criado_em < p_fim),
    'profissionais_novos', (select count(*) from public.profissionais x where x.criado_em >= p_ini and x.criado_em < p_fim),
    'profissionais_aprovados', (select count(*) from public.profissionais x where x.aprovado_em >= p_ini and x.aprovado_em < p_fim),
    'buscas', (select count(*) from public.buscas b where b.criada_em >= p_ini and b.criada_em < p_fim),
    'buscas_sem_resultado', (select count(*) from public.buscas b where b.criada_em >= p_ini and b.criada_em < p_fim and b.resultados = 0),
    'reclamacoes', (select count(*) from public.reclamacoes r where r.criada_em >= p_ini and r.criada_em < p_fim),
    'denuncias', (select count(*) from public.denuncias d where d.criada_em >= p_ini and d.criada_em < p_fim),
    'emergencias', (select count(*) from public.emergencias e where e.criada_em >= p_ini and e.criada_em < p_fim))
  from public.pedidos p where p.criado_em >= p_ini and p.criado_em < p_fim
$$;
revoke all on function public.relatorio_totais(timestamptz, timestamptz) from public, anon, authenticated;

create or replace function public.admin_relatorio(p_inicio date, p_fim date)
returns jsonb
language plpgsql stable security definer
set search_path = public
set timezone = 'America/Sao_Paulo'
as $$
declare
  v_ini timestamptz;
  v_fim timestamptz;
  v_dias integer;
begin
  perform public.exigir_permissao('relatorios');
  if p_inicio is null or p_fim is null or p_fim < p_inicio then perform public.erro('periodo_invalido', 'Escolha um período válido.'); end if;
  v_dias := p_fim - p_inicio + 1;
  if v_dias > 400 then perform public.erro('periodo_longo', 'Escolha um período de até 400 dias.'); end if;
  v_ini := p_inicio::timestamptz;
  v_fim := (p_fim + 1)::timestamptz;
  return jsonb_build_object(
    'inicio', p_inicio, 'fim', p_fim, 'dias', v_dias,
    'atual', public.relatorio_totais(v_ini, v_fim),
    'anterior', public.relatorio_totais(v_ini - make_interval(days => v_dias), v_ini),
    'por_dia', (select coalesce(jsonb_agg(jsonb_build_object('dia', d.dia,
        'pedidos', (select count(*) from public.pedidos p where p.criado_em >= d.dia::timestamptz and p.criado_em < (d.dia + 1)::timestamptz),
        'concluidos', (select count(*) from public.pedidos p where p.criado_em >= d.dia::timestamptz and p.criado_em < (d.dia + 1)::timestamptz and p.status = 'concluido'),
        'cancelados', (select count(*) from public.pedidos p where p.criado_em >= d.dia::timestamptz and p.criado_em < (d.dia + 1)::timestamptz and p.status in ('cancelado', 'recusado', 'expirado')),
        'buscas', (select count(*) from public.buscas b where b.criada_em >= d.dia::timestamptz and b.criada_em < (d.dia + 1)::timestamptz),
        'clientes_novos', (select count(*) from public.perfis x where x.e_cliente and x.criado_em >= d.dia::timestamptz and x.criado_em < (d.dia + 1)::timestamptz),
        'profissionais_novos', (select count(*) from public.profissionais x where x.criado_em >= d.dia::timestamptz and x.criado_em < (d.dia + 1)::timestamptz))
      order by d.dia), '[]'::jsonb)
      from (select generate_series(p_inicio, p_fim, interval '1 day')::date as dia) d),
    'por_profissao', (select coalesce(jsonb_agg(x order by (x ->> 'pedidos')::int desc, x ->> 'nome'), '[]'::jsonb) from (
      select jsonb_build_object('id', f.id, 'nome', f.nome,
        'pedidos', count(p.id), 'concluidos', count(p.id) filter (where p.status = 'concluido'),
        'cancelados', count(p.id) filter (where p.status in ('cancelado', 'recusado', 'expirado')),
        'valor', coalesce(sum(coalesce(p.valor_cobrado, p.preco_informado + p.taxa_urgencia + p.taxa_fora_horario)) filter (where p.status = 'concluido'), 0),
        'nota', (select round(avg(a.nota), 1) from public.avaliacoes a join public.pedidos q on q.id = a.pedido_id
          where q.profissao_id = f.id and a.criada_em >= v_ini and a.criada_em < v_fim and not a.oculta),
        'buscas', (select count(*) from public.buscas b where b.profissao_id = f.id and b.criada_em >= v_ini and b.criada_em < v_fim),
        'buscas_sem_resultado', (select count(*) from public.buscas b where b.profissao_id = f.id and b.criada_em >= v_ini and b.criada_em < v_fim and b.resultados = 0),
        'profissionais', (select count(*) from public.profissional_profissoes pp join public.profissionais pr on pr.id = pp.profissional_id
          where pp.profissao_id = f.id and pr.status = 'aprovado')) x
      from public.profissoes f left join public.pedidos p on p.profissao_id = f.id and p.criado_em >= v_ini and p.criado_em < v_fim
      group by f.id, f.nome) s),
    'por_regiao', (select coalesce(jsonb_agg(x order by (x ->> 'pedidos')::int desc, x ->> 'nome'), '[]'::jsonb) from (
      select jsonb_build_object('id', r.id, 'nome', r.nome,
        'pedidos', count(p.id), 'concluidos', count(p.id) filter (where p.status = 'concluido'),
        'valor', coalesce(sum(coalesce(p.valor_cobrado, p.preco_informado + p.taxa_urgencia + p.taxa_fora_horario)) filter (where p.status = 'concluido'), 0),
        'buscas', (select count(*) from public.buscas b where b.regiao_id = r.id and b.criada_em >= v_ini and b.criada_em < v_fim),
        'buscas_sem_resultado', (select count(*) from public.buscas b where b.regiao_id = r.id and b.criada_em >= v_ini and b.criada_em < v_fim and b.resultados = 0)) x
      from public.regioes r left join public.pedidos p on p.regiao_id = r.id and p.criado_em >= v_ini and p.criado_em < v_fim
      group by r.id, r.nome) s),
    'top_profissionais', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
      select jsonb_build_object('id', pe.id, 'nome', pe.nome, 'foto_url', pe.foto_url, 'concluidos', count(*),
        'valor', coalesce(sum(coalesce(p.valor_cobrado, p.preco_informado + p.taxa_urgencia + p.taxa_fora_horario)), 0),
        'nota', (select round(avg(a.nota), 1) from public.avaliacoes a join public.pedidos q on q.id = a.pedido_id
          where q.profissional_id = pe.id and a.criada_em >= v_ini and a.criada_em < v_fim and not a.oculta),
        'profissoes', (select string_agg(f.nome, ', ' order by pp.principal desc, f.ordem) from public.profissional_profissoes pp
          join public.profissoes f on f.id = pp.profissao_id where pp.profissional_id = pe.id)) x
      from public.pedidos p join public.perfis pe on pe.id = p.profissional_id
      where p.status = 'concluido' and p.criado_em >= v_ini and p.criado_em < v_fim
      group by pe.id, pe.nome, pe.foto_url
      order by count(*) desc, pe.nome limit 15) s));
end;
$$;

-- Planilha de pedidos do período (até 5.000 linhas).
create or replace function public.admin_planilha_pedidos(p_inicio date, p_fim date)
returns jsonb
language plpgsql stable security definer
set search_path = public
set timezone = 'America/Sao_Paulo'
as $$
begin
  perform public.exigir_permissao('pedidos');
  if p_inicio is null or p_fim is null or p_fim < p_inicio then perform public.erro('periodo_invalido', 'Escolha um período válido.'); end if;
  if p_fim - p_inicio > 400 then perform public.erro('periodo_longo', 'Escolha um período de até 400 dias.'); end if;
  return coalesce((select jsonb_agg(x) from (
    select jsonb_build_object('codigo', p.codigo, 'criado_em', p.criado_em, 'status', p.status, 'quando', p.quando,
      'combinado_para', p.combinado_para, 'profissao', f.nome, 'regiao', r.nome,
      'cliente', c.nome, 'profissional', pr.nome,
      'preco_informado', p.preco_informado, 'taxa_urgencia', p.taxa_urgencia, 'taxa_fora_horario', p.taxa_fora_horario,
      'valor_cobrado', p.valor_cobrado, 'forma_pagamento', p.forma_pagamento,
      'aceito_em', p.aceito_em, 'concluido_em', p.concluido_em, 'encerrado_em', p.encerrado_em, 'motivo', p.motivo,
      'minutos_trabalhados', p.minutos_trabalhados,
      'nota', (select a.nota from public.avaliacoes a where a.pedido_id = p.id)) x
    from public.pedidos p
      join public.profissoes f on f.id = p.profissao_id
      left join public.regioes r on r.id = p.regiao_id
      left join public.perfis c on c.id = p.cliente_id
      left join public.perfis pr on pr.id = p.profissional_id
    where p.criado_em >= p_inicio::timestamptz and p.criado_em < (p_fim + 1)::timestamptz
    order by p.criado_em desc limit 5000) s), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Cadastros incompletos e lembrete
-- ---------------------------------------------------------------------------
create table if not exists public.cadastro_lembretes (
  id bigint generated always as identity primary key,
  profissional_id uuid not null references public.profissionais (id) on delete cascade,
  admin_id uuid references public.perfis (id) on delete set null,
  pendencias text[] not null default '{}',
  enviado_em timestamptz not null default now()
);
create index if not exists cadastro_lembretes_prof on public.cadastro_lembretes (profissional_id, enviado_em desc);
alter table public.cadastro_lembretes enable row level security;
revoke all on public.cadastro_lembretes from anon, authenticated;

create or replace function public.nome_pendencia(p text)
returns text
language sql immutable
as $$
  select case p
    when 'foto' then 'foto de perfil' when 'nome' then 'nome completo' when 'nascimento' then 'data de nascimento'
    when 'cpf' then 'CPF' when 'telefone' then 'celular' when 'endereco' then 'endereço'
    when 'area_atendimento' then 'área de atendimento' when 'profissao' then 'profissão'
    when 'especialidades_e_precos' then 'especialidades e preços' when 'documento' then 'foto do documento'
    when 'selfie' then 'selfie com o documento' when 'antecedentes' then 'certidão de antecedentes'
    else replace(p, '_', ' ') end
$$;

create or replace function public.admin_cadastros_incompletos(p_texto text default null)
returns jsonb
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.exigir_permissao('cadastros');
  return coalesce((select jsonb_agg(x order by (x ->> 'atualizado_em') desc) from (
    select jsonb_build_object('id', pr.id, 'nome', pe.nome, 'email', pe.email, 'foto_url', pe.foto_url,
      'telefone', case when public.pode('dados_pessoais') then pe.telefone else null end,
      'status', pr.status, 'criado_em', pr.criado_em, 'atualizado_em', greatest(pr.atualizado_em, pe.atualizado_em),
      'pendencias', to_jsonb(coalesce(public.pendencias_profissional(pr.id), '{}')),
      'profissoes', coalesce((select jsonb_agg(f.nome order by pp.principal desc, f.ordem) from public.profissional_profissoes pp
        join public.profissoes f on f.id = pp.profissao_id where pp.profissional_id = pr.id), '[]'::jsonb),
      'lembretes', (select count(*) from public.cadastro_lembretes l where l.profissional_id = pr.id),
      'ultimo_lembrete', (select max(l.enviado_em) from public.cadastro_lembretes l where l.profissional_id = pr.id)) x
    from public.profissionais pr join public.perfis pe on pe.id = pr.id
    where pr.status in ('rascunho', 'recusado') and pe.suspenso_em is null and pe.excluido_em is null
      and (coalesce(btrim(p_texto), '') = '' or pe.nome ilike '%' || btrim(p_texto) || '%' or pe.email ilike '%' || btrim(p_texto) || '%')
    limit 500) s), '[]'::jsonb);
end;
$$;

-- Manda o lembrete (no máximo 1 por pessoa a cada 24 horas). Devolve quantos foram enviados.
create or replace function public.admin_lembrar_cadastro(p_profissionais uuid[])
returns integer
language plpgsql security definer
set search_path = public
as $$
declare
  r record;
  v_pend text[];
  v_falta text;
  n integer := 0;
begin
  perform public.exigir_permissao('cadastros');
  if coalesce(cardinality(p_profissionais), 0) = 0 then return 0; end if;
  if cardinality(p_profissionais) > 500 then perform public.erro('muitos', 'Mande para até 500 pessoas de cada vez.'); end if;
  for r in select pr.id, pr.status, pe.nome from public.profissionais pr join public.perfis pe on pe.id = pr.id
           where pr.id = any (p_profissionais) and pr.status in ('rascunho', 'recusado') and pe.suspenso_em is null and pe.excluido_em is null
             and not exists (select 1 from public.cadastro_lembretes l where l.profissional_id = pr.id and l.enviado_em > now() - interval '24 hours') loop
    v_pend := coalesce(public.pendencias_profissional(r.id), '{}');
    select string_agg(public.nome_pendencia(x), ', ') into v_falta from unnest(v_pend[1:5]) x;
    perform public.notificar(r.id, 'completar_cadastro',
      case when r.status = 'recusado' then 'Falta um ajuste no seu cadastro' else 'Falta pouco para você começar a atender' end,
      coalesce(nullif(split_part(btrim(r.nome), ' ', 1), '') || ', ', '')
        || case when v_falta is not null then 'para concluir o seu cadastro no iService falta: ' || v_falta || '. '
           else 'o seu cadastro no iService ainda não foi enviado para análise. ' end
        || 'Abra o app iService Profissional e termine. Clientes da sua região já estão procurando.');
    insert into public.cadastro_lembretes (profissional_id, admin_id, pendencias) values (r.id, auth.uid(), v_pend);
    perform public.registrar_acao('lembrete_cadastro', r.id::text, jsonb_build_object('pendencias', to_jsonb(v_pend)));
    n := n + 1;
  end loop;
  return n;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Permissões das funções e tarefas automáticas
-- ---------------------------------------------------------------------------
revoke all on function public.nota_permissao(text), public.nome_pendencia(text) from public, anon;
grant execute on function public.nota_permissao(text), public.nome_pendencia(text) to authenticated;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.admin_notas(text, uuid)', 'public.admin_anotar(text, uuid, text)', 'public.admin_fixar_nota(bigint, boolean)',
    'public.admin_apagar_nota(bigint)', 'public.admin_advertir(uuid, text)', 'public.admin_suspender_por(uuid, integer, text)',
    'public.admin_definir_validade(text, bigint, date)', 'public.admin_validades(integer, uuid)',
    'public.admin_respostas_prontas()', 'public.admin_salvar_resposta(bigint, text, text)', 'public.admin_apagar_resposta(bigint)',
    'public.admin_usar_resposta(bigint)', 'public.admin_atencao()', 'public.admin_atencao_contagem()',
    'public.admin_atencao_tratado(text, text)', 'public.admin_gestao_pessoa(uuid)', 'public.admin_relatorio(date, date)',
    'public.admin_planilha_pedidos(date, date)', 'public.admin_cadastros_incompletos(text)', 'public.admin_lembrar_cadastro(uuid[])'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end;
$$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname in ('iservice-fim-suspensao', 'iservice-avisar-validades');
    perform cron.schedule('iservice-fim-suspensao', '*/10 * * * *', 'select public.reativar_suspensoes_vencidas()');
    -- 12h UTC = 9h em Brasília.
    perform cron.schedule('iservice-avisar-validades', '0 12 * * *', 'select public.avisar_validades()');
  end if;
end;
$$;
