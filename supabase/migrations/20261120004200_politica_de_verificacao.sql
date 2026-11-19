-- Política de verificação dos profissionais (Plano Diretor, tópico 6, aprovada em 19/11/2026)
--
--  1. Antecedentes criminais de TODOS os profissionais: certidão da Polícia Federal
--     e certidão criminal estadual (TJDFT ou do estado onde mora).
--  2. Documentos extras por profissão: Fretes (CNH e documento do veículo) e
--     Dedetizador (vínculo com empresa licenciada).
--  3. Validade: antecedentes 12 meses, documentos 24 meses, vínculo 12 meses.
--     Aviso 15 dias antes; vencido, o perfil sai das buscas até enviar um novo.
--  4. Fila de análise com a data de envio (prazo de 48 horas úteis no painel).
--  5. A 3ª advertência suspende a conta por 30 dias. Nota geral abaixo de 3,5 com
--     10 ou mais avaliações entra em "Precisa de atenção" para revisão.
--  6. O arquivo das certidões é apagado 90 dias depois da decisão (fica o resultado
--     e a data). Quem apaga é a função limpar-arquivos.
--
-- Os tipos novos de documento são comparados como texto (d.tipo::text) para esta
-- migração rodar inteira de uma vez no editor SQL.

alter type public.tipo_documento add value if not exists 'antecedentes_estadual';
alter type public.tipo_documento add value if not exists 'cnh';
alter type public.tipo_documento add value if not exists 'documento_veiculo';
alter type public.tipo_documento add value if not exists 'vinculo_empresa';

-- ---------------------------------------------------------------------------
-- 1 e 2. Exigências por profissão
-- ---------------------------------------------------------------------------
alter table public.profissoes alter column exige_antecedentes set default true;
update public.profissoes set exige_antecedentes = true where not exige_antecedentes;

alter table public.profissoes add column if not exists documentos_extras text[] not null default '{}';
alter table public.profissoes drop constraint if exists profissoes_documentos_extras_validos;
alter table public.profissoes add constraint profissoes_documentos_extras_validos
  check (documentos_extras <@ array['cnh', 'documento_veiculo', 'vinculo_empresa']::text[]);
update public.profissoes set documentos_extras = array['cnh', 'documento_veiculo'] where id = 'fretes';
update public.profissoes set documentos_extras = array['vinculo_empresa'] where id = 'dedetizador';

alter table public.documentos add column if not exists arquivo_apagado_em timestamptz;
alter table public.profissionais add column if not exists enviado_analise_em timestamptz;

-- Documento que vale: não recusado e dentro da validade.
create or replace function public.documento_vale(p_profissional uuid, p_tipo text)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.documentos d
    where d.profissional_id = p_profissional and d.tipo::text = p_tipo and d.status <> 'recusado'
      and (d.valido_ate is null or d.valido_ate >= (now() at time zone 'America/Sao_Paulo')::date))
$$;
revoke all on function public.documento_vale(uuid, text) from public, anon, authenticated;

-- Documentos extras que as profissões do profissional pedem.
create or replace function public.documentos_extras_do_profissional(p_profissional uuid)
returns text[]
language sql stable security definer
set search_path = public
as $$
  select coalesce(array_agg(distinct x order by x), '{}')
  from public.profissional_profissoes pp
  join public.profissoes f on f.id = pp.profissao_id
  cross join lateral unnest(f.documentos_extras) x
  where pp.profissional_id = p_profissional
$$;
revoke all on function public.documentos_extras_do_profissional(uuid) from public, anon, authenticated;

create or replace function public.exige_antecedentes_do_profissional(p_profissional uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (select 1 from public.profissional_profissoes pp join public.profissoes f on f.id = pp.profissao_id
                 where pp.profissional_id = p_profissional and f.exige_antecedentes)
$$;
revoke all on function public.exige_antecedentes_do_profissional(uuid) from public, anon, authenticated;

create or replace function public.pendencias_profissional(p_id uuid)
returns text[]
language sql stable security definer
set search_path = public
as $$
  select coalesce(public.pendencias_basicas(p_id), '{}') || array_remove(array[
    case when pr.area_centro is null then 'area_atendimento' end,
    case when not exists (select 1 from public.profissional_profissoes pp where pp.profissional_id = p_id) then 'profissao' end,
    case when exists (
      select 1 from public.profissional_profissoes pp
      where pp.profissional_id = p_id and not exists (
        select 1 from public.profissional_especialidades pe join public.especialidades e on e.id = pe.especialidade_id
        where pe.profissional_id = p_id and e.profissao_id = pp.profissao_id)
    ) or exists (
      select 1 from public.profissional_especialidades pe where pe.profissional_id = p_id
        and (pe.preco is null or pe.preco < coalesce(public.preco_minimo_do_profissional(p_id, pe.especialidade_id, pe.cobranca), 0))
    ) then 'especialidades_e_precos' end,
    case when not public.documento_vale(p_id, 'documento_frente') then 'documento' end,
    case when not public.documento_vale(p_id, 'selfie_documento') then 'selfie' end,
    case when public.exige_antecedentes_do_profissional(p_id) and not public.documento_vale(p_id, 'antecedentes') then 'antecedentes' end,
    case when public.exige_antecedentes_do_profissional(p_id) and not public.documento_vale(p_id, 'antecedentes_estadual') then 'antecedentes_estadual' end
  ], null)
  || array(select x from unnest(public.documentos_extras_do_profissional(p_id)) x where not public.documento_vale(p_id, x) order by x)
  from public.profissionais pr
  where pr.id = p_id and (p_id = auth.uid() or public.e_admin() or auth.uid() is null)
$$;


-- ---------------------------------------------------------------------------
-- 3. Validade padrão ao aprovar
-- ---------------------------------------------------------------------------
create or replace function public.validade_padrao_documento()
returns trigger
language plpgsql
as $$
declare
  v_dias integer := case new.tipo::text
    when 'antecedentes' then 365 when 'antecedentes_estadual' then 365 when 'vinculo_empresa' then 365
    when 'documento_frente' then 730 when 'documento_verso' then 730 when 'cnh' then 730 when 'documento_veiculo' then 730
    end;
begin
  if v_dias is not null and new.status = 'aprovado' and old.status is distinct from 'aprovado' and new.valido_ate is null then
    new.valido_ate := (coalesce(new.revisado_em, now()) at time zone 'America/Sao_Paulo')::date + v_dias;
  end if;
  return new;
end;
$$;
revoke all on function public.validade_padrao_documento() from public, anon, authenticated;

-- Documentos já aprovados sem validade: contam da aprovação.
update public.documentos set valido_ate = (coalesce(revisado_em, criado_em) at time zone 'America/Sao_Paulo')::date + 730
where tipo::text in ('documento_frente', 'documento_verso') and status = 'aprovado' and valido_ate is null;

-- Todo dia de manhã: avisa 15 dias antes; no vencimento, o perfil sai das buscas
-- até ele mandar um documento novo (o cadastro volta para "ajustes").
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
           from public.documentos d where d.status = 'aprovado' and d.valido_ate is not null and d.valido_ate <= v_hoje + 15
             and not exists (select 1 from public.documentos n where n.profissional_id = d.profissional_id and n.tipo = d.tipo and n.id > d.id and n.status <> 'recusado')
           union all
           select 'certificacao', c.id, c.profissional_id, 'certificacao', c.nome, c.valido_ate, c.aviso_validade_em, c.aviso_vencido_em
           from public.certificacoes c where c.status = 'aprovado' and c.valido_ate is not null and c.valido_ate <= v_hoje + 15 loop
    v_doc := case when r.tipo = 'certificacao' then 'a certificação "' || r.nome || '"'
      when r.qual = 'antecedentes' then 'sua certidão de antecedentes da Polícia Federal'
      when r.qual = 'antecedentes_estadual' then 'sua certidão criminal estadual'
      when r.qual = 'cnh' then 'sua CNH'
      when r.qual = 'documento_veiculo' then 'o documento do veículo'
      when r.qual = 'vinculo_empresa' then 'o comprovante de vínculo com a empresa'
      else 'seu documento' end;
    if r.valido_ate < v_hoje and r.aviso_vencido_em is null then
      if r.tipo = 'documento' then
        update public.documentos set aviso_vencido_em = now() where id = r.id;
        -- Documento obrigatório vencido: sai das buscas até enviar um novo.
        update public.profissionais set status = 'recusado', disponivel = false,
          motivo_status = 'A validade de ' || v_doc || ' terminou em ' || to_char(r.valido_ate, 'DD/MM/YYYY')
            || '. Envie um novo em "Corrigir cadastro" para voltar a receber pedidos.'
        where id = r.profissional_id and status = 'aprovado';
        perform public.notificar(r.profissional_id, 'documento_vencido', 'Documento vencido',
          'A validade de ' || v_doc || ' terminou em ' || to_char(r.valido_ate, 'DD/MM/YYYY')
            || '. Seu perfil saiu das buscas até você enviar um novo pelo app.',
          jsonb_build_object('tipo', r.tipo, 'id', r.id));
      else
        update public.certificacoes set aviso_vencido_em = now() where id = r.id;
        perform public.notificar(r.profissional_id, 'documento_vencido', 'Certificação vencida',
          'A validade de ' || v_doc || ' terminou em ' || to_char(r.valido_ate, 'DD/MM/YYYY') || '. Envie uma nova pelo app.',
          jsonb_build_object('tipo', r.tipo, 'id', r.id));
      end if;
      n := n + 1;
    elsif r.valido_ate >= v_hoje and r.aviso_validade_em is null then
      perform public.notificar(r.profissional_id, 'documento_vencendo', 'Seu documento vai vencer',
        'A validade de ' || v_doc || ' termina em ' || to_char(r.valido_ate, 'DD/MM/YYYY')
          || '. Envie um novo em Perfil > Documentos para não sair das buscas.',
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
-- 4. Fila de análise: quando o cadastro foi enviado
-- ---------------------------------------------------------------------------
create or replace function public.marcar_envio_analise()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'em_analise' and old.status is distinct from 'em_analise' then
    new.enviado_analise_em := now();
  end if;
  return new;
end;
$$;
revoke all on function public.marcar_envio_analise() from public, anon, authenticated;
drop trigger if exists marcar_envio_analise on public.profissionais;
create trigger marcar_envio_analise before update of status on public.profissionais
  for each row execute function public.marcar_envio_analise();
update public.profissionais set enviado_analise_em = atualizado_em where status = 'em_analise' and enviado_analise_em is null;

drop function if exists public.admin_cadastros(public.status_cadastro, text, integer);
create function public.admin_cadastros(p_status public.status_cadastro default 'em_analise', p_texto text default null, p_limite integer default 200)
returns table (
  id uuid, nome text, email text, telefone text, foto_url text, status public.status_cadastro, motivo_status text,
  profissoes text[], exige_antecedentes boolean, regiao text, documentos_pendentes bigint, documentos_recusados bigint,
  criado_em timestamptz, atualizado_em timestamptz, suspenso boolean, enviado_em timestamptz
)
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.exigir_permissao('cadastros');
  return query
  select pr.id, pe.nome, pe.email, pe.telefone, pe.foto_url, pr.status, pr.motivo_status,
    array(select f.nome from public.profissional_profissoes pp join public.profissoes f on f.id = pp.profissao_id
          where pp.profissional_id = pr.id order by pp.principal desc, f.ordem),
    public.exige_antecedentes_do_profissional(pr.id),
    (select r.nome from public.regioes r where r.id = pr.regiao_id),
    (select count(*) from public.documentos d where d.profissional_id = pr.id and d.status = 'pendente'),
    (select count(*) from public.documentos d where d.profissional_id = pr.id and d.status = 'recusado'),
    pr.criado_em, pr.atualizado_em, pe.suspenso_em is not null, coalesce(pr.enviado_analise_em, pr.atualizado_em)
  from public.profissionais pr join public.perfis pe on pe.id = pr.id
  where (p_status is null or pr.status = p_status)
    and pe.excluido_em is null
    and (p_texto is null or p_texto = '' or pe.nome ilike '%' || p_texto || '%' or pe.email ilike '%' || p_texto || '%'
         or pe.cpf like regexp_replace(p_texto, '\D', '', 'g') || '%' and regexp_replace(p_texto, '\D', '', 'g') <> '')
  -- Fila: quem enviou primeiro é atendido primeiro.
  order by case when pr.status = 'em_analise' then coalesce(pr.enviado_analise_em, pr.atualizado_em) end asc nulls last, pr.atualizado_em desc
  limit p_limite;
end;
$$;
revoke all on function public.admin_cadastros(public.status_cadastro, text, integer) from public, anon;
grant execute on function public.admin_cadastros(public.status_cadastro, text, integer) to authenticated;

-- Revisão de um documento: nomes dos tipos novos e aviso certo para cada um.
create or replace function public.admin_revisar_documento(p_documento bigint, p_aprovar boolean, p_observacao text default null)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_doc public.documentos;
  v_nome text;
begin
  perform public.exigir_permissao('cadastros_decidir');
  select * into v_doc from public.documentos where id = p_documento;
  if v_doc.id is null then perform public.erro('nao_encontrado', 'Documento não encontrado.'); end if;
  if not p_aprovar and coalesce(trim(p_observacao), '') = '' then
    perform public.erro('motivo_obrigatorio', 'Diga ao profissional o que precisa mudar.');
  end if;
  update public.documentos set status = case when p_aprovar then 'aprovado' else 'recusado' end::public.status_documento,
    observacao = nullif(trim(p_observacao), ''), revisado_em = now(), revisado_por = auth.uid()
  where id = p_documento;
  v_nome := case v_doc.tipo::text when 'documento_frente' then 'a frente do documento' when 'documento_verso' then 'o verso do documento'
    when 'selfie_documento' then 'a selfie com o documento' when 'antecedentes' then 'a certidão de antecedentes da Polícia Federal'
    when 'antecedentes_estadual' then 'a certidão criminal estadual' when 'cnh' then 'a CNH'
    when 'documento_veiculo' then 'o documento do veículo' when 'vinculo_empresa' then 'o comprovante de vínculo com a empresa'
    else 'o comprovante de endereço' end;
  if not p_aprovar then
    update public.profissionais set status = 'recusado', motivo_status = 'Envie de novo ' || v_nome || ': ' || trim(p_observacao)
    where id = v_doc.profissional_id and status = 'em_analise';
    perform public.notificar(v_doc.profissional_id, 'documento_recusado', 'Envie o documento de novo',
      'Precisamos que você envie de novo ' || v_nome || '. ' || trim(p_observacao), jsonb_build_object('documento_id', p_documento));
  elsif v_doc.tipo::text in ('antecedentes', 'antecedentes_estadual')
    and exists (select 1 from public.profissionais where id = v_doc.profissional_id and status = 'aprovado') then
    perform public.notificar(v_doc.profissional_id, 'antecedentes_aprovados', 'Certidão aprovada',
      'Sua certidão foi conferida pela equipe iService.');
  end if;
  perform public.registrar_acao(case when p_aprovar then 'aprovar_documento' else 'recusar_documento' end, v_doc.profissional_id::text,
    jsonb_build_object('documento_id', p_documento, 'tipo', v_doc.tipo, 'observacao', p_observacao));
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. 3ª advertência = suspensão de 30 dias
-- ---------------------------------------------------------------------------
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
  perform public.registrar_acao('advertir', p_usuario::text, jsonb_build_object('motivo', btrim(p_motivo), 'total', v_total));
  if v_total % 3 = 0 then
    -- Política de verificação: a cada 3 advertências, 30 dias de suspensão.
    perform public.admin_suspender_por(p_usuario, 30, v_total || 'ª advertência: ' || btrim(p_motivo));
  else
    perform public.notificar(p_usuario, 'advertencia', 'Aviso da equipe iService',
      btrim(p_motivo) || '. Esta é a sua ' || v_total || 'ª advertência. Na 3ª, a conta fica suspensa por 30 dias. Dúvidas: suporte@iservice.app.br.');
  end if;
  return v_total;
end;
$$;

-- Revisão pela nota geral (10+ avaliações abaixo de 3,5) e aviso de quem está perto da 3ª advertência.
do $$
declare
  v_def text := replace(pg_get_functiondef('public.alertas_profissionais_lista(uuid)'::regprocedure), E'\r\n', E'\n');
  v_novo text;
begin
  if position('nota_geral' in v_def) = 0 then
    v_novo := replace(v_def,
      '        case when b.sem_resposta >= 3 then',
      '        case when b.total_avaliacoes >= 10 and b.nota_media < 3.5 then jsonb_build_object(''codigo'', ''nota_geral'', ''nivel'', ''alto'',
          ''texto'', ''Nota geral '' || replace(to_char(b.nota_media, ''FM0.0''), ''.'', '','') || '' com '' || b.total_avaliacoes
            || '' avaliações: revisar a conta (Política de Verificação)'') end,
        case when b.advertencias = 2 then jsonb_build_object(''codigo'', ''advertencias'', ''nivel'', ''medio'',
          ''texto'', ''2 advertências (90 dias): na próxima, a conta é suspensa por 30 dias'') end,
        case when b.sem_resposta >= 3 then');
    if v_novo = v_def then raise exception 'alertas_profissionais_lista sem o trecho esperado.'; end if;
    execute v_novo;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Ficha no painel: mostra se o arquivo já foi apagado
-- ---------------------------------------------------------------------------
do $$
declare
  v_def text := replace(pg_get_functiondef('public.admin_usuario_completo(uuid)'::regprocedure), E'\r\n', E'\n');
  v_novo text;
begin
  if position('arquivo_apagado_em' in v_def) = 0 then
    v_novo := replace(v_def, '''revisado_em'', d.revisado_em)', '''revisado_em'', d.revisado_em, ''arquivo_apagado_em'', d.arquivo_apagado_em, ''valido_ate'', d.valido_ate)');
    if v_novo = v_def then raise exception 'admin_usuario_completo sem o trecho esperado.'; end if;
    execute v_novo;
  end if;
end;
$$;

-- Lista que a função limpar-arquivos usa: certidões decididas há mais de 90 dias.
create or replace function public.certidoes_para_apagar(p_limite integer default 200)
returns table (id bigint, arquivo_path text)
language sql stable security definer
set search_path = public
as $$
  select d.id, d.arquivo_path from public.documentos d
  where d.tipo::text in ('antecedentes', 'antecedentes_estadual') and d.status <> 'pendente'
    and d.arquivo_apagado_em is null and d.revisado_em < now() - interval '90 days'
  order by d.revisado_em
  limit greatest(1, least(coalesce(p_limite, 200), 1000))
$$;
revoke all on function public.certidoes_para_apagar(integer) from public, anon, authenticated;
grant execute on function public.certidoes_para_apagar(integer) to service_role;

create or replace function public.marcar_certidao_apagada(p_ids bigint[])
returns void
language sql security definer
set search_path = public
as $$
  update public.documentos set arquivo_apagado_em = now() where id = any(p_ids) and arquivo_apagado_em is null
$$;
revoke all on function public.marcar_certidao_apagada(bigint[]) from public, anon, authenticated;
grant execute on function public.marcar_certidao_apagada(bigint[]) to service_role;

-- Profissão nova depois do cadastro enviado: o profissional (pelo app) precisa das
-- certidões aprovadas. A equipe e as rotinas do banco não passam por esta trava.
-- Sem security definer: current_user precisa ser quem fez a mudança (o app lê os
-- próprios documentos pelas regras de leitura).
create or replace function public.exigir_antecedentes()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user = 'authenticated'
    and exists (select 1 from public.profissoes where id = new.profissao_id and exige_antecedentes)
    and exists (select 1 from public.profissionais where id = new.profissional_id and status not in ('rascunho', 'recusado'))
    and not (
      exists (select 1 from public.documentos where profissional_id = new.profissional_id and tipo = 'antecedentes' and status = 'aprovado')
      and exists (select 1 from public.documentos where profissional_id = new.profissional_id and tipo::text = 'antecedentes_estadual' and status = 'aprovado'))
  then
    perform public.erro('antecedentes_obrigatorio',
      'Para atender nessa profissão, envie as certidões de antecedentes criminais e aguarde a aprovação da equipe iService.');
  end if;
  return new;
end;
$$;
revoke all on function public.exigir_antecedentes() from public, anon, authenticated;
