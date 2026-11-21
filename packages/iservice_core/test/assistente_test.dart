import 'package:flutter_test/flutter_test.dart';
import 'package:iservice_core/iservice_core.dart';

// Perguntas da Central de Ajuda como estão no banco (21/11/2026).
const faq = [
  PerguntaAjuda(categoria: 'Pedidos', pergunta: 'Como peço um serviço?', resposta: 'Na tela Início, escolha a profissão. O mapa mostra os profissionais perto de você, com nota, preço médio e tempo de resposta. Abra o perfil, toque em "Pedir" e descreva o que precisa. O pedido vai só para o profissional que você escolheu.', palavras: 'pedir, contratar, solicitar, chamar profissional, como funciona, encontrar, procurar, achar'),
  PerguntaAjuda(categoria: 'Cadastro', pergunta: 'Quanto tempo leva a análise do cadastro?', resposta: 'Até 2 dias úteis depois que você envia tudo. Se faltar algo, avisamos pelo app e por e-mail o que precisa corrigir.', palavras: 'análise, aprovação, aprovar, aprovado, demora, cadastro pendente, em análise, liberar perfil'),
  PerguntaAjuda(categoria: 'Pedidos', pergunta: 'O profissional não respondeu. E agora?', resposta: 'Cada profissional tem 5 minutos para responder. Se o prazo passar, toque em "Pedir a outro profissional" e o app mostra os próximos mais bem avaliados perto de você.', palavras: 'não respondeu, sem resposta, demora, demorando, não aceitou, ninguém respondeu, esperando'),
  PerguntaAjuda(categoria: 'Cadastro', pergunta: 'Por que preciso enviar antecedentes criminais?', resposta: 'Você entra na casa das pessoas, e a certidão é o que dá confiança ao cliente. As certidões da Polícia Federal e do TJDFT são gratuitas e saem pela internet em poucos minutos. Valem 12 meses; avisamos antes de vencer.', palavras: 'antecedentes, certidão, criminal, polícia federal, tjdft, documento'),
  PerguntaAjuda(categoria: 'Cadastro', pergunta: 'Como atualizo minhas certidões e documentos?', resposta: 'Vá em Perfil e toque em "Documentos e certidões". Envie o arquivo novo; a equipe confere e o app avisa quando estiver aprovado. Avisamos antes de uma certidão vencer.', palavras: 'certidão vencida, vencendo, renovar, documento, enviar de novo, atualizar documento'),
  PerguntaAjuda(categoria: 'Pedidos', pergunta: 'Posso agendar para outro dia?', resposta: 'Sim. Você pode agendar para até 7 dias à frente. O profissional confirma o horário ou sugere outro, e os dois recebem um lembrete na véspera.', palavras: 'agendar, agenda, marcar, outro dia, amanhã, horário, data'),
  PerguntaAjuda(categoria: 'Pedidos', pergunta: 'Como recebo pedidos?', resposta: 'Ative o modo disponível na tela Início. Os clientes perto de você veem o seu perfil, e cada pedido chega só para você. Responda em até 5 minutos: quem responde rápido aparece mais no ranking.', palavras: 'receber pedidos, clientes, chamados, disponível, online, ficar disponível, trabalho'),
  PerguntaAjuda(categoria: 'Pedidos', pergunta: 'Como cancelo um pedido?', resposta: 'Abra o pedido em Pedidos e toque em "Cancelar pedido" (ou "Cancelar agendamento"). Dá para cancelar enquanto o profissional ainda não começou o serviço.', palavras: 'cancelar, cancelamento, desistir, desmarcar'),
  PerguntaAjuda(categoria: 'Pedidos', pergunta: 'Como avalio o profissional?', resposta: 'Depois que o serviço é concluído, abra o pedido em Pedidos e toque em "Avaliar". A sua avaliação ajuda outros clientes e deixa os melhores profissionais no topo.', palavras: 'avaliar, avaliação, nota, estrelas, comentário'),
  PerguntaAjuda(categoria: 'Pagamento', pergunta: 'Quanto custa o serviço?', resposta: 'O preço é definido pelo profissional e aparece no perfil dele, com a faixa de preço da sua região para você comparar. Ao valor do serviço soma-se a taxa de serviço de 10%. A partir de 5 de janeiro de 2027, você paga pelo app, com Pix ou cartão, e o valor só vai para o profissional depois do serviço concluído. Nunca pague por fora do app.', palavras: 'preço, valor, custo, caro, quanto, cobra, orçamento, taxa'),
  PerguntaAjuda(categoria: 'Pedidos', pergunta: 'Como apareço mais no topo?', resposta: 'O ranking considera principalmente as suas avaliações, e também o tempo de resposta. Atenda bem, responda rápido e mantenha o perfil completo, com fotos dos seus trabalhos.', palavras: 'ranking, topo, aparecer, destaque, mais pedidos, primeiro lugar, visibilidade'),
  PerguntaAjuda(categoria: 'Segurança', pergunta: 'Os profissionais são conferidos?', resposta: 'Sim. Todo profissional envia documento com foto, selfie e certidões de antecedentes criminais (Polícia Federal e Justiça do DF). Uma pessoa da equipe confere tudo antes de liberar o perfil.', palavras: 'confiável, seguro, segurança, verificado, antecedentes, conferido, confiança'),
  PerguntaAjuda(categoria: 'Pagamento', pergunta: 'Quem define o meu preço?', resposta: 'Você. Informe o valor médio por serviço ou por diária no seu perfil, a partir do mínimo da sua região. Você recebe 100% desse valor: a taxa de serviço de 10% é paga pelo cliente, e não há cobrança por pedido.', palavras: 'preço, valor, cobrar, quanto cobrar'),
  PerguntaAjuda(categoria: 'Pagamento', pergunta: 'Como recebo pelos serviços?', resposta: 'A partir de 5 de janeiro de 2027, o cliente paga pelo app logo depois que você aceita o pedido. O valor fica guardado e, quando você conclui o serviço, cai inteiro na sua conta de recebimento, no seu nome e CPF. Ative a conta em Ganhos > Recebimentos, enviando documento e selfie. Depois, você saca por Pix.', palavras: 'receber, pagamento, dinheiro, pix, conta bancária, repasse, saque'),
  PerguntaAjuda(categoria: 'Pagamento', pergunta: 'Como mudo o meu preço?', resposta: 'Vá em Perfil e toque em "Especialidades e preços". Mude o valor e salve: o novo preço já aparece para os clientes.', palavras: 'mudar preço, alterar valor, aumentar, diminuir, tabela'),
  PerguntaAjuda(categoria: 'Segurança', pergunta: 'O que faço numa emergência durante o serviço?', resposta: 'No acompanhamento do pedido, toque no botão de emergência. A equipe do iService é avisada na hora e liga para você. Se houver risco, ligue para o 190 (polícia) ou 192 (SAMU).', palavras: 'emergência, socorro, perigo, ameaça, assalto, agressão, acidente, polícia, urgente'),
  PerguntaAjuda(categoria: 'Segurança', pergunta: 'Tive um problema com um cliente. O que faço?', resposta: 'Se houver risco, use o botão de emergência no pedido ou ligue para o 190. Depois, denuncie o cliente pelo menu do pedido. A equipe analisa toda denúncia.', palavras: 'problema cliente, denunciar, denúncia, cliente grosso, ameaça, calote, não pagou'),
  PerguntaAjuda(categoria: 'Garantia', pergunta: 'O serviço não ficou bom. Como reclamo?', resposta: 'Você tem a Garantia iService de 30 dias depois do serviço concluído. Abra o pedido e toque em "Abrir reclamação". A nossa equipe conversa com você e com o profissional para resolver.', palavras: 'reclamar, reclamação, ruim, mal feito, garantia, problema, estragou, defeito, refazer, devolver, reembolso'),
  PerguntaAjuda(categoria: 'Conta', pergunta: 'Como excluo a minha conta?', resposta: 'Vá em Perfil, Conta e dados, Excluir conta. Seus dados são apagados conforme a nossa Política de Privacidade.', palavras: 'excluir, apagar, deletar, cancelar conta, encerrar conta, sair do app'),
  PerguntaAjuda(categoria: 'Conta', pergunta: 'Esqueci minha senha. O que faço?', resposta: 'Na tela de entrar, toque em "Esqueci minha senha" e digite o seu e-mail. Chega um link para você criar uma senha nova. Confira também a caixa de spam.', palavras: 'senha, esqueci, não consigo entrar, login, acessar, redefinir'),
  PerguntaAjuda(categoria: 'Conta', pergunta: 'Como mudo meus dados?', resposta: 'Vá em Perfil e toque em "Meus dados". Ali você confere e atualiza nome, telefone e e-mail. Clientes mudam os endereços em Perfil, "Meus endereços".', palavras: 'alterar, mudar, trocar, atualizar, telefone, e-mail, nome, endereço, dados'),
  PerguntaAjuda(categoria: 'Atendimento', pergunta: 'Como falo com o suporte do iService?', resposta: 'Pelo chat aqui no app: em Perfil, toque em "Falar com o suporte". Primeiro o assistente tenta responder; se não resolver, uma pessoa da equipe continua a conversa. Também atendemos pelo e-mail suporte@iservice.app.br. Emergências durante um serviço têm atendimento 24 horas pelo botão de emergência no pedido.', palavras: 'atendente, pessoa, humano, falar com alguém, suporte, contato, telefone, whatsapp, e-mail'),
];

void main() {
  test('acha a pergunta certa por outros jeitos de perguntar', () {
    expect(responderAssistente('quero cancelar meu pedido', faq).melhor?.pergunta, 'Como cancelo um pedido?');
    expect(responderAssistente('esqueci a senha', faq).melhor?.pergunta, 'Esqueci minha senha. O que faço?');
    expect(responderAssistente('não consigo entrar na minha conta', faq).melhor?.pergunta, 'Esqueci minha senha. O que faço?');
    expect(responderAssistente('o profissional não respondeu ainda', faq).melhor?.pergunta, 'O profissional não respondeu. E agora?');
    expect(responderAssistente('quanto custa?', faq).melhor?.pergunta, 'Quanto custa o serviço?');
    expect(responderAssistente('o serviço ficou mal feito, quero reclamar', faq).melhor?.pergunta, 'O serviço não ficou bom. Como reclamo?');
    expect(responderAssistente('como faço para apagar minha conta', faq).melhor?.pergunta, 'Como excluo a minha conta?');
    expect(responderAssistente('meu cadastro está em análise há dias', faq).melhor?.pergunta, 'Quanto tempo leva a análise do cadastro?');
    expect(responderAssistente('como mudo meu telefone', faq).melhor?.pergunta, 'Como mudo meus dados?');
    expect(responderAssistente('dá pra marcar pra amanhã?', faq).melhor?.pergunta, 'Posso agendar para outro dia?');
    expect(responderAssistente('como avaliar o eletricista', faq).melhor?.pergunta, 'Como avalio o profissional?');
    expect(responderAssistente('minha certidão venceu', faq).melhor?.pergunta, 'Como atualizo minhas certidões e documentos?');
  });

  test('entende saudação, agradecimento, pedido de pessoa e emergência', () {
    expect(responderAssistente('oi, boa noite', faq).intencao, IntencaoAssistente.saudacao);
    expect(responderAssistente('obrigado!', faq).intencao, IntencaoAssistente.agradecimento);
    expect(responderAssistente('quero falar com um atendente', faq).intencao, IntencaoAssistente.falarComPessoa);
    final e = responderAssistente('socorro, o profissional me ameaçou', faq);
    expect(e.intencao, IntencaoAssistente.emergencia);
    expect(e.melhor?.pergunta, 'O que faço numa emergência durante o serviço?');
  });

  test('sem resposta pronta, não inventa', () {
    expect(responderAssistente('meu cachorro fugiu ontem', faq).melhor, isNull);
  });
}
