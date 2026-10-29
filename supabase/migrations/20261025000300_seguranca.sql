-- iService: quem pode ler e escrever o quê (RLS e permissões por coluna).
-- Regra geral: os apps leem direto as tabelas permitidas e mudam estado só
-- pelas funções da migração anterior.

alter table public.app_config enable row level security;
alter table public.regioes enable row level security;
alter table public.profissoes enable row level security;
alter table public.especialidades enable row level security;
alter table public.certificacoes_sugeridas enable row level security;
alter table public.perfis enable row level security;
alter table public.enderecos enable row level security;
alter table public.profissionais enable row level security;
alter table public.profissional_profissoes enable row level security;
alter table public.profissional_especialidades enable row level security;
alter table public.certificacoes enable row level security;
alter table public.documentos enable row level security;
alter table public.portfolio enable row level security;
alter table public.pedidos enable row level security;
alter table public.mensagens enable row level security;
alter table public.avaliacoes enable row level security;
alter table public.favoritos enable row level security;
alter table public.notificacoes enable row level security;
alter table public.dispositivos enable row level security;
alter table public.reclamacoes enable row level security;
alter table public.emergencias enable row level security;
alter table public.compartilhamentos enable row level security;
alter table public.pontos enable row level security;
alter table public.indicacoes enable row level security;

-- Nada é aberto por padrão; cada permissão abaixo é explícita.
revoke all on all tables in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Catálogo: leitura para todos (inclusive antes do login)
-- ---------------------------------------------------------------------------
grant select on public.app_config, public.regioes, public.profissoes, public.especialidades, public.certificacoes_sugeridas to anon, authenticated;
create policy "config: leitura" on public.app_config for select using (true);
create policy "regioes: leitura" on public.regioes for select using (true);
create policy "profissoes: leitura" on public.profissoes for select using (ativa or public.e_admin());
create policy "especialidades: leitura" on public.especialidades for select using (aprovada or criada_por = auth.uid() or public.e_admin());
create policy "certificacoes sugeridas: leitura" on public.certificacoes_sugeridas for select using (true);

-- ---------------------------------------------------------------------------
-- Perfis: nome e foto são públicos para quem está logado; o resto só pelo meu_perfil()
-- ---------------------------------------------------------------------------
grant select (id, nome, foto_url, e_profissional) on public.perfis to authenticated;
grant update (nome, nascimento, cpf, telefone, foto_url, letra_grande) on public.perfis to authenticated;
create policy "perfis: leitura" on public.perfis for select to authenticated using (true);
create policy "perfis: editar o próprio" on public.perfis for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

grant select (id, usuario_id, rotulo, regiao_id, logradouro, bloco, numero, complemento, referencia, cep, cidade, uf, principal, criado_em),
  delete on public.enderecos to authenticated;
create policy "enderecos: dono lê" on public.enderecos for select to authenticated using (usuario_id = auth.uid());
create policy "enderecos: dono apaga" on public.enderecos for delete to authenticated using (usuario_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Profissionais: dados públicos dos aprovados (a área de atendimento não é pública)
-- ---------------------------------------------------------------------------
grant select (id, status, verificado, disponivel, bio, anos_experiencia, regiao_id, nota_media, total_avaliacoes,
  servicos_concluidos, aprovado_em) on public.profissionais to authenticated;
grant update (bio, anos_experiencia) on public.profissionais to authenticated;
create policy "profissionais: leitura" on public.profissionais for select to authenticated
  using (status = 'aprovado' or id = auth.uid() or public.e_admin());
create policy "profissionais: editar o próprio" on public.profissionais for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

grant select, insert, delete on public.profissional_profissoes to authenticated;
grant update (principal) on public.profissional_profissoes to authenticated;
create policy "prof_profissoes: leitura" on public.profissional_profissoes for select to authenticated using (true);
create policy "prof_profissoes: dono escreve" on public.profissional_profissoes for all to authenticated
  using (profissional_id = auth.uid()) with check (profissional_id = auth.uid() and exists (select 1 from public.profissionais where id = auth.uid()));

grant select, insert, delete on public.profissional_especialidades to authenticated;
grant update (preco) on public.profissional_especialidades to authenticated;
create policy "prof_especialidades: leitura" on public.profissional_especialidades for select to authenticated using (true);
create policy "prof_especialidades: dono escreve" on public.profissional_especialidades for all to authenticated
  using (profissional_id = auth.uid())
  with check (profissional_id = auth.uid() and exists (
    select 1 from public.especialidades e join public.profissional_profissoes pp on pp.profissao_id = e.profissao_id
    where e.id = especialidade_id and pp.profissional_id = auth.uid()));

grant select, insert, delete on public.certificacoes to authenticated;
create policy "certificacoes: leitura" on public.certificacoes for select to authenticated
  using (status = 'aprovado' or profissional_id = auth.uid() or public.e_admin());
create policy "certificacoes: dono envia" on public.certificacoes for insert to authenticated
  with check (profissional_id = auth.uid() and status = 'pendente');
create policy "certificacoes: dono apaga" on public.certificacoes for delete to authenticated using (profissional_id = auth.uid());

grant select, insert on public.documentos to authenticated;
create policy "documentos: dono e admin leem" on public.documentos for select to authenticated using (profissional_id = auth.uid() or public.e_admin());
create policy "documentos: dono envia" on public.documentos for insert to authenticated
  with check (profissional_id = auth.uid() and status = 'pendente');

grant select, insert, update, delete on public.portfolio to authenticated;
create policy "portfolio: leitura" on public.portfolio for select to authenticated using (true);
create policy "portfolio: dono escreve" on public.portfolio for all to authenticated
  using (profissional_id = auth.uid()) with check (profissional_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Pedidos, chat e avaliações
-- ---------------------------------------------------------------------------
grant select on public.pedidos to authenticated;
create policy "pedidos: participantes leem" on public.pedidos for select to authenticated
  using (auth.uid() in (cliente_id, profissional_id) or public.e_admin());

grant select, insert on public.mensagens to authenticated;
create policy "mensagens: participantes leem" on public.mensagens for select to authenticated using (public.participa_do_pedido(pedido_id));
create policy "mensagens: participantes enviam" on public.mensagens for insert to authenticated
  with check (autor_id = auth.uid() and public.participa_do_pedido(pedido_id) and lida_em is null);

grant select on public.avaliacoes to authenticated;
grant update (resposta) on public.avaliacoes to authenticated;
create policy "avaliacoes: leitura" on public.avaliacoes for select to authenticated using (true);
create policy "avaliacoes: profissional responde" on public.avaliacoes for update to authenticated
  using (profissional_id = auth.uid()) with check (profissional_id = auth.uid());

grant select, insert, delete on public.favoritos to authenticated;
create policy "favoritos: dono" on public.favoritos for all to authenticated
  using (cliente_id = auth.uid()) with check (cliente_id = auth.uid());

grant select, delete on public.notificacoes to authenticated;
grant update (lida) on public.notificacoes to authenticated;
create policy "notificacoes: dono" on public.notificacoes for all to authenticated
  using (usuario_id = auth.uid()) with check (usuario_id = auth.uid());

grant select, insert, update, delete on public.dispositivos to authenticated;
create policy "dispositivos: dono" on public.dispositivos for all to authenticated
  using (usuario_id = auth.uid()) with check (usuario_id = auth.uid());

grant select on public.reclamacoes to authenticated;
create policy "reclamacoes: participantes leem" on public.reclamacoes for select to authenticated
  using (autor_id = auth.uid() or exists (select 1 from public.pedidos p where p.id = pedido_id and p.profissional_id = auth.uid()) or public.e_admin());

grant select on public.emergencias to authenticated;
create policy "emergencias: dono e admin" on public.emergencias for select to authenticated using (usuario_id = auth.uid() or public.e_admin());

grant select on public.pontos, public.indicacoes to authenticated;
create policy "pontos: dono" on public.pontos for select to authenticated using (usuario_id = auth.uid());
create policy "indicacoes: envolvidos" on public.indicacoes for select to authenticated using (auth.uid() in (indicado_id, indicador_id));

-- ---------------------------------------------------------------------------
-- Funções que os apps podem chamar
-- ---------------------------------------------------------------------------
grant execute on function
  public.meu_perfil(), public.salvar_endereco(text, double precision, double precision, text, text, text, text, text, text, text, text, text, boolean, bigint),
  public.concluir_cadastro_cliente(), public.ativar_profissional(), public.sugerir_especialidade(text, text),
  public.definir_area_atendimento(double precision, double precision, numeric, text), public.enviar_cadastro_profissional(),
  public.definir_disponivel(boolean), public.buscar_profissionais(text, double precision, double precision, bigint, text, integer, integer),
  public.top_regiao(double precision, double precision, text, integer, integer), public.perfil_profissional(uuid),
  public.faixa_preco(bigint, text),
  public.criar_pedido(uuid, text, bigint, public.quando_pedido, bigint, text, text, timestamptz, text[]),
  public.responder_pedido(uuid, boolean, text), public.avancar_pedido(uuid, public.status_pedido, numeric, text),
  public.cancelar_pedido(uuid, text), public.meus_pedidos(text, text, integer), public.avaliar_pedido(uuid, smallint, text, text[]),
  public.marcar_mensagens_lidas(uuid), public.acionar_emergencia(uuid, double precision, double precision),
  public.compartilhar_acompanhamento(uuid), public.abrir_reclamacao(uuid, text, text, text[]), public.resumo_ganhos(date, date),
  public.pendencias_profissional(uuid), public.admin_decidir_cadastro(uuid, boolean, text), public.e_admin(),
  public.participa_do_pedido(uuid), public.cpf_valido(text), public.ponto(double precision, double precision)
to authenticated;

grant execute on function public.acompanhamento_publico(text), public.faixa_preco(bigint, text), public.cpf_valido(text) to anon;

-- Funções internas usadas dentro de políticas e gatilhos.
grant execute on function public.cfg(text), public.cfg_num(text, numeric), public.cfg_bool(text, boolean),
  public.em_atendimento(uuid), public.alcance_km(numeric, public.plano_profissional, timestamptz), public.erro(text, text)
to authenticated;

-- ---------------------------------------------------------------------------
-- Tempo real: pedidos, mensagens e notificações chegam na hora nos apps
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.pedidos, public.mensagens, public.notificacoes;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Arquivos (Supabase Storage). Pasta = id do usuário.
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'storage' and table_name = 'buckets') then
    insert into storage.buckets (id, name, public) values
      ('fotos', 'fotos', true),            -- foto de perfil
      ('portfolio', 'portfolio', true),    -- antes e depois
      ('avaliacoes', 'avaliacoes', true),  -- fotos das avaliações
      ('pedidos', 'pedidos', false),       -- fotos do problema enviadas no pedido
      ('documentos', 'documentos', false)  -- documento, selfie, antecedentes, certificados
    on conflict (id) do nothing;
  end if;
end;
$$;

do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'storage' and table_name = 'objects') then
    execute $p$create policy "arquivos públicos: leitura" on storage.objects for select
      using (bucket_id in ('fotos', 'portfolio', 'avaliacoes'))$p$;
    execute $p$create policy "arquivos: dono envia" on storage.objects for insert to authenticated
      with check (bucket_id in ('fotos', 'portfolio', 'avaliacoes', 'pedidos', 'documentos') and (storage.foldername(name))[1] = auth.uid()::text)$p$;
    execute $p$create policy "arquivos: dono altera" on storage.objects for update to authenticated
      using ((storage.foldername(name))[1] = auth.uid()::text)$p$;
    execute $p$create policy "arquivos: dono apaga" on storage.objects for delete to authenticated
      using ((storage.foldername(name))[1] = auth.uid()::text)$p$;
    execute $p$create policy "documentos: dono e admin leem" on storage.objects for select to authenticated
      using (bucket_id = 'documentos' and ((storage.foldername(name))[1] = auth.uid()::text or public.e_admin()))$p$;
    -- Fotos do pedido: quem enviou e o profissional daquele pedido (pasta = cliente/pedido/...).
    execute $p$create policy "pedidos: participantes leem" on storage.objects for select to authenticated
      using (bucket_id = 'pedidos' and ((storage.foldername(name))[1] = auth.uid()::text
        or exists (select 1 from public.pedidos p where p.id::text = (storage.foldername(name))[2] and p.profissional_id = auth.uid())))$p$;
  end if;
end;
$$;
