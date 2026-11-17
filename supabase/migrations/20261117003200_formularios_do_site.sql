-- Formulários do site (17/11/2026)
-- 1) "Não achou sua profissão? Sugira": o visitante sugere uma profissão nova. O painel
--    (Crescimento > Sugestões de profissões) mostra as mais pedidas no topo.
-- 2) "Fazer uma reclamação": a reclamação entra na caixa de suporte do painel (aba E-mails)
--    como uma conversa nova, vai para a próxima pessoa do rodízio e é respondida por e-mail,
--    igual a um e-mail que chega em suporte@iservice.app.br.
--
-- Proteção contra abuso: o site só chama as duas funções abaixo (ninguém lê nem grava direto
-- nas tabelas), tudo tem limite de tamanho, cada aparelho e cada conexão têm limite por dia,
-- e há um teto diário geral. O endereço da conexão não é guardado: só um resumo embaralhado
-- (hash com segredo) que muda todo dia e serve apenas para contar os envios.

-- ---------------------------------------------------------------------------
-- 1. Segredo do resumo da conexão (fica só no banco)
-- ---------------------------------------------------------------------------
create table if not exists public.site_segredo (
  id boolean primary key default true check (id),
  sal text not null default encode(extensions.gen_random_bytes(32), 'hex')
);
insert into public.site_segredo (id) values (true) on conflict do nothing;
alter table public.site_segredo enable row level security;
revoke all on public.site_segredo from anon, authenticated;

-- Resumo da conexão de quem chamou, trocado todo dia. Nulo se não der para saber.
create or replace function public.site_conexao()
returns text
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_h jsonb;
  v_ip text;
begin
  begin
    v_h := nullif(current_setting('request.headers', true), '')::jsonb;
  exception when others then
    v_h := null;
  end;
  v_ip := nullif(btrim(coalesce(v_h->>'cf-connecting-ip', split_part(coalesce(v_h->>'x-forwarded-for', ''), ',', 1), v_h->>'x-real-ip', '')), '');
  if v_ip is null then return null; end if;
  return encode(extensions.digest(v_ip || '|' || ((now() at time zone 'America/Sao_Paulo')::date)::text || '|'
    || (select sal from public.site_segredo), 'sha256'), 'hex');
end;
$$;
revoke all on function public.site_conexao() from public, anon, authenticated;

-- Texto de uma linha, sem espaços repetidos nem caracteres de controle.
create or replace function public.site_limpar(p text, p_max integer)
returns text
language sql immutable
as $$ select nullif(left(btrim(regexp_replace(regexp_replace(coalesce(p, ''), '[[:cntrl:]]', ' ', 'g'), '\s+', ' ', 'g')), p_max), '') $$;

-- Chave para juntar "Costureira", "costureira " e "Costureíra" na mesma linha.
create or replace function public.site_chave_profissao(p text)
returns text
language sql stable
set search_path = public
as $$ select lower(extensions.unaccent(public.site_limpar(p, 60))) $$;

revoke all on function public.site_limpar(text, integer), public.site_chave_profissao(text) from public, anon;
grant execute on function public.site_limpar(text, integer), public.site_chave_profissao(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Sugestões de profissão
-- ---------------------------------------------------------------------------
create table if not exists public.sugestoes_profissao (
  id bigint generated always as identity primary key,
  criada_em timestamptz not null default now(),
  dia date not null default (now() at time zone 'America/Sao_Paulo')::date,
  profissao text not null check (char_length(profissao) between 2 and 60),
  chave text not null check (char_length(chave) between 2 and 60),
  perfil text not null check (perfil in ('cliente', 'profissional')),
  regiao_id text references public.regioes (id) on delete set null,
  outra_cidade boolean not null default false,
  contato text check (char_length(contato) <= 120),
  visitante text check (visitante ~ '^[a-z0-9]{8,40}$'),
  conexao text
);
create index if not exists sugestoes_profissao_chave on public.sugestoes_profissao (chave);
create index if not exists sugestoes_profissao_dia on public.sugestoes_profissao (dia);
alter table public.sugestoes_profissao enable row level security;
revoke all on public.sugestoes_profissao from anon, authenticated;

-- p_regiao: id de public.regioes ou 'outra'. p_armadilha: campo escondido do formulário;
-- gente de verdade deixa vazio, robô costuma preencher.
create or replace function public.site_sugerir_profissao(
  p_profissao text, p_perfil text, p_regiao text default null, p_contato text default null,
  p_visitante text default null, p_armadilha text default null)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_dia date := (now() at time zone 'America/Sao_Paulo')::date;
  v_prof text := public.site_limpar(p_profissao, 60);
  v_chave text;
  v_contato text := public.site_limpar(p_contato, 120);
  v_visitante text := case when p_visitante ~ '^[a-z0-9]{8,40}$' then p_visitante end;
  v_conexao text := public.site_conexao();
  v_regiao text;
  v_existe boolean;
begin
  -- Robô: finge que deu certo e não guarda nada.
  if nullif(btrim(coalesce(p_armadilha, '')), '') is not null then return jsonb_build_object('ok', true); end if;

  if v_prof is null or char_length(v_prof) < 2 then
    perform public.erro('sugestao_invalida', 'Escreva o nome da profissão.');
  end if;
  if v_prof !~ '[[:alpha:]]' or v_prof ~* '(https?:|www\.|\.(com|br|net|org)\b|[<>{}\[\]@#$%*=_|\\~`^])' then
    perform public.erro('sugestao_invalida', 'Escreva só o nome da profissão, sem links ou símbolos.');
  end if;
  if p_perfil not in ('cliente', 'profissional') then
    perform public.erro('sugestao_invalida', 'Diga se você é cliente ou profissional.');
  end if;
  if v_contato ~* '(https?:|www\.|<)' then
    perform public.erro('sugestao_invalida', 'Deixe no contato só um telefone ou e-mail.');
  end if;
  if p_regiao is not null and p_regiao <> 'outra' then
    select id into v_regiao from public.regioes where id = p_regiao;
  end if;

  -- Limites por dia: 5 por aparelho, 8 por conexão, 600 no total.
  if (v_visitante is not null and (select count(*) from public.sugestoes_profissao where dia = v_dia and visitante = v_visitante) >= 5)
     or (v_conexao is not null and (select count(*) from public.sugestoes_profissao where dia = v_dia and conexao = v_conexao) >= 8)
     or (select count(*) from public.sugestoes_profissao where dia = v_dia) >= 600 then
    perform public.erro('limite', 'Recebemos muitas sugestões suas hoje. Obrigado! Tente de novo amanhã.');
  end if;

  v_chave := public.site_chave_profissao(v_prof);
  -- A mesma pessoa repetindo a mesma profissão no mesmo dia conta uma vez só.
  if not exists (select 1 from public.sugestoes_profissao
                 where dia = v_dia and chave = v_chave
                   and case when v_visitante is not null then visitante = v_visitante
                            else v_conexao is not null and conexao = v_conexao end) then
    insert into public.sugestoes_profissao (dia, profissao, chave, perfil, regiao_id, outra_cidade, contato, visitante, conexao)
    values (v_dia, v_prof, v_chave, p_perfil, v_regiao, coalesce(p_regiao = 'outra', false), v_contato, v_visitante, v_conexao);
  end if;

  select exists (select 1 from public.profissoes where public.site_chave_profissao(nome) = v_chave) into v_existe;
  return jsonb_build_object('ok', true, 'ja_existe', v_existe);
end;
$$;
revoke all on function public.site_sugerir_profissao(text, text, text, text, text, text) from public;
grant execute on function public.site_sugerir_profissao(text, text, text, text, text, text) to anon, authenticated;

-- Painel: ranking das profissões mais pedidas e as últimas sugestões.
-- O contato só aparece inteiro para quem vê dados pessoais (Dono, Gerente e Responsável).
create or replace function public.admin_sugestoes_profissao(p_dias integer default 90)
returns jsonb
language plpgsql stable security definer
set search_path = public
set timezone = 'America/Sao_Paulo'
as $$
declare
  v_ini date := case when p_dias is null or p_dias <= 0 then date '2000-01-01'
                     else current_date - (least(p_dias, 3650) - 1) end;
  v_dados boolean := public.pode('dados_pessoais');
begin
  perform public.exigir_permissao('crescimento');
  return jsonb_build_object(
    'inicio', v_ini,
    'total', (select count(*) from public.sugestoes_profissao where dia >= v_ini),
    'clientes', (select count(*) from public.sugestoes_profissao where dia >= v_ini and perfil = 'cliente'),
    'profissionais', (select count(*) from public.sugestoes_profissao where dia >= v_ini and perfil = 'profissional'),
    'diferentes', (select count(distinct chave) from public.sugestoes_profissao where dia >= v_ini),
    'ranking', coalesce((
      select jsonb_agg(r order by (r->>'total')::int desc, r->>'nome') from (
        select jsonb_build_object(
          'chave', s.chave,
          'nome', (select x.profissao from public.sugestoes_profissao x where x.chave = s.chave and x.dia >= v_ini
                   group by x.profissao order by count(*) desc, max(x.criada_em) desc limit 1),
          'total', count(*),
          'clientes', count(*) filter (where s.perfil = 'cliente'),
          'profissionais', count(*) filter (where s.perfil = 'profissional'),
          'ultima', max(s.criada_em),
          'ja_existe', exists (select 1 from public.profissoes p where public.site_chave_profissao(p.nome) = s.chave),
          'regioes', coalesce((
            select jsonb_agg(jsonb_build_object('nome', g.nome, 'total', g.n) order by g.n desc, g.nome) from (
              select coalesce(rg.nome, case when y.outra_cidade then 'Outra cidade' else 'Não informou' end) nome, count(*) n
              from public.sugestoes_profissao y left join public.regioes rg on rg.id = y.regiao_id
              where y.chave = s.chave and y.dia >= v_ini group by 1 order by 2 desc limit 3) g), '[]')
        ) r
        from public.sugestoes_profissao s where s.dia >= v_ini
        group by s.chave order by count(*) desc limit 100) t), '[]'),
    'recentes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id, 'criada_em', s.criada_em, 'profissao', s.profissao, 'perfil', s.perfil,
        'cidade', coalesce(rg.nome, case when s.outra_cidade then 'Outra cidade' end),
        'contato', case when s.contato is null then null when v_dados then s.contato
                        else left(s.contato, 2) || '•••' || right(s.contato, 2) end) order by s.criada_em desc)
      from (select * from public.sugestoes_profissao where dia >= v_ini order by criada_em desc limit 60) s
      left join public.regioes rg on rg.id = s.regiao_id), '[]'),
    'contato_mascarado', not v_dados,
    'pode_apagar', public.pode('catalogo')
  );
end;
$$;

-- Apagar uma sugestão (spam, brincadeira). Só quem cuida do catálogo (Dono e Gerente geral).
create or replace function public.admin_apagar_sugestao(p_id bigint)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v public.sugestoes_profissao;
begin
  perform public.exigir_permissao('catalogo');
  delete from public.sugestoes_profissao where id = p_id returning * into v;
  if v.id is null then perform public.erro('nao_encontrado', 'Sugestão não encontrada.'); end if;
  perform public.registrar_acao('apagar_sugestao_profissao', v.profissao, jsonb_build_object('id', v.id, 'perfil', v.perfil));
end;
$$;

revoke all on function public.admin_sugestoes_profissao(integer), public.admin_apagar_sugestao(bigint) from public, anon;
grant execute on function public.admin_sugestoes_profissao(integer), public.admin_apagar_sugestao(bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Reclamações pelo site -> caixa de suporte
-- ---------------------------------------------------------------------------
-- Registro de cada envio, para os limites e para saber qual conversa veio do site.
create table if not exists public.site_reclamacoes (
  id bigint generated always as identity primary key,
  criada_em timestamptz not null default now(),
  dia date not null default (now() at time zone 'America/Sao_Paulo')::date,
  conversa_id bigint references public.suporte_conversas (id) on delete set null,
  email text not null,
  motivo text not null,
  visitante text,
  conexao text
);
create index if not exists site_reclamacoes_dia on public.site_reclamacoes (dia);
alter table public.site_reclamacoes enable row level security;
revoke all on public.site_reclamacoes from anon, authenticated;

create or replace function public.site_motivo_reclamacao(p text)
returns text
language sql immutable
as $$
  select case p
    when 'profissional' then 'Atendimento de um profissional'
    when 'cliente' then 'Comportamento de um cliente'
    when 'cobranca' then 'Cobrança ou valor do serviço'
    when 'app' then 'Problema na plataforma'
    when 'conta' then 'Conta e cadastro'
    when 'seguranca' then 'Segurança'
    when 'outro' then 'Outro assunto'
  end
$$;

create or replace function public.site_enviar_reclamacao(
  p_nome text, p_email text, p_motivo text, p_texto text,
  p_perfil text default null, p_telefone text default null, p_pedido text default null,
  p_visitante text default null, p_armadilha text default null)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_dia date := (now() at time zone 'America/Sao_Paulo')::date;
  v_nome text := public.site_limpar(p_nome, 80);
  v_email text := lower(public.site_limpar(p_email, 120));
  v_motivo text := public.site_motivo_reclamacao(p_motivo);
  v_tel text := public.site_limpar(p_telefone, 30);
  v_pedido text := public.site_limpar(p_pedido, 40);
  v_texto text := nullif(btrim(regexp_replace(coalesce(p_texto, ''), '[\x01-\x08\x0B\x0C\x0E-\x1F\x7F]', '', 'g')), '');
  v_visitante text := case when p_visitante ~ '^[a-z0-9]{8,40}$' then p_visitante end;
  v_conexao text := public.site_conexao();
  v_perfil text := case p_perfil when 'cliente' then 'Cliente' when 'profissional' then 'Profissional' else 'Não informou' end;
  v_res jsonb;
  v_conversa bigint;
begin
  if nullif(btrim(coalesce(p_armadilha, '')), '') is not null then
    return jsonb_build_object('ok', true, 'protocolo', null);
  end if;

  if v_nome is null or char_length(v_nome) < 2 then perform public.erro('reclamacao_invalida', 'Escreva o seu nome.'); end if;
  if v_email is null or v_email !~ '^[^@\s<>()",;]+@[^@\s<>()",;]+\.[a-z]{2,}$' then
    perform public.erro('reclamacao_invalida', 'Confira o seu e-mail. É por ele que vamos responder.');
  end if;
  if v_email like '%@iservice.app.br' then perform public.erro('reclamacao_invalida', 'Use o seu e-mail pessoal.'); end if;
  if v_motivo is null then perform public.erro('reclamacao_invalida', 'Escolha o motivo da reclamação.'); end if;
  if v_texto is null or char_length(v_texto) < 20 then
    perform public.erro('reclamacao_invalida', 'Conte um pouco mais o que aconteceu (pelo menos 20 letras).');
  end if;
  if char_length(v_texto) > 4000 then perform public.erro('reclamacao_invalida', 'O texto passou de 4.000 caracteres. Resuma um pouco.'); end if;

  -- Limites por dia: 3 por e-mail, 3 por aparelho, 5 por conexão, 150 no total.
  if (select count(*) from public.site_reclamacoes where dia = v_dia and email = v_email) >= 3
     or (v_visitante is not null and (select count(*) from public.site_reclamacoes where dia = v_dia and visitante = v_visitante) >= 3)
     or (v_conexao is not null and (select count(*) from public.site_reclamacoes where dia = v_dia and conexao = v_conexao) >= 5)
     or (select count(*) from public.site_reclamacoes where dia = v_dia) >= 150 then
    perform public.erro('limite', 'Você já mandou várias reclamações hoje. Nossa equipe vai responder por e-mail. Se precisar, escreva para suporte@iservice.app.br.');
  end if;

  v_res := public.suporte_receber(jsonb_build_object(
    'id_externo', 'site-' || gen_random_uuid(),
    'de_email', v_email,
    'de_nome', v_nome,
    'para', jsonb_build_array('suporte@iservice.app.br'),
    'assunto', 'Reclamação pelo site: ' || v_motivo,
    'texto', 'Reclamação enviada pelo formulário do site. O e-mail não foi confirmado: confira antes de passar dados da conta.' || E'\n\n'
      || 'Nome: ' || v_nome || E'\n'
      || 'Sou: ' || v_perfil || E'\n'
      || 'E-mail: ' || v_email || E'\n'
      || 'Telefone: ' || coalesce(v_tel, 'não informou') || E'\n'
      || 'Pedido: ' || coalesce(v_pedido, 'não informou') || E'\n'
      || 'Motivo: ' || v_motivo || E'\n\n'
      || v_texto
  ));
  v_conversa := (v_res->>'conversa_id')::bigint;
  if v_conversa is null then perform public.erro('reclamacao_invalida', 'Não foi possível registrar. Confira o seu e-mail.'); end if;

  insert into public.site_reclamacoes (dia, conversa_id, email, motivo, visitante, conexao)
  values (v_dia, v_conversa, v_email, p_motivo, v_visitante, v_conexao);

  return jsonb_build_object('ok', true, 'protocolo', public.suporte_protocolo(v_conversa));
end;
$$;

revoke all on function public.site_motivo_reclamacao(text) from public, anon;
revoke all on function public.site_enviar_reclamacao(text, text, text, text, text, text, text, text, text) from public;
grant execute on function public.site_enviar_reclamacao(text, text, text, text, text, text, text, text, text) to anon, authenticated;
