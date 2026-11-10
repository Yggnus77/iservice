-- Auditoria de segurança (10/11/2026)
--
-- Teste completo do banco em produção (permissões, RLS, Storage, funções) e do
-- código dos apps, painel, site e funções do servidor. O que foi corrigido aqui:
--
--  1. Mapa ao vivo (posicoes_pedido): a tabela nasceu com permissão total para
--     anon e authenticated (padrão do Supabase). A RLS segurava, mas fica só leitura.
--  2. Storage: o usuário podia sobrescrever ou apagar os próprios documentos depois
--     de aprovados (trocar a selfie ou o RG já conferidos pela equipe) e as fotos de
--     avaliações e pedidos (provas da Garantia). Agora só foto de perfil e portfólio
--     podem ser trocadas ou apagadas pelo próprio usuário.
--  3. Colunas que só o sistema preenche: dava para mandar mensagem com data falsa
--     (criada_em, atrapalhando a mediação), documento já com "revisado_por" e
--     certificação com data falsa. Agora o insert aceita só as colunas do app.
--  4. Arquivos de outra pessoa: documento, certificação e portfólio podiam apontar
--     para o arquivo de outro usuário (ex.: usar o RG aprovado de outra pessoa).
--     Agora o caminho tem que estar na pasta do próprio usuário.
--  5. Foto de perfil e fotos de avaliação: aceitavam qualquer projeto *.supabase.co
--     (ou qualquer link, nas avaliações), o que permitia rastrear quem abre o perfil
--     e fugir da moderação. Agora só o Storage do iService, na pasta do autor.
--  6. Profissional em análise ou aprovado não troca mais nome, CPF e nascimento
--     sozinho (eram usados na verificação do selo). Correção pelo suporte.
--  7. Equipe: alguém do suporte conseguia suspender o dono e trancá-lo fora do
--     painel. O dono não pode mais ser suspenso.
--  8. Limites de tamanho nos textos e na quantidade de fotos (evita abuso e lentidão).
--  9. Funções de gatilho e admin_site deixam de ficar expostas na API para anon.
--
-- Pode rodar mais de uma vez.

-- ---------------------------------------------------------------------------
-- 1. Mapa ao vivo: só leitura (quem escreve é a função enviar_posicao)
-- ---------------------------------------------------------------------------
revoke all on public.posicoes_pedido from anon, authenticated;
grant select on public.posicoes_pedido to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Storage: trocar ou apagar só foto de perfil e portfólio
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('storage.objects') is null then return; end if;
  execute 'drop policy if exists "arquivos: dono altera" on storage.objects';
  execute 'drop policy if exists "arquivos: dono apaga" on storage.objects';
  execute $p$create policy "arquivos: dono altera" on storage.objects for update to authenticated
    using (bucket_id in ('fotos', 'portfolio') and (storage.foldername(name))[1] = auth.uid()::text)
    with check (bucket_id in ('fotos', 'portfolio') and (storage.foldername(name))[1] = auth.uid()::text)$p$;
  execute $p$create policy "arquivos: dono apaga" on storage.objects for delete to authenticated
    using (bucket_id in ('fotos', 'portfolio') and (storage.foldername(name))[1] = auth.uid()::text)$p$;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Insert só com as colunas que o app manda
-- ---------------------------------------------------------------------------
revoke insert on public.mensagens from anon, authenticated;
grant insert (pedido_id, autor_id, texto) on public.mensagens to authenticated;

revoke insert on public.documentos from anon, authenticated;
grant insert (profissional_id, tipo, arquivo_path) on public.documentos to authenticated;

revoke insert on public.certificacoes from anon, authenticated;
grant insert (profissional_id, profissao_id, nome, instituicao, arquivo_path) on public.certificacoes to authenticated;

revoke insert, update on public.portfolio from anon, authenticated;
grant insert (profissional_id, profissao_id, descricao, antes_path, depois_path, ordem) on public.portfolio to authenticated;
grant update (profissao_id, descricao, ordem) on public.portfolio to authenticated;

-- ---------------------------------------------------------------------------
-- 4 e 5. Arquivos sempre na pasta de quem enviou, no Storage do iService
-- ---------------------------------------------------------------------------
-- Aceita o caminho dentro do bucket ("<dono>/arquivo.jpg"), o caminho com o bucket
-- ("fotos/<dono>/arquivo.jpg") ou o link público do Storage do iService.
create or replace function public.arquivo_do_usuario(p_caminho text, p_bucket text, p_dono uuid)
returns boolean
language sql immutable
set search_path = public
as $$
  select p_caminho is not null and p_dono is not null
    and p_caminho !~ '\.\.'
    and p_caminho ~ ('^((https://aurjqwqqrxaexmwozezr\.supabase\.co/storage/v1/object/public/)?' || p_bucket || '/)?'
                     || p_dono::text || '/[^?#]+$')
$$;

create or replace function public.arquivos_do_usuario(p_caminhos text[], p_bucket text, p_dono uuid, p_max int default 10)
returns boolean
language sql immutable
set search_path = public
as $$
  select coalesce(cardinality(p_caminhos), 0) <= p_max
    and coalesce((select bool_and(public.arquivo_do_usuario(c, p_bucket, p_dono)) from unnest(p_caminhos) c), true)
$$;

alter table public.documentos drop constraint if exists documentos_arquivo_do_dono;
alter table public.documentos add constraint documentos_arquivo_do_dono
  check (public.arquivo_do_usuario(arquivo_path, 'documentos', profissional_id)) not valid;

alter table public.certificacoes drop constraint if exists certificacoes_arquivo_do_dono;
alter table public.certificacoes add constraint certificacoes_arquivo_do_dono
  check (arquivo_path is null or public.arquivo_do_usuario(arquivo_path, 'documentos', profissional_id)) not valid;

alter table public.portfolio drop constraint if exists portfolio_arquivos_do_dono;
alter table public.portfolio add constraint portfolio_arquivos_do_dono
  check (public.arquivo_do_usuario(depois_path, 'portfolio', profissional_id)
         and (antes_path is null or public.arquivo_do_usuario(antes_path, 'portfolio', profissional_id))) not valid;

alter table public.avaliacoes drop constraint if exists avaliacoes_fotos_do_cliente;
alter table public.avaliacoes add constraint avaliacoes_fotos_do_cliente
  check (public.arquivos_do_usuario(fotos, 'avaliacoes', cliente_id)) not valid;

alter table public.perfis drop constraint if exists perfis_foto_do_iservice;
alter table public.perfis add constraint perfis_foto_do_iservice
  check (foto_url is null or public.arquivo_do_usuario(foto_url, 'fotos', id)) not valid;

-- ---------------------------------------------------------------------------
-- 6. Dados verificados do profissional
-- ---------------------------------------------------------------------------
-- Só barra a edição direta pela API (role authenticated). As funções do sistema,
-- como a exclusão de conta, rodam como dono do banco e seguem funcionando.
create or replace function public.travar_dados_verificados()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user = 'authenticated'
     and (new.nome is distinct from old.nome or new.cpf is distinct from old.cpf or new.nascimento is distinct from old.nascimento)
     and exists (select 1 from public.profissionais where id = new.id and status in ('em_analise', 'aprovado', 'suspenso'))
     and not public.e_admin()
  then
    perform public.erro('dados_verificados',
      'Seu cadastro já foi enviado para verificação. Para corrigir nome, CPF ou data de nascimento, fale com o suporte iService.');
  end if;
  return new;
end;
$$;
revoke all on function public.travar_dados_verificados() from public, anon, authenticated;

drop trigger if exists travar_dados_verificados on public.perfis;
create trigger travar_dados_verificados before update of nome, cpf, nascimento on public.perfis
  for each row execute function public.travar_dados_verificados();

-- ---------------------------------------------------------------------------
-- 7. O dono do painel não pode ser suspenso
-- ---------------------------------------------------------------------------
create or replace function public.admin_suspender(p_usuario uuid, p_suspender boolean, p_motivo text default null)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  perform public.exigir_admin();
  if p_usuario = auth.uid() then perform public.erro('sem_permissao', 'Você não pode suspender a própria conta.'); end if;
  if not exists (select 1 from public.perfis where id = p_usuario and excluido_em is null) then
    perform public.erro('nao_encontrado', 'Pessoa não encontrada.');
  end if;
  if p_suspender and to_regclass('public.equipe') is not null
     and exists (select 1 from public.equipe where usuario_id = p_usuario and papel = 'dono') then
    perform public.erro('dono', 'O dono do painel não pode ser suspenso.');
  end if;
  if p_suspender then
    if coalesce(trim(p_motivo), '') = '' then perform public.erro('motivo_obrigatorio', 'Escreva o motivo da suspensão.'); end if;
    update public.perfis set suspenso_em = coalesce(suspenso_em, now()), motivo_suspensao = trim(p_motivo) where id = p_usuario;
    update public.profissionais set status = 'suspenso', disponivel = false, motivo_status = trim(p_motivo) where id = p_usuario;
    -- Pedidos que ainda nem foram aceitos são cancelados; os em andamento ficam para a equipe acompanhar.
    update public.pedidos set status = 'cancelado', motivo = 'Conta suspensa pela equipe iService', cancelado_por = auth.uid(), encerrado_em = now()
    where status = 'solicitado' and p_usuario in (cliente_id, profissional_id);
    begin
      update auth.users set banned_until = 'infinity' where id = p_usuario;
    exception when others then null;
    end;
  else
    update public.perfis set suspenso_em = null, motivo_suspensao = null where id = p_usuario;
    update public.profissionais set status = case when aprovado_em is not null then 'aprovado' else 'em_analise' end::public.status_cadastro,
      motivo_status = null
    where id = p_usuario and status = 'suspenso';
    begin
      update auth.users set banned_until = null where id = p_usuario;
    exception when others then null;
    end;
    perform public.notificar(p_usuario, 'conta_reativada', 'Sua conta foi reativada', 'Você já pode usar o iService normalmente.');
  end if;
  perform public.registrar_acao(case when p_suspender then 'suspender' else 'reativar' end, p_usuario::text, jsonb_build_object('motivo', p_motivo));
end;
$$;
revoke all on function public.admin_suspender(uuid, boolean, text) from public, anon;
grant execute on function public.admin_suspender(uuid, boolean, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Limites de tamanho (valem para linhas novas e alteradas)
-- ---------------------------------------------------------------------------
alter table public.pedidos drop constraint if exists pedidos_limites;
alter table public.pedidos add constraint pedidos_limites
  check (length(descricao) <= 2000 and cardinality(fotos) <= 10 and length(coalesce(motivo, '')) <= 1000) not valid;

alter table public.avaliacoes drop constraint if exists avaliacoes_limites;
alter table public.avaliacoes add constraint avaliacoes_limites
  check (length(coalesce(comentario, '')) <= 2000 and length(coalesce(resposta, '')) <= 2000) not valid;

alter table public.reclamacoes drop constraint if exists reclamacoes_limites;
alter table public.reclamacoes add constraint reclamacoes_limites
  check (length(motivo) <= 200 and length(descricao) <= 4000 and cardinality(fotos) <= 10) not valid;

alter table public.perfis drop constraint if exists perfis_limites;
alter table public.perfis add constraint perfis_limites check (length(nome) <= 120) not valid;

alter table public.profissionais drop constraint if exists profissionais_limites;
alter table public.profissionais add constraint profissionais_limites check (length(coalesce(bio, '')) <= 2000) not valid;

alter table public.portfolio drop constraint if exists portfolio_limites;
alter table public.portfolio add constraint portfolio_limites check (length(coalesce(descricao, '')) <= 500) not valid;

alter table public.certificacoes drop constraint if exists certificacoes_limites;
alter table public.certificacoes add constraint certificacoes_limites
  check (length(nome) <= 200 and length(coalesce(instituicao, '')) <= 200) not valid;

alter table public.dispositivos drop constraint if exists dispositivos_limites;
alter table public.dispositivos add constraint dispositivos_limites check (length(token) <= 4096) not valid;

-- ---------------------------------------------------------------------------
-- 9. Fora da API pública: funções de gatilho e o resumo do site no painel
-- ---------------------------------------------------------------------------
do $$
declare
  f text;
begin
  foreach f in array array[
    'public.apagar_posicao()', 'public.atualizar_tempo_resposta()', 'public.notificacao_push()',
    'public.celular_trocado()', 'public.exigir_celular_pedido()', 'public.exigir_celular_disponivel()',
    'public.cobranca_padrao_especialidade()', 'public.marcar_resposta()'
  ] loop
    if to_regprocedure(f) is not null then
      execute format('revoke all on function %s from public, anon, authenticated', f);
    end if;
  end loop;

  if to_regprocedure('public.admin_site(integer)') is not null then
    revoke all on function public.admin_site(integer) from public, anon;
    grant execute on function public.admin_site(integer) to authenticated;
  end if;

  -- Criada pela agenda de 7 dias; fixa o search_path (aviso do Supabase).
  if to_regprocedure('public.tipo_tem_email(text)') is not null then
    alter function public.tipo_tem_email(text) set search_path = public;
  end if;
end;
$$;
