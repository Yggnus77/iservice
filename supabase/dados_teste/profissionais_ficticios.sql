-- Profissionais fictícios para testar o app (brief do MVP, Fase 1).
-- NÃO é migração: rode à mão no SQL Editor só enquanto estiver testando.
--
-- Cria 90 profissionais (5 por profissão, menos Babá, que exige antecedentes de
-- verdade) espalhados pelas regiões do DF e do Entorno, aprovados, verificados e
-- disponíveis. Um em cada três marca "Atendo 24h". Todos usam e-mail
-- @teste.iservice.app.br, não recebem e-mail nem push e não conseguem entrar
-- no app (sem senha).
--
-- Rodar de novo apaga os fictícios antigos e cria tudo outra vez.
-- Para APAGAR antes do lançamento, rode só o bloco "Apagar" lá embaixo.

-- Apagar (também roda antes de criar). Pedidos de teste feitos com eles são
-- apagados junto, para a exclusão não travar.
delete from public.pedidos where profissional_id in (select id from auth.users where email like '%@teste.iservice.app.br');
delete from auth.users where email like '%@teste.iservice.app.br';

do $$
declare
  v_nomes text[] := array['Carlos','Mariana','José','Ana Paula','Rafael','Juliana','Pedro','Fernanda','Lucas','Beatriz',
    'Thiago','Camila','Bruno','Larissa','Gustavo','Patrícia','Diego','Aline','Marcos','Renata','Felipe','Tatiane',
    'André','Priscila','Leandro','Vanessa','Rodrigo','Simone','Eduardo','Daniela'];
  v_sobrenomes text[] := array['Souza','Alves','Ribeiro','Lima','Costa','Martins','Santos','Rocha','Pereira','Gomes',
    'Nunes','Dias','Teixeira','Melo','Araújo','Freitas','Barros','Cardoso','Moreira','Batista'];
  v_prof record;
  v_reg record;
  v_regioes text[];
  v_id uuid;
  v_n int := 0;
  v_k int;
  v_nota numeric;
  v_aval int;
begin
  select array_agg(id order by ordem) into v_regioes from public.regioes where centro is not null;

  for v_prof in select id, nome, preco_base from public.profissoes where ativa and not exige_antecedentes order by ordem loop
    for v_k in 1..5 loop
      v_n := v_n + 1;
      v_id := gen_random_uuid();
      select id, nome, centro into v_reg from public.regioes where id = v_regioes[1 + (v_n * 7) % array_length(v_regioes, 1)];
      v_aval := (v_n * 13) % 40;                         -- 0 a 39 avaliações (alguns "novos")
      v_nota := round((4.2 + ((v_n * 37) % 80) / 100.0)::numeric, 2);   -- 4,20 a 4,99

      insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, phone,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
      values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
        'profissional' || v_n || '@teste.iservice.app.br', '', now(), '5561990' || lpad(v_n::text, 6, '0'),
        '{"provider":"email","providers":["email"]}'::jsonb,
        jsonb_build_object('nome', v_nomes[1 + v_n % 30] || ' ' || v_sobrenomes[1 + (v_n * 3) % 20], 'app', 'cliente'),
        now(), now());

      update public.perfis set e_profissional = true, telefone_verificado = true where id = v_id;

      insert into public.profissionais (id, status, verificado, disponivel, atende_24h, bio, anos_experiencia,
        area_centro, area_raio_km, regiao_id, nota_media, total_avaliacoes, servicos_concluidos, aprovado_em)
      values (v_id, 'aprovado', true, true, v_n % 3 = 0,
        'Perfil de teste. ' || v_prof.nome || ' com atendimento em ' || v_reg.nome || '.',
        2 + v_n % 18,
        -- até ~3 km do centro da região, para não empilhar todos no mesmo ponto
        public.ponto(extensions.st_y(v_reg.centro::extensions.geometry) + (((v_n * 17) % 60) - 30) / 1000.0,
                     extensions.st_x(v_reg.centro::extensions.geometry) + (((v_n * 29) % 60) - 30) / 1000.0),
        35, v_reg.id,
        case when v_aval = 0 then 0 else v_nota end, v_aval, v_aval + (v_n % 9), now());

      insert into public.profissional_profissoes (profissional_id, profissao_id, principal) values (v_id, v_prof.id, true);

      -- 3 especialidades com preço perto do preço base (80% a 140%)
      insert into public.profissional_especialidades (profissional_id, especialidade_id, preco)
      select v_id, e.id, round(v_prof.preco_base * (0.8 + ((v_n + e.ordem) * 11 % 60) / 100.0))
      from public.especialidades e
      where e.profissao_id = v_prof.id and e.aprovada
      order by (e.ordem + v_k) % 5, e.id
      limit 3;
    end loop;
  end loop;

  raise notice 'Criados % profissionais fictícios.', v_n;
end $$;

-- Conferir: quantos por profissão e quantos atendem 24h.
select pp.profissao_id, count(*) as profissionais, count(*) filter (where pr.atende_24h) as atendem_24h
from public.profissionais pr
join auth.users u on u.id = pr.id and u.email like '%@teste.iservice.app.br'
join public.profissional_profissoes pp on pp.profissional_id = pr.id
group by 1 order by 1;
