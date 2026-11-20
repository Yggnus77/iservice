-- Central de Ajuda: textos do pagamento pelo app e da taxa de serviço (pagamento ligado em 05/01/2027).
update public.ajuda_perguntas set resposta =
  'O preço é definido pelo profissional e aparece no perfil dele, com a faixa de preço da sua região para você comparar. Ao valor do serviço soma-se a taxa de serviço de 10%. A partir de 5 de janeiro de 2027, você paga pelo app, com Pix ou cartão, e o valor só vai para o profissional depois do serviço concluído. Nunca pague por fora do app.',
  atualizada_em = now()
where publico = 'cliente' and pergunta = 'Quanto custa o serviço?';

update public.ajuda_perguntas set resposta =
  'Você. Informe o valor médio por serviço ou por diária no seu perfil, a partir do mínimo da sua região. Você recebe 100% desse valor: a taxa de serviço de 10% é paga pelo cliente, e não existe mensalidade.',
  atualizada_em = now()
where publico = 'profissional' and pergunta = 'Quem define o meu preço?';

insert into public.ajuda_perguntas (publico, categoria, pergunta, resposta, ordem)
select 'profissional', 'Pagamento', 'Como recebo pelos serviços?',
  'A partir de 5 de janeiro de 2027, o cliente paga pelo app logo depois que você aceita o pedido. O valor fica guardado e, quando você conclui o serviço, cai inteiro na sua conta de recebimento, no seu nome e CPF. Ative a conta em Ganhos > Recebimentos, enviando documento e selfie. Depois, você saca por Pix.', 55
where not exists (select 1 from public.ajuda_perguntas where pergunta = 'Como recebo pelos serviços?');
