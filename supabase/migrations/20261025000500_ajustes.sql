-- Ajustes apontados pelo verificador de segurança do Supabase.
alter function public.erro(text, text) set search_path = public;
alter function public.tocar_atualizado_em() set search_path = public;

-- Links de acompanhamento só são lidos por acompanhamento_publico() (security definer);
-- deixa explícito que ninguém lê a tabela direto.
create policy "compartilhamentos: sem acesso direto" on public.compartilhamentos for select to authenticated using (false);
