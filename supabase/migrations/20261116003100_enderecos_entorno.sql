-- Endereços do Entorno (16/11/2026)
-- 1) Campo "Bairro / setor" no endereço. No Entorno (Goiás) a mesma "Rua 10 Qd 5" existe em
--    vários bairros da cidade; sem o bairro o profissional não acha a casa.
-- 2) Cidades e regiões administrativas que faltavam na lista (12 do DF e 4 do Entorno),
--    cada uma na faixa de preço do seu grupo, e a lista em ordem alfabética (DF, depois Goiás).
-- 3) O texto do endereço no pedido passa a ter o bairro e não repete vírgulas de campos vazios.

alter table public.enderecos add column if not exists bairro text;
grant select (bairro) on public.enderecos to authenticated;

-- salvar_endereco ganha p_bairro (no fim, para as chamadas antigas continuarem valendo).
drop function if exists public.salvar_endereco(text, double precision, double precision, text, text, text, text, text, text, text, text, text, boolean, bigint);
create or replace function public.salvar_endereco(
  p_logradouro text, p_lat double precision, p_lng double precision,
  p_regiao_id text default null, p_bloco text default null, p_numero text default null,
  p_complemento text default null, p_referencia text default null, p_cep text default null,
  p_cidade text default 'Brasília', p_uf text default 'DF', p_rotulo text default 'Casa',
  p_principal boolean default true, p_id bigint default null, p_bairro text default null
)
returns bigint
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id bigint;
  v_uf text;
begin
  if auth.uid() is null then perform public.erro('nao_autenticado', 'Entre na sua conta para continuar.'); end if;
  select uf into v_uf from public.regioes where id = p_regiao_id;
  -- Só nos endereços novos, para não travar quem já tinha endereço salvo sem bairro.
  if p_id is null and v_uf = 'GO' and nullif(btrim(coalesce(p_bairro, '')), '') is null then
    perform public.erro('endereco_invalido', 'Informe o bairro ou setor. No Entorno ele ajuda o profissional a achar o endereço.');
  end if;
  if p_principal then
    update public.enderecos set principal = false where usuario_id = auth.uid() and principal and id is distinct from p_id;
  end if;
  if p_id is null then
    insert into public.enderecos (usuario_id, rotulo, regiao_id, logradouro, bloco, numero, complemento, bairro, referencia, cep, cidade, uf, localizacao, principal)
    values (auth.uid(), p_rotulo, p_regiao_id, p_logradouro, p_bloco, p_numero, p_complemento, nullif(btrim(coalesce(p_bairro, '')), ''), p_referencia,
            nullif(regexp_replace(coalesce(p_cep, ''), '\D', '', 'g'), ''), p_cidade, p_uf, public.ponto(p_lat, p_lng), p_principal)
    returning id into v_id;
  else
    update public.enderecos set rotulo = p_rotulo, regiao_id = p_regiao_id, logradouro = p_logradouro, bloco = p_bloco,
      numero = p_numero, complemento = p_complemento, bairro = nullif(btrim(coalesce(p_bairro, '')), ''), referencia = p_referencia,
      cep = nullif(regexp_replace(coalesce(p_cep, ''), '\D', '', 'g'), ''), cidade = p_cidade, uf = p_uf,
      localizacao = public.ponto(p_lat, p_lng), principal = p_principal
    where id = p_id and usuario_id = auth.uid()
    returning id into v_id;
    if v_id is null then perform public.erro('endereco_invalido', 'Endereço não encontrado.'); end if;
  end if;
  return v_id;
end;
$$;
revoke all on function public.salvar_endereco(text, double precision, double precision, text, text, text, text, text, text, text, text, text, boolean, bigint, text) from public, anon;
grant execute on function public.salvar_endereco(text, double precision, double precision, text, text, text, text, text, text, text, text, text, boolean, bigint, text) to authenticated;

-- meu_perfil e a ficha do painel passam a devolver o bairro.
create or replace function public.meu_perfil()
returns jsonb
language sql stable security definer
set search_path = public, extensions
as $$
  select jsonb_build_object(
    'perfil', to_jsonb(p.*),
    'enderecos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', e.id, 'rotulo', e.rotulo, 'regiao_id', e.regiao_id, 'logradouro', e.logradouro, 'bloco', e.bloco,
        'numero', e.numero, 'complemento', e.complemento, 'bairro', e.bairro, 'referencia', e.referencia, 'cep', e.cep,
        'cidade', e.cidade, 'uf', e.uf, 'principal', e.principal,
        'lat', extensions.st_y(e.localizacao::extensions.geometry), 'lng', extensions.st_x(e.localizacao::extensions.geometry)
      ) order by e.principal desc, e.id)
      from public.enderecos e where e.usuario_id = p.id), '[]'::jsonb),
    'profissional', (
      select to_jsonb(pr.*) - 'area_centro' || jsonb_build_object(
        'area_lat', extensions.st_y(pr.area_centro::extensions.geometry),
        'area_lng', extensions.st_x(pr.area_centro::extensions.geometry))
      from public.profissionais pr where pr.id = p.id),
    'pontos', coalesce((select sum(pontos) from public.pontos where usuario_id = p.id), 0)
  )
  from public.perfis p
  where p.id = auth.uid()
$$;


create or replace function public.admin_usuario(p_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  v jsonb;
begin
  perform public.exigir_admin();
  select jsonb_build_object(
    'perfil', jsonb_build_object('id', pe.id, 'nome', pe.nome, 'email', pe.email, 'telefone', pe.telefone, 'cpf', pe.cpf,
      'nascimento', pe.nascimento, 'foto_url', pe.foto_url, 'telefone_verificado', pe.telefone_verificado,
      'e_cliente', pe.e_cliente, 'e_profissional', pe.e_profissional, 'e_admin', pe.e_admin,
      'criado_em', pe.criado_em, 'suspenso_em', pe.suspenso_em, 'motivo_suspensao', pe.motivo_suspensao,
      'exclusao_solicitada_em', pe.exclusao_solicitada_em, 'codigo_indicacao', pe.codigo_indicacao),
    'enderecos', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'rotulo', e.rotulo, 'logradouro', e.logradouro, 'bloco', e.bloco,
        'numero', e.numero, 'complemento', e.complemento, 'bairro', e.bairro, 'cidade', e.cidade, 'uf', e.uf, 'cep', e.cep,
        'regiao', (select r.nome from public.regioes r where r.id = e.regiao_id), 'principal', e.principal) order by e.principal desc, e.id)
      from public.enderecos e where e.usuario_id = pe.id), '[]'::jsonb),
    'profissional', (select jsonb_build_object(
        'status', pr.status, 'motivo_status', pr.motivo_status, 'verificado', pr.verificado, 'disponivel', pr.disponivel,
        'bio', pr.bio, 'anos_experiencia', pr.anos_experiencia, 'area_raio_km', pr.area_raio_km,
        'area_lat', extensions.st_y(pr.area_centro::extensions.geometry), 'area_lng', extensions.st_x(pr.area_centro::extensions.geometry),
        'regiao', (select r.nome from public.regioes r where r.id = pr.regiao_id), 'plano', pr.plano,
        'nota_media', pr.nota_media, 'total_avaliacoes', pr.total_avaliacoes, 'servicos_concluidos', pr.servicos_concluidos,
        'pedidos_recebidos', pr.pedidos_recebidos, 'pedidos_aceitos', pr.pedidos_aceitos, 'pedidos_perdidos', pr.pedidos_perdidos,
        'cancelados_pelo_profissional', pr.cancelados_pelo_profissional, 'aprovado_em', pr.aprovado_em, 'criado_em', pr.criado_em,
        'atualizado_em', pr.atualizado_em,
        'pendencias', to_jsonb(coalesce(public.pendencias_profissional(pr.id), '{}')),
        'profissoes', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'nome', f.nome, 'principal', pp.principal,
            'exige_antecedentes', f.exige_antecedentes,
            'especialidades', coalesce((select jsonb_agg(jsonb_build_object('id', es.id, 'nome', es.nome, 'preco', x.preco, 'aprovada', es.aprovada)
                order by es.ordem, es.nome)
              from public.profissional_especialidades x join public.especialidades es on es.id = x.especialidade_id
              where x.profissional_id = pr.id and es.profissao_id = f.id), '[]'::jsonb)) order by pp.principal desc, f.ordem)
          from public.profissional_profissoes pp join public.profissoes f on f.id = pp.profissao_id where pp.profissional_id = pr.id), '[]'::jsonb),
        'documentos', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'tipo', d.tipo, 'arquivo_path', d.arquivo_path, 'status', d.status,
            'observacao', d.observacao, 'criado_em', d.criado_em, 'revisado_em', d.revisado_em) order by d.tipo, d.criado_em desc)
          from public.documentos d where d.profissional_id = pr.id), '[]'::jsonb),
        'certificacoes', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'nome', c.nome, 'instituicao', c.instituicao,
            'profissao_id', c.profissao_id, 'arquivo_path', c.arquivo_path, 'status', c.status, 'criado_em', c.criado_em) order by c.criado_em)
          from public.certificacoes c where c.profissional_id = pr.id), '[]'::jsonb),
        'portfolio', coalesce((select jsonb_agg(jsonb_build_object('id', po.id, 'descricao', po.descricao, 'antes_path', po.antes_path,
            'depois_path', po.depois_path) order by po.ordem, po.id) from public.portfolio po where po.profissional_id = pr.id), '[]'::jsonb))
      from public.profissionais pr where pr.id = pe.id),
    'pedidos', coalesce((select jsonb_agg(x order by (x ->> 'criado_em') desc) from (
        select jsonb_build_object('id', p.id, 'codigo', p.codigo, 'status', p.status, 'criado_em', p.criado_em,
          'profissao', (select f.nome from public.profissoes f where f.id = p.profissao_id),
          'papel', case when p.cliente_id = pe.id then 'cliente' else 'profissional' end,
          'outra_parte', (select o.nome from public.perfis o where o.id = case when p.cliente_id = pe.id then p.profissional_id else p.cliente_id end),
          'valor', coalesce(p.valor_cobrado, p.preco_informado)) x
        from public.pedidos p where pe.id in (p.cliente_id, p.profissional_id) order by p.criado_em desc limit 30) s), '[]'::jsonb),
    'denuncias_recebidas', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'motivo', d.motivo, 'status', d.status, 'criada_em', d.criada_em)
        order by d.criada_em desc) from public.denuncias d where d.alvo_id = pe.id), '[]'::jsonb),
    'reclamacoes', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'motivo', r.motivo, 'status', r.status, 'criada_em', r.criada_em)
        order by r.criada_em desc) from public.reclamacoes r join public.pedidos p on p.id = r.pedido_id
        where pe.id in (p.cliente_id, p.profissional_id)), '[]'::jsonb),
    'acoes', coalesce((select jsonb_agg(jsonb_build_object('acao', a.acao, 'dados', a.dados, 'criada_em', a.criada_em,
        'admin', (select ad.nome from public.perfis ad where ad.id = a.admin_id)) order by a.criada_em desc)
      from (select * from public.admin_acoes where alvo = pe.id::text order by criada_em desc limit 30) a), '[]'::jsonb)
  ) into v
  from public.perfis pe where pe.id = p_id;
  if v is null then perform public.erro('nao_encontrado', 'Pessoa não encontrada.'); end if;
  return v;
end;
$$;


-- criar_pedido: igual à versão da agenda de 7 dias, com o bairro no texto do endereço.
create or replace function public.criar_pedido(
  p_profissional uuid,
  p_profissao text,
  p_endereco_id bigint,
  p_quando public.quando_pedido,
  p_especialidade bigint default null,
  p_descricao text default '',
  p_janela text default null,
  p_combinado_para timestamptz default null,
  p_fotos text[] default '{}'
)
returns public.pedidos
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_end public.enderecos;
  v_pro public.profissionais;
  v_ped public.pedidos;
  v_nome_cliente text;
  v_preco numeric;
  v_dist numeric;
  v_agendado boolean := p_quando = 'combinado';
begin
  if v_uid is null then perform public.erro('nao_autenticado', 'Entre na sua conta para continuar.'); end if;
  if not coalesce((select e_cliente from public.perfis where id = v_uid), false) then
    perform public.erro('cadastro_incompleto', 'Complete seu cadastro, com foto, para fazer pedidos.');
  end if;
  if v_uid = p_profissional then perform public.erro('pedido_proprio', 'Você não pode contratar a si mesmo.'); end if;

  select * into v_end from public.enderecos where id = p_endereco_id and usuario_id = v_uid;
  if v_end.id is null then perform public.erro('endereco_invalido', 'Escolha um endereço válido.'); end if;

  select * into v_pro from public.profissionais where id = p_profissional;
  if v_pro.id is null or v_pro.status <> 'aprovado' then
    perform public.erro('profissional_indisponivel', 'Este profissional não está disponível.');
  end if;
  if not exists (select 1 from public.profissional_profissoes where profissional_id = p_profissional and profissao_id = p_profissao) then
    perform public.erro('profissao_invalida', 'Este profissional não atende essa profissão.');
  end if;
  if p_especialidade is not null then
    select x.preco into v_preco from public.profissional_especialidades x join public.especialidades e on e.id = x.especialidade_id
    where x.profissional_id = p_profissional and x.especialidade_id = p_especialidade and e.profissao_id = p_profissao;
    if not found then perform public.erro('especialidade_invalida', 'Este profissional não oferece essa especialidade.'); end if;
  end if;

  v_dist := round((extensions.st_distance(public.centro_publico(v_pro.area_centro), v_end.localizacao) / 1000)::numeric, 2);
  if v_pro.area_centro is null or v_dist > public.alcance_km(v_pro.area_raio_km, v_pro.plano, v_pro.plano_valido_ate) then
    perform public.erro('fora_da_area', 'Este profissional não atende o seu endereço.');
  end if;

  if not v_agendado then
    if not v_pro.disponivel or public.em_atendimento(p_profissional) then
      perform public.erro('profissional_ocupado', 'Este profissional está ocupado agora. Agende para outro horário ou escolha outro.');
    end if;
    if exists (select 1 from public.pedidos where cliente_id = v_uid and status = 'solicitado' and quando <> 'combinado' and responder_ate > now()) then
      perform public.erro('pedido_aguardando', 'Você já tem um pedido aguardando resposta.');
    end if;
  else
    -- Agendar não depende de o profissional estar disponível agora.
    perform public.validar_horario_agenda(p_combinado_para);
    if exists (select 1 from public.pedidos where cliente_id = v_uid and profissional_id = p_profissional
               and status = 'solicitado' and responder_ate > now()) then
      perform public.erro('pedido_aguardando', 'Você já tem um pedido aguardando a resposta deste profissional.');
    end if;
    if (select count(*) from public.pedidos where cliente_id = v_uid and status = 'solicitado' and quando = 'combinado' and responder_ate > now())
       >= public.cfg_num('max_agendados_aguardando', 3) then
      perform public.erro('pedido_aguardando', 'Você já tem muitos agendamentos aguardando resposta. Espere um deles responder.');
    end if;
  end if;

  insert into public.pedidos (
    cliente_id, profissional_id, profissao_id, especialidade_id, descricao, fotos, quando, janela, combinado_para,
    endereco_id, endereco_texto, regiao_id, localizacao, distancia_km, preco_informado, taxa_urgencia, responder_ate
  ) values (
    v_uid, p_profissional, p_profissao, p_especialidade, coalesce(p_descricao, ''), coalesce(p_fotos, '{}'), p_quando,
    case when p_quando = 'hoje' then coalesce(p_janela, 'Hoje') when v_agendado then null else p_janela end,
    case when v_agendado then p_combinado_para end,
    v_end.id,
    concat_ws(', ', nullif(v_end.logradouro, ''), nullif(v_end.bloco, ''), nullif(v_end.numero, ''), nullif(v_end.complemento, ''),
      nullif(v_end.bairro, ''), v_end.cidade || '/' || v_end.uf),
    v_end.regiao_id, v_end.localizacao, v_dist, v_preco,
    case when p_quando = 'agora' then public.cfg_num('taxa_urgencia', 15) else 0 end,
    case when v_agendado then public.prazo_agendado(p_combinado_para, 'prazo_resposta_agendado_min')
         else now() + make_interval(mins => public.cfg_num('prazo_resposta_min', 10)::int) end
  ) returning * into v_ped;

  update public.profissionais set pedidos_recebidos = pedidos_recebidos + 1 where id = p_profissional;
  select split_part(nome, ' ', 1) into v_nome_cliente from public.perfis where id = v_uid;
  if v_agendado then
    perform public.notificar(p_profissional, 'pedido_novo', v_nome_cliente || ' quer agendar: ' || public.texto_dia_hora(p_combinado_para),
      'Confirme, recuse ou sugira outro horário até as ' || to_char(v_ped.responder_ate at time zone 'America/Sao_Paulo', 'HH24:MI') || '.',
      jsonb_build_object('pedido_id', v_ped.id));
  else
    perform public.notificar(p_profissional, 'pedido_novo', 'Novo pedido de ' || v_nome_cliente,
      'Você tem ' || public.cfg_num('prazo_resposta_min', 10) || ' minutos para responder.', jsonb_build_object('pedido_id', v_ped.id));
  end if;
  return v_ped;
end;
$$;


-- Regiões novas
insert into public.regioes (id, nome, uf, faixa_preco, centro, ordem) values
  ('sol-nascente', 'Sol Nascente/Pôr do Sol', 'DF', 4, public.ponto(-15.805, -48.14), 32),
  ('estrutural', 'SCIA/Estrutural', 'DF', 4, public.ponto(-15.783, -47.993), 28),
  ('itapoa', 'Itapoã', 'DF', 4, public.ponto(-15.748, -47.765), 13),
  ('varjao', 'Varjão', 'DF', 4, public.ponto(-15.71, -47.877), 35),
  ('riacho-fundo-2', 'Riacho Fundo II', 'DF', 4, public.ponto(-15.913, -48.05), 24),
  ('arniqueira', 'Arniqueira', 'DF', 2, public.ponto(-15.857, -48.01), 3),
  ('sobradinho-2', 'Sobradinho II', 'DF', 3, public.ponto(-15.64, -47.825), 31),
  ('fercal', 'Fercal', 'DF', 4, public.ponto(-15.6, -47.87), 10),
  ('candangolandia', 'Candangolândia', 'DF', 3, public.ponto(-15.852, -47.951), 7),
  ('sia', 'SIA', 'DF', 2, public.ponto(-15.802, -47.955), 29),
  ('agua-quente', 'Água Quente', 'DF', 4, public.ponto(-15.955, -48.17), 0),
  ('arapoanga', 'Arapoanga', 'DF', 4, public.ponto(-15.64, -47.65), 2),
  ('alexania', 'Alexânia', 'GO', 5, public.ponto(-16.083, -48.507), 38),
  ('cristalina', 'Cristalina', 'GO', 5, public.ponto(-16.768, -47.613), 41),
  ('padre-bernardo', 'Padre Bernardo', 'GO', 5, public.ponto(-15.16, -48.283), 45),
  ('cocalzinho', 'Cocalzinho de Goiás', 'GO', 5, public.ponto(-15.793, -48.775), 40)
on conflict (id) do update set nome = excluded.nome, uf = excluded.uf, faixa_preco = excluded.faixa_preco, centro = excluded.centro, ordem = excluded.ordem;

-- Lista em ordem alfabética: DF primeiro, depois as cidades de Goiás.
update public.regioes set ordem = 1 where id = 'aguas-claras';
update public.regioes set ordem = 4 where id = 'asa-norte';
update public.regioes set ordem = 5 where id = 'asa-sul';
update public.regioes set ordem = 6 where id = 'brazlandia';
update public.regioes set ordem = 8 where id = 'ceilandia';
update public.regioes set ordem = 9 where id = 'cruzeiro';
update public.regioes set ordem = 11 where id = 'gama';
update public.regioes set ordem = 12 where id = 'guara';
update public.regioes set ordem = 14 where id = 'jardim-botanico';
update public.regioes set ordem = 15 where id = 'lago-norte';
update public.regioes set ordem = 16 where id = 'lago-sul';
update public.regioes set ordem = 17 where id = 'noroeste';
update public.regioes set ordem = 18 where id = 'nucleo-bandeirante';
update public.regioes set ordem = 19 where id = 'paranoa';
update public.regioes set ordem = 20 where id = 'park-way';
update public.regioes set ordem = 21 where id = 'planaltina';
update public.regioes set ordem = 22 where id = 'recanto-das-emas';
update public.regioes set ordem = 23 where id = 'riacho-fundo';
update public.regioes set ordem = 25 where id = 'samambaia';
update public.regioes set ordem = 26 where id = 'santa-maria';
update public.regioes set ordem = 27 where id = 'sao-sebastiao';
update public.regioes set ordem = 30 where id = 'sobradinho';
update public.regioes set ordem = 33 where id = 'sudoeste';
update public.regioes set ordem = 34 where id = 'taguatinga';
update public.regioes set ordem = 36 where id = 'vicente-pires';
update public.regioes set ordem = 37 where id = 'aguas-lindas';
update public.regioes set ordem = 39 where id = 'cidade-ocidental';
update public.regioes set ordem = 42 where id = 'formosa';
update public.regioes set ordem = 43 where id = 'luziania';
update public.regioes set ordem = 44 where id = 'novo-gama';
update public.regioes set ordem = 46 where id = 'planaltina-go';
update public.regioes set ordem = 47 where id = 'santo-antonio';
update public.regioes set ordem = 48 where id = 'valparaiso';
