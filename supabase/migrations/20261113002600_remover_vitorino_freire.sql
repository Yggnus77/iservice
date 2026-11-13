-- Fim da fase de testes em Vitorino Freire (MA), decisão de 13/11/2026.
-- O iService atende só Brasília e o Entorno até novas expansões.
-- Antes de apagar a região, desliga qualquer registro que ainda aponte para ela
-- (as chaves estrangeiras não apagam em cascata).
update public.pedidos       set regiao_id = null where regiao_id = 'vitorino-freire';
update public.enderecos     set regiao_id = null where regiao_id = 'vitorino-freire';
update public.profissionais set regiao_id = null where regiao_id = 'vitorino-freire';
update public.buscas        set regiao_id = null where regiao_id = 'vitorino-freire';
update public.comunicados   set regiao_id = null where regiao_id = 'vitorino-freire';
delete from public.regioes where id = 'vitorino-freire';
