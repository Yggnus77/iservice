-- iService: estrutura principal do banco.
-- Um único backend serve o app Cliente, o app Profissional e o painel admin.

create extension if not exists postgis with schema extensions;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists unaccent with schema extensions;

-- ---------------------------------------------------------------------------
-- Tipos
-- ---------------------------------------------------------------------------
create type public.status_cadastro as enum ('rascunho', 'em_analise', 'aprovado', 'recusado', 'suspenso');
create type public.plano_profissional as enum ('gratis', 'vip', 'premium');
create type public.quando_pedido as enum ('agora', 'hoje', 'combinado');
create type public.status_pedido as enum (
  'solicitado',     -- enviado só ao profissional escolhido, aguardando até 10 min
  'aceito',         -- profissional aceitou
  'a_caminho',      -- profissional saiu para o local
  'em_atendimento', -- profissional no local, trabalhando
  'concluido',
  'recusado',       -- profissional recusou: o pedido encerra e não vai a mais ninguém
  'expirado',       -- passou o prazo sem resposta: idem
  'cancelado'
);
create type public.status_documento as enum ('pendente', 'aprovado', 'recusado');
create type public.tipo_documento as enum ('documento_frente', 'documento_verso', 'selfie_documento', 'antecedentes', 'comprovante_endereco');
create type public.status_reclamacao as enum ('aberta', 'em_mediacao', 'resolvida', 'encerrada');

-- ---------------------------------------------------------------------------
-- Configuração geral (lida pelos apps e pelas funções)
-- ---------------------------------------------------------------------------
create table public.app_config (
  chave text primary key,
  valor jsonb not null,
  descricao text,
  atualizado_em timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Catálogo: regiões, profissões e especialidades
-- ---------------------------------------------------------------------------
-- Regiões administrativas do DF e cidades do Entorno. A faixa (1 a 5) agrupa
-- regiões de custo parecido para o preço de referência (1 = Plano Piloto e Lagos).
create table public.regioes (
  id text primary key,
  nome text not null,
  uf char(2) not null default 'DF',
  faixa_preco smallint not null check (faixa_preco between 1 and 5),
  centro extensions.geography(point, 4326),
  ordem smallint not null default 0
);

create table public.profissoes (
  id text primary key,                 -- ex.: 'eletricista'
  nome text not null,
  icone text not null,                 -- nome do Material Symbol
  cor_inicio text not null,
  cor_fim text not null,
  preco_base numeric(10, 2) not null,  -- base para a referência enquanto há poucos dados
  exige_antecedentes boolean not null default false,
  palavras_chave text[] not null default '{}',
  ativa boolean not null default true,
  ordem smallint not null default 0
);

create table public.especialidades (
  id bigint generated always as identity primary key,
  profissao_id text not null references public.profissoes (id),
  nome text not null,
  sugerida boolean not null default true,  -- false = criada por um profissional
  aprovada boolean not null default true,
  criada_por uuid,
  ordem smallint not null default 0,
  unique (profissao_id, nome)
);

create table public.certificacoes_sugeridas (
  id bigint generated always as identity primary key,
  profissao_id text not null references public.profissoes (id),
  nome text not null,
  obrigatoria boolean not null default false,
  unique (profissao_id, nome)
);

-- ---------------------------------------------------------------------------
-- Pessoas
-- ---------------------------------------------------------------------------
-- Dados comuns de qualquer usuário (cliente, profissional ou os dois).
create table public.perfis (
  id uuid primary key references auth.users (id) on delete cascade,
  nome text not null default '',
  nascimento date,
  cpf text unique check (cpf is null or cpf ~ '^\d{11}$'),
  telefone text check (telefone is null or telefone ~ '^\d{10,13}$'),
  email text,
  foto_url text,
  telefone_verificado boolean not null default false,
  letra_grande boolean not null default false,
  e_cliente boolean not null default false,
  e_profissional boolean not null default false,
  e_admin boolean not null default false,
  codigo_indicacao text unique,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create table public.enderecos (
  id bigint generated always as identity primary key,
  usuario_id uuid not null references public.perfis (id) on delete cascade,
  rotulo text not null default 'Casa',
  regiao_id text references public.regioes (id),
  logradouro text not null,          -- ex.: 'SQS 308' ou 'Rua 10, Qd 5'
  bloco text,
  numero text,
  complemento text,
  referencia text,
  cep text check (cep is null or cep ~ '^\d{8}$'),
  cidade text not null default 'Brasília',
  uf char(2) not null default 'DF',
  localizacao extensions.geography(point, 4326) not null,
  principal boolean not null default false,
  criado_em timestamptz not null default now()
);
create index enderecos_usuario_idx on public.enderecos (usuario_id);
create unique index enderecos_um_principal on public.enderecos (usuario_id) where principal;

create table public.profissionais (
  id uuid primary key references public.perfis (id) on delete cascade,
  status public.status_cadastro not null default 'rascunho',
  motivo_status text,
  verificado boolean not null default false,       -- documento + selfie conferidos
  disponivel boolean not null default false,       -- "modo disponível"
  bio text,
  anos_experiencia smallint check (anos_experiencia between 0 and 70),
  -- Área de atendimento: centro + raio escolhido pelo profissional.
  area_centro extensions.geography(point, 4326),
  area_raio_km numeric(5, 1) not null default 15 check (area_raio_km between 1 and 50),
  regiao_id text references public.regioes (id),
  -- Plano: só define o alcance. Desligado enquanto o app for grátis.
  plano public.plano_profissional not null default 'gratis',
  plano_valido_ate timestamptz,
  -- Indicadores de qualidade (mantidos por gatilhos)
  nota_media numeric(3, 2) not null default 0,
  total_avaliacoes integer not null default 0,
  servicos_concluidos integer not null default 0,
  pedidos_recebidos integer not null default 0,
  pedidos_aceitos integer not null default 0,
  pedidos_perdidos integer not null default 0,     -- recusados + expirados
  cancelados_pelo_profissional integer not null default 0,
  aprovado_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index profissionais_area_idx on public.profissionais using gist (area_centro);
create index profissionais_status_idx on public.profissionais (status, disponivel);

create table public.profissional_profissoes (
  profissional_id uuid not null references public.profissionais (id) on delete cascade,
  profissao_id text not null references public.profissoes (id),
  principal boolean not null default false,
  primary key (profissional_id, profissao_id)
);
create index profissional_profissoes_prof_idx on public.profissional_profissoes (profissao_id);

-- Especialidade marcada pelo profissional, com o preço que ele define.
create table public.profissional_especialidades (
  profissional_id uuid not null references public.profissionais (id) on delete cascade,
  especialidade_id bigint not null references public.especialidades (id),
  preco numeric(10, 2) check (preco is null or preco > 0),
  primary key (profissional_id, especialidade_id)
);

create table public.certificacoes (
  id bigint generated always as identity primary key,
  profissional_id uuid not null references public.profissionais (id) on delete cascade,
  profissao_id text references public.profissoes (id),
  nome text not null,
  instituicao text,
  arquivo_path text,
  status public.status_documento not null default 'pendente',
  criado_em timestamptz not null default now()
);

create table public.documentos (
  id bigint generated always as identity primary key,
  profissional_id uuid not null references public.profissionais (id) on delete cascade,
  tipo public.tipo_documento not null,
  arquivo_path text not null,
  status public.status_documento not null default 'pendente',
  observacao text,
  criado_em timestamptz not null default now(),
  revisado_em timestamptz,
  revisado_por uuid references public.perfis (id)
);

create table public.portfolio (
  id bigint generated always as identity primary key,
  profissional_id uuid not null references public.profissionais (id) on delete cascade,
  profissao_id text references public.profissoes (id),
  descricao text,
  antes_path text,
  depois_path text not null,
  ordem smallint not null default 0,
  criado_em timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Pedidos (sempre direcionados a um único profissional)
-- ---------------------------------------------------------------------------
create table public.pedidos (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique default upper(substr(md5(gen_random_uuid()::text), 1, 6)),
  cliente_id uuid not null references public.perfis (id),
  profissional_id uuid not null references public.profissionais (id),
  profissao_id text not null references public.profissoes (id),
  especialidade_id bigint references public.especialidades (id),
  descricao text not null default '',
  fotos text[] not null default '{}',
  -- Quando: agora (com taxa de urgência), hoje (numa janela) ou horário combinado
  -- direto com aquele profissional (até 7 dias à frente).
  quando public.quando_pedido not null,
  janela text,
  combinado_para timestamptz,
  -- Local do serviço (cópia do endereço no momento do pedido)
  endereco_id bigint references public.enderecos (id) on delete set null,
  endereco_texto text not null,
  regiao_id text references public.regioes (id),
  localizacao extensions.geography(point, 4326) not null,
  distancia_km numeric(6, 2),
  -- Valores (o profissional sempre define o preço; pagamento direto no lançamento)
  preco_informado numeric(10, 2),
  taxa_urgencia numeric(10, 2) not null default 0,
  valor_cobrado numeric(10, 2),
  forma_pagamento text,
  status public.status_pedido not null default 'solicitado',
  responder_ate timestamptz not null,
  motivo text,                              -- motivo de recusa ou cancelamento
  cancelado_por uuid references public.perfis (id),
  criado_em timestamptz not null default now(),
  aceito_em timestamptz,
  a_caminho_em timestamptz,
  iniciado_em timestamptz,
  concluido_em timestamptz,
  encerrado_em timestamptz,                 -- recusado, expirado ou cancelado
  constraint pedido_quando_valido check (
    (quando = 'agora' and combinado_para is null)
    or (quando = 'hoje' and combinado_para is null and janela is not null)
    or (quando = 'combinado' and combinado_para is not null)
  )
);
create index pedidos_cliente_idx on public.pedidos (cliente_id, criado_em desc);
create index pedidos_profissional_idx on public.pedidos (profissional_id, criado_em desc);
create index pedidos_status_idx on public.pedidos (status, responder_ate);

create table public.mensagens (
  id bigint generated always as identity primary key,
  pedido_id uuid not null references public.pedidos (id) on delete cascade,
  autor_id uuid not null references public.perfis (id),
  texto text not null check (length(texto) between 1 and 2000),
  criada_em timestamptz not null default now(),
  lida_em timestamptz
);
create index mensagens_pedido_idx on public.mensagens (pedido_id, criada_em);

create table public.avaliacoes (
  pedido_id uuid primary key references public.pedidos (id) on delete cascade,
  cliente_id uuid not null references public.perfis (id),
  profissional_id uuid not null references public.profissionais (id),
  nota smallint not null check (nota between 1 and 5),
  comentario text,
  fotos text[] not null default '{}',
  resposta text,                            -- resposta pública do profissional
  criada_em timestamptz not null default now()
);
create index avaliacoes_profissional_idx on public.avaliacoes (profissional_id, criada_em desc);

create table public.favoritos (
  cliente_id uuid not null references public.perfis (id) on delete cascade,
  profissional_id uuid not null references public.profissionais (id) on delete cascade,
  criado_em timestamptz not null default now(),
  primary key (cliente_id, profissional_id)
);

create table public.notificacoes (
  id bigint generated always as identity primary key,
  usuario_id uuid not null references public.perfis (id) on delete cascade,
  tipo text not null,
  titulo text not null,
  corpo text not null default '',
  dados jsonb not null default '{}',
  lida boolean not null default false,
  criada_em timestamptz not null default now()
);
create index notificacoes_usuario_idx on public.notificacoes (usuario_id, criada_em desc);

create table public.dispositivos (
  token text primary key,
  usuario_id uuid not null references public.perfis (id) on delete cascade,
  app text not null check (app in ('cliente', 'profissional')),
  plataforma text not null check (plataforma in ('android', 'ios', 'web')),
  atualizado_em timestamptz not null default now()
);

-- Garantia iService: reclamação com mediação
create table public.reclamacoes (
  id bigint generated always as identity primary key,
  pedido_id uuid not null references public.pedidos (id),
  autor_id uuid not null references public.perfis (id),
  motivo text not null,
  descricao text not null,
  fotos text[] not null default '{}',
  status public.status_reclamacao not null default 'aberta',
  resolucao text,
  criada_em timestamptz not null default now(),
  atualizada_em timestamptz not null default now()
);

-- Segurança: acionamento do botão de emergência e acompanhamento compartilhado
create table public.emergencias (
  id bigint generated always as identity primary key,
  pedido_id uuid references public.pedidos (id),
  usuario_id uuid not null references public.perfis (id),
  localizacao extensions.geography(point, 4326),
  criada_em timestamptz not null default now(),
  atendida_em timestamptz
);

create table public.compartilhamentos (
  token text primary key default encode(extensions.gen_random_bytes(16), 'hex'),
  pedido_id uuid not null references public.pedidos (id) on delete cascade,
  criado_por uuid not null references public.perfis (id),
  expira_em timestamptz not null default now() + interval '12 hours',
  criado_em timestamptz not null default now()
);

-- Fidelidade: pontos e indicações (cupons ficam no admin)
create table public.pontos (
  id bigint generated always as identity primary key,
  usuario_id uuid not null references public.perfis (id) on delete cascade,
  pontos integer not null,
  motivo text not null,
  pedido_id uuid references public.pedidos (id),
  criado_em timestamptz not null default now()
);

create table public.indicacoes (
  indicado_id uuid primary key references public.perfis (id) on delete cascade,
  indicador_id uuid not null references public.perfis (id) on delete cascade,
  recompensado boolean not null default false,
  criada_em timestamptz not null default now()
);
