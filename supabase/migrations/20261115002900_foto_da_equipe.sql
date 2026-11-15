-- Foto de perfil da equipe no painel (15/11/2026)
--
-- Cada pessoa da equipe já pode trocar a própria foto pelo painel sem nada novo no
-- banco (envia para fotos/<seu id>/ e grava em perfis.foto_url, como nos apps).
-- Este arquivo libera uma coisa a mais: alguém da equipe colocar ou trocar a foto
-- de um colega do suporte, por exemplo de quem ainda não sabe fazer sozinho.
--
-- Regras (mesmo cuidado da auditoria de 10/11/2026):
--  * O Storage só ganha permissão de ENVIAR arquivo novo, no bucket "fotos", na
--    pasta de quem está na equipe. Ninguém sobrescreve nem apaga o arquivo de outro.
--  * A foto do dono só o próprio dono troca.
--  * A foto tem que estar na pasta da própria pessoa (regra perfis_foto_do_iservice).
--  * Fica no Registro da equipe com o nome de quem trocou.
--
-- Pode rodar mais de uma vez.

-- Quem pode receber foto enviada por outra pessoa da equipe (p_pasta = id da pessoa,
-- que é o nome da pasta no Storage).
drop function if exists public.pode_trocar_foto_equipe(uuid);
create or replace function public.pode_trocar_foto_equipe(p_pasta text)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select p_pasta is not null
    and public.e_admin()
    and exists (
      select 1 from public.equipe e
      where e.usuario_id is not null
        and e.usuario_id::text = p_pasta
        and (e.papel <> 'dono' or e.usuario_id = auth.uid())
    )
$$;
revoke all on function public.pode_trocar_foto_equipe(text) from public, anon;
grant execute on function public.pode_trocar_foto_equipe(text) to authenticated;

do $$
begin
  if to_regclass('storage.objects') is null then return; end if;
  execute 'drop policy if exists "fotos: equipe envia foto de colega" on storage.objects';
  execute $p$create policy "fotos: equipe envia foto de colega" on storage.objects for insert to authenticated
    with check (
      bucket_id = 'fotos'
      and public.pode_trocar_foto_equipe((storage.foldername(name))[1])
    )$p$;
end;
$$;

-- Grava (ou tira, com p_foto nulo) a foto de alguém da equipe.
create or replace function public.admin_foto_equipe(p_usuario uuid, p_foto text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v public.equipe;
  v_foto text := nullif(btrim(coalesce(p_foto, '')), '');
begin
  perform public.exigir_admin();
  select * into v from public.equipe where usuario_id = p_usuario;
  if v.email is null then
    perform public.erro('nao_encontrado', 'Esta pessoa não está na equipe ou ainda não fez o primeiro acesso.');
  end if;
  if v.papel = 'dono' and p_usuario <> auth.uid() then
    perform public.erro('dono', 'Só o dono do painel troca a própria foto.');
  end if;
  if v_foto is not null and not public.arquivo_do_usuario(v_foto, 'fotos', p_usuario) then
    perform public.erro('foto_invalida', 'A foto precisa ser enviada pelo painel. Escolha a imagem de novo.');
  end if;

  update public.perfis set foto_url = v_foto where id = p_usuario;

  perform public.registrar_acao(case when v_foto is null then 'remover_foto_equipe' else 'foto_equipe' end,
    p_usuario::text, jsonb_build_object('nome', v.nome, 'email', v.email));
end;
$$;
revoke all on function public.admin_foto_equipe(uuid, text) from public, anon;
grant execute on function public.admin_foto_equipe(uuid, text) to authenticated;
