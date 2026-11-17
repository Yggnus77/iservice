# Teste no iPhone (Safari)

Workflow `.github/workflows/teste-iphone.yml` (aba Actions > "Teste no iPhone (Safari)" > Run workflow).

- **webkit**: motor do Safari com tela, toque e navegador de iPhone 15. No site publicado vai do
  cadastro até a tela de e-mail e senha, sem criar conta. Depois abre a versão de demonstração
  (dados de exemplo, sem banco) para mapa, pedido, chat, avaliação com foto, agenda e ganhos.
  Gera `relatorio.txt` com erros, bloqueios da política de segurança e o que havia na tela.
- **simulador**: Safari de verdade no simulador de iPhone do Xcode (Mac do GitHub).
- **juntar**: em ramos `claude/**`, grava as capturas em `capturas-teste-iphone/` no próprio ramo.
  Apague a pasta antes de mesclar.
