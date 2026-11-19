-- Nada de contato por fora da plataforma (pedido do usuário em 19/11/2026).
-- Todo texto que uma pessoa escreve e outra lê passa por ocultar_contatos():
-- telefones, e-mails, links, @ de redes sociais e palavras como Pix e WhatsApp
-- viram "[contato oculto]". Vale sempre, com ou sem o pagamento pelo app.
-- Textos protegidos: chat, descrição e motivo do pedido, bio e portfólio do profissional,
-- avaliações (comentário e resposta), avaliação do cliente, certificações, especialidades
-- próprias, nome da pessoa e complemento/referência do endereço (vão no pedido).

create or replace function public.ocultar_contatos(p_texto text)
returns text
language plpgsql immutable
set search_path = public
as $$
declare
  v text := p_texto;
  m constant text := '[contato oculto]';
begin
  if v is null or v = '' then return v; end if;
  -- e-mails
  v := regexp_replace(v, '[A-Za-z0-9._%+-]+\s*(@|\(at\)|\[at\])\s*[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+', m, 'gi');
  -- links e sites
  v := regexp_replace(v, '(https?://|www\.)\S+', m, 'gi');
  v := regexp_replace(v, '\m[A-Za-z0-9-]+\.(com|net|org|me|app|io|ly|link|bio|site|online|br)(\.br)?(/\S*)?\M', m, 'gi');
  -- @ de redes sociais
  v := regexp_replace(v, '(^|\s)@[A-Za-z0-9._]{3,}', '\1' || m, 'g');
  -- telefones, CPF e chaves numéricas (9 dígitos ou mais, mesmo com espaços, pontos ou traços no meio)
  v := regexp_replace(v, '\+?\d([\s().-]*\d){8,}', m, 'g');
  -- palavras que puxam o contato para fora
  v := regexp_replace(v, '\m(pix|whats\s*app|whats|zap\s*zap|zap|wpp|wa\.me|telegram|instagram|insta|facebook|messenger|signal)\M', m, 'gi');
  return v;
end;
$$;

-- Um gatilho por tabela, com os campos de texto livre de cada uma.
create or replace function public.sem_contatos_mensagem() returns trigger language plpgsql security definer set search_path = public as $$
begin new.texto := public.ocultar_contatos(new.texto); return new; end $$;
create or replace function public.sem_contatos_pedido() returns trigger language plpgsql security definer set search_path = public as $$
begin new.descricao := public.ocultar_contatos(new.descricao); new.motivo := public.ocultar_contatos(new.motivo);
  new.endereco_texto := public.ocultar_contatos(new.endereco_texto); return new; end $$;
create or replace function public.sem_contatos_profissional() returns trigger language plpgsql security definer set search_path = public as $$
begin new.bio := public.ocultar_contatos(new.bio); return new; end $$;
create or replace function public.sem_contatos_portfolio() returns trigger language plpgsql security definer set search_path = public as $$
begin new.descricao := public.ocultar_contatos(new.descricao); return new; end $$;
create or replace function public.sem_contatos_avaliacao() returns trigger language plpgsql security definer set search_path = public as $$
begin new.comentario := public.ocultar_contatos(new.comentario); new.resposta := public.ocultar_contatos(new.resposta); return new; end $$;
create or replace function public.sem_contatos_avaliacao_cliente() returns trigger language plpgsql security definer set search_path = public as $$
begin new.comentario := public.ocultar_contatos(new.comentario); return new; end $$;
create or replace function public.sem_contatos_certificacao() returns trigger language plpgsql security definer set search_path = public as $$
begin new.nome := public.ocultar_contatos(new.nome); new.instituicao := public.ocultar_contatos(new.instituicao); return new; end $$;
create or replace function public.sem_contatos_especialidade() returns trigger language plpgsql security definer set search_path = public as $$
begin new.nome := public.ocultar_contatos(new.nome); return new; end $$;
create or replace function public.sem_contatos_perfil() returns trigger language plpgsql security definer set search_path = public as $$
begin new.nome := public.ocultar_contatos(new.nome); return new; end $$;
create or replace function public.sem_contatos_endereco() returns trigger language plpgsql security definer set search_path = public as $$
begin new.complemento := public.ocultar_contatos(new.complemento); new.referencia := public.ocultar_contatos(new.referencia); return new; end $$;

do $$
declare
  r record;
begin
  for r in select * from (values
    ('mensagens', 'sem_contatos_mensagem', 'texto'),
    ('pedidos', 'sem_contatos_pedido', 'descricao, motivo, endereco_texto'),
    ('profissionais', 'sem_contatos_profissional', 'bio'),
    ('portfolio', 'sem_contatos_portfolio', 'descricao'),
    ('avaliacoes', 'sem_contatos_avaliacao', 'comentario, resposta'),
    ('avaliacoes_cliente', 'sem_contatos_avaliacao_cliente', 'comentario'),
    ('certificacoes', 'sem_contatos_certificacao', 'nome, instituicao'),
    ('especialidades', 'sem_contatos_especialidade', 'nome'),
    ('perfis', 'sem_contatos_perfil', 'nome'),
    ('enderecos', 'sem_contatos_endereco', 'complemento, referencia')
  ) as t(tabela, funcao, colunas) loop
    if to_regclass('public.' || r.tabela) is null then continue; end if;
    execute format('revoke all on function public.%I() from public, anon, authenticated', r.funcao);
    execute format('drop trigger if exists %I on public.%I', r.funcao, r.tabela);
    execute format('create trigger %I before insert or update of %s on public.%I for each row execute function public.%I()',
      r.funcao, r.colunas, r.tabela, r.funcao);
  end loop;
end;
$$;

-- Limpa o que já está gravado (o banco tem poucos dados reais em 19/11/2026).
update public.mensagens set texto = public.ocultar_contatos(texto) where texto is distinct from public.ocultar_contatos(texto);
update public.profissionais set bio = public.ocultar_contatos(bio) where bio is distinct from public.ocultar_contatos(bio);
update public.avaliacoes set comentario = public.ocultar_contatos(comentario), resposta = public.ocultar_contatos(resposta)
where comentario is distinct from public.ocultar_contatos(comentario) or resposta is distinct from public.ocultar_contatos(resposta);
update public.portfolio set descricao = public.ocultar_contatos(descricao) where descricao is distinct from public.ocultar_contatos(descricao);

-- O painel continua sinalizando a avaliação que tentou passar contato (agora escondido).
do $$
declare
  v_def text;
  v_novo text;
begin
  if to_regprocedure('public.admin_avaliacoes_suspeitas(integer, boolean)') is null then return; end if;
  v_def := pg_get_functiondef('public.admin_avaliacoes_suspeitas(integer, boolean)'::regprocedure);
  v_novo := replace(v_def, $r$'(whats|zap|wpp|insta|$r$, $r$'(\[contato oculto\]|whats|zap|wpp|insta|$r$);
  if v_novo <> v_def then execute v_novo; end if;
end;
$$;
