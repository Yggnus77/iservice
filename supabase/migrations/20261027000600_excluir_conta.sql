-- Exclusão de conta (exigida pela App Store e pelo Google Play).
-- O usuário pede pelo app (Perfil > Meus dados > Excluir conta, com a senha);
-- a conta sai do ar na hora e os dados pessoais são apagados em até 30 dias.
-- Até lá, ele pode entrar de novo e cancelar.

alter table public.perfis add column if not exists exclusao_solicitada_em timestamptz;
alter table public.perfis add column if not exists excluido_em timestamptz;

insert into public.app_config (chave, valor) values ('dias_exclusao_conta', '30') on conflict (chave) do nothing;

create or replace function public.solicitar_exclusao_conta(p_motivo text default null)
returns timestamptz
language plpgsql security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then perform public.erro('nao_autenticado', 'Entre na sua conta para continuar.'); end if;
  if exists (
    select 1 from public.pedidos
    where v_uid in (cliente_id, profissional_id) and status in ('solicitado', 'aceito', 'a_caminho', 'em_atendimento')
  ) then
    perform public.erro('pedido_em_andamento', 'Conclua ou cancele seus pedidos em andamento antes de excluir a conta.');
  end if;
  update public.perfis set exclusao_solicitada_em = coalesce(exclusao_solicitada_em, now()) where id = v_uid;
  -- Some das buscas na hora.
  update public.profissionais set disponivel = false where id = v_uid;
  insert into public.notificacoes (usuario_id, tipo, titulo, corpo, dados)
  values (v_uid, 'exclusao_conta', 'Exclusão de conta solicitada',
    'Seus dados serão apagados em até ' || public.cfg_num('dias_exclusao_conta', 30) || ' dias. Entre de novo para cancelar.',
    jsonb_build_object('motivo', p_motivo));
  return (select exclusao_solicitada_em from public.perfis where id = v_uid) + make_interval(days => public.cfg_num('dias_exclusao_conta', 30)::int);
end;
$$;

create or replace function public.cancelar_exclusao_conta()
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  update public.perfis set exclusao_solicitada_em = null where id = auth.uid() and excluido_em is null;
end;
$$;

-- Quem pediu a exclusão não volta a aparecer nas buscas até cancelar.
create or replace function public.definir_disponivel(p_disponivel boolean)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_status public.status_cadastro;
begin
  select status into v_status from public.profissionais where id = auth.uid();
  if v_status is distinct from 'aprovado' and p_disponivel then
    perform public.erro('cadastro_nao_aprovado', 'Seu cadastro ainda está em análise.');
  end if;
  if p_disponivel and exists (select 1 from public.perfis where id = auth.uid() and exclusao_solicitada_em is not null) then
    perform public.erro('exclusao_pendente', 'Cancele a exclusão da conta para voltar a receber pedidos.');
  end if;
  update public.profissionais set disponivel = p_disponivel where id = auth.uid();
end;
$$;

-- Apaga de vez as contas com o prazo vencido. Sem histórico de pedidos, o usuário
-- sai inteiro (cascata a partir de auth.users). Com histórico, os pedidos ficam
-- (obrigação fiscal e de garantia) e todo o resto é apagado ou anonimizado.
create or replace function public.excluir_contas_vencidas()
returns integer
language plpgsql security definer
set search_path = public
as $$
declare
  r record;
  n int := 0;
begin
  for r in
    select id from public.perfis
    where exclusao_solicitada_em is not null and excluido_em is null
      and exclusao_solicitada_em <= now() - make_interval(days => public.cfg_num('dias_exclusao_conta', 30)::int)
  loop
    n := n + 1;
    -- Arquivos enviados (foto, documentos, portfólio, fotos de avaliação).
    begin
      delete from storage.objects where (storage.foldername(name))[1] = r.id::text;
    exception when others then null;  -- se o Storage recusar o SQL direto, os registros abaixo saem de qualquer forma
    end;
    begin
      delete from auth.users where id = r.id;
    exception when foreign_key_violation then
      delete from public.enderecos where usuario_id = r.id;
      delete from public.favoritos where cliente_id = r.id or profissional_id = r.id;
      delete from public.notificacoes where usuario_id = r.id;
      delete from public.dispositivos where usuario_id = r.id;
      delete from public.pontos where usuario_id = r.id;
      delete from public.indicacoes where indicado_id = r.id or indicador_id = r.id;
      delete from public.documentos where profissional_id = r.id;
      delete from public.certificacoes where profissional_id = r.id;
      delete from public.portfolio where profissional_id = r.id;
      delete from public.profissional_especialidades where profissional_id = r.id;
      delete from public.profissional_profissoes where profissional_id = r.id;
      update public.profissionais set status = 'suspenso', disponivel = false, bio = null, area_centro = null,
        motivo_status = 'Conta excluída' where id = r.id;
      update public.perfis set nome = 'Conta excluída', email = null, telefone = null, cpf = null, nascimento = null,
        foto_url = null, e_cliente = false, e_profissional = false, excluido_em = now() where id = r.id;
      update public.mensagens set texto = 'Mensagem apagada' where autor_id = r.id;
      -- Login desativado para sempre.
      update auth.users set email = null, encrypted_password = '', raw_user_meta_data = '{}'::jsonb where id = r.id;
      begin
        execute 'update auth.users set phone = null, banned_until = ''infinity'' where id = $1' using r.id;
      exception when undefined_column then null;
      end;
      begin
        execute 'delete from auth.identities where user_id = $1' using r.id;
        execute 'delete from auth.sessions where user_id = $1' using r.id;
      exception when undefined_table then null;
      end;
    end;
  end loop;
  return n;
end;
$$;

revoke all on function public.excluir_contas_vencidas() from public, anon, authenticated;
revoke all on function public.solicitar_exclusao_conta(text) from public, anon;
revoke all on function public.cancelar_exclusao_conta() from public, anon;
grant execute on function public.solicitar_exclusao_conta(text) to authenticated;
grant execute on function public.cancelar_exclusao_conta() to authenticated;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    perform cron.schedule('iservice-excluir-contas', '0 6 * * *', 'select public.excluir_contas_vencidas()');
  end if;
end;
$$;
