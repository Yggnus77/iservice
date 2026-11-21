-- Assistente automático no chat do suporte (pedido de 21/11/2026).
--
-- O assistente responde pelo app usando as perguntas da Central de Ajuda (editadas no
-- painel). As "palavras" de cada pergunta são outros jeitos de a pessoa perguntar a mesma
-- coisa, para o assistente reconhecer. Se não resolver, a dúvida vai para a equipe.

alter table public.ajuda_perguntas add column if not exists palavras text not null default ''
  check (char_length(palavras) <= 400);

-- Painel: salvar as palavras de uma pergunta (mesma permissão de editar a Central de Ajuda).
create or replace function public.admin_palavras_pergunta(p_id bigint, p_palavras text)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  perform public.exigir_permissao('comunicados');
  update public.ajuda_perguntas
     set palavras = left(regexp_replace(btrim(coalesce(p_palavras, '')), '\s+', ' ', 'g'), 400), atualizada_em = now()
   where id = p_id;
  if not found then perform public.erro('nao_encontrado', 'Pergunta não encontrada.'); end if;
end;
$$;
revoke all on function public.admin_palavras_pergunta(bigint, text) from public, anon;
grant execute on function public.admin_palavras_pergunta(bigint, text) to authenticated;

-- O canal de atendimento agora inclui o chat do app.
update public.ajuda_perguntas
   set resposta = 'Pelo chat aqui no app: em Perfil, toque em "Falar com o suporte". Primeiro o assistente tenta responder; se não resolver, uma pessoa da equipe continua a conversa. Também atendemos pelo e-mail suporte@iservice.app.br. Emergências durante um serviço têm atendimento 24 horas pelo botão de emergência no pedido.',
       atualizada_em = now()
 where pergunta = 'Como falo com o suporte do iService?' and resposta like 'Pelo WhatsApp do iService%';

-- Perguntas novas que aparecem muito em atendimento.
insert into public.ajuda_perguntas (publico, categoria, pergunta, resposta, ordem)
select v.* from (values
  ('cliente', 'Pedidos', 'Como cancelo um pedido?',
   'Abra o pedido em Pedidos e toque em "Cancelar pedido" (ou "Cancelar agendamento"). Dá para cancelar enquanto o profissional ainda não começou o serviço.', 35),
  ('cliente', 'Pedidos', 'Como avalio o profissional?',
   'Depois que o serviço é concluído, abra o pedido em Pedidos e toque em "Avaliar". A sua avaliação ajuda outros clientes e deixa os melhores profissionais no topo.', 36),
  ('todos', 'Conta', 'Esqueci minha senha. O que faço?',
   'Na tela de entrar, toque em "Esqueci minha senha" e digite o seu e-mail. Chega um link para você criar uma senha nova. Confira também a caixa de spam.', 85),
  ('todos', 'Conta', 'Como mudo meus dados?',
   'Vá em Perfil e toque em "Meus dados". Ali você confere e atualiza nome, telefone e e-mail. Clientes mudam os endereços em Perfil, "Meus endereços".', 86),
  ('profissional', 'Pagamento', 'Como mudo o meu preço?',
   'Vá em Perfil e toque em "Especialidades e preços". Mude o valor e salve: o novo preço já aparece para os clientes.', 55),
  ('profissional', 'Cadastro', 'Como atualizo minhas certidões e documentos?',
   'Vá em Perfil e toque em "Documentos e certidões". Envie o arquivo novo; a equipe confere e o app avisa quando estiver aprovado. Avisamos antes de uma certidão vencer.', 25)
) as v(publico, categoria, pergunta, resposta, ordem)
where not exists (select 1 from public.ajuda_perguntas a where a.pergunta = v.pergunta);

-- Outros jeitos de perguntar (só onde ainda não há palavras).
update public.ajuda_perguntas a set palavras = v.palavras
from (values
  ('Como peço um serviço?', 'pedir, contratar, solicitar, chamar profissional, como funciona, encontrar, procurar, achar'),
  ('O profissional não respondeu. E agora?', 'não respondeu, sem resposta, demora, demorando, não aceitou, ninguém respondeu, esperando'),
  ('Posso agendar para outro dia?', 'agendar, agenda, marcar, outro dia, amanhã, horário, data'),
  ('Quanto custa o serviço?', 'preço, valor, custo, caro, quanto, cobra, orçamento, taxa'),
  ('Os profissionais são conferidos?', 'confiável, seguro, segurança, verificado, antecedentes, conferido, confiança'),
  ('O que faço numa emergência durante o serviço?', 'emergência, socorro, perigo, ameaça, assalto, agressão, acidente, polícia, urgente'),
  ('O serviço não ficou bom. Como reclamo?', 'reclamar, reclamação, ruim, mal feito, garantia, problema, estragou, defeito, refazer, devolver, reembolso'),
  ('Como excluo a minha conta?', 'excluir, apagar, deletar, cancelar conta, encerrar conta, sair do app'),
  ('Quanto tempo leva a análise do cadastro?', 'análise, aprovação, aprovar, aprovado, demora, cadastro pendente, em análise, liberar perfil'),
  ('Por que preciso enviar antecedentes criminais?', 'antecedentes, certidão, criminal, polícia federal, tjdft, documento'),
  ('Como recebo pedidos?', 'receber pedidos, clientes, chamados, disponível, online, ficar disponível, trabalho'),
  ('Como apareço mais no topo?', 'ranking, topo, aparecer, destaque, mais pedidos, primeiro lugar, visibilidade'),
  ('Quem define o meu preço?', 'preço, valor, cobrar, quanto cobrar'),
  ('Como recebo pelos serviços?', 'receber, pagamento, dinheiro, pix, conta bancária, repasse, saque'),
  ('Tive um problema com um cliente. O que faço?', 'problema cliente, denunciar, denúncia, cliente grosso, ameaça, calote, não pagou'),
  ('Como falo com o suporte do iService?', 'atendente, pessoa, humano, falar com alguém, suporte, contato, telefone, whatsapp, e-mail'),
  ('Como cancelo um pedido?', 'cancelar, cancelamento, desistir, desmarcar'),
  ('Como avalio o profissional?', 'avaliar, avaliação, nota, estrelas, comentário'),
  ('Esqueci minha senha. O que faço?', 'senha, esqueci, não consigo entrar, login, acessar, redefinir'),
  ('Como mudo meus dados?', 'alterar, mudar, trocar, atualizar, telefone, e-mail, nome, endereço, dados'),
  ('Como mudo o meu preço?', 'mudar preço, alterar valor, aumentar, diminuir, tabela'),
  ('Como atualizo minhas certidões e documentos?', 'certidão vencida, vencendo, renovar, documento, enviar de novo, atualizar documento')
) as v(pergunta, palavras)
where a.pergunta = v.pergunta and a.palavras = '';
