import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iservice_core/iservice_core.dart';

import 'estado.dart';
import 'telas/agenda.dart';
import 'telas/analise.dart';
import 'telas/atendimento.dart';
import 'telas/boas_vindas.dart';
import 'telas/cadastro.dart';
import 'telas/ganhos.dart';
import 'telas/painel.dart';
import 'telas/perfil.dart';
import 'telas/shell.dart';
import 'telas/solicitacoes.dart';

class _Atualizador extends ChangeNotifier {
  _Atualizador(Ref ref) {
    ref.listen(sessaoProvider, (_, _) => notifyListeners());
    ref.listen(meuPerfilProvider, (_, _) => notifyListeners());
    ref.listen(pendenciasProvider, (_, _) => notifyListeners());
  }
}

const _rotasPublicas = ['/boas-vindas', '/entrar', '/cadastro', '/confirmar-email'];

final rotasProvider = Provider<GoRouter>((ref) {
  final atualizador = _Atualizador(ref);
  ref.onDispose(atualizador.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: atualizador,
    redirect: (context, estado) {
      final local = estado.matchedLocation;
      final publica = _rotasPublicas.any(local.startsWith);
      final sessao = ref.read(sessaoProvider);
      if (sessao.isLoading) return local == '/' ? null : '/';
      if (sessao.value == null) return publica ? null : '/boas-vindas';

      final perfil = ref.read(meuPerfilProvider);
      if (perfil.isLoading && !perfil.hasValue) return local == '/' ? null : '/';
      final p = perfil.value;
      if (p == null) return null;

      final pro = p.profissional;
      // Conta criada no app Cliente: começa o cadastro de profissional do passo 1.
      if (pro == null) return local.startsWith('/cadastro') ? null : '/cadastro/1';
      switch (pro.status) {
        case StatusCadastro.rascunho || StatusCadastro.recusado:
          if (local.startsWith('/cadastro') || local == '/analise') return null;
          final pend = ref.read(pendenciasProvider);
          if (!pend.hasValue) return local == '/' ? null : '/';
          return pro.status == StatusCadastro.recusado ? '/analise' : '/cadastro/${passoPendente(pend.value!)}';
        case StatusCadastro.emAnalise || StatusCadastro.suspenso:
          return local == '/analise' ? null : '/analise';
        case StatusCadastro.aprovado:
          if (publica || local == '/' || local == '/analise') return '/inicio';
          return null;
      }
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const TelaAbertura()),
      GoRoute(path: '/boas-vindas', builder: (_, _) => const TelaBoasVindas()),
      GoRoute(
        path: '/entrar',
        builder: (context, _) => TelaEntrar(aoCriarConta: () => context.push('/cadastro/1'), aoEntrar: () => context.go('/')),
      ),
      GoRoute(path: '/cadastro/:passo', builder: (_, e) => TelaCadastro(passo: int.parse(e.pathParameters['passo']!))),
      GoRoute(
        path: '/confirmar-email',
        builder: (context, e) => TelaConfirmarEmail(email: e.uri.queryParameters['email'] ?? '', aoIrParaEntrar: () => context.go('/entrar')),
      ),
      GoRoute(path: '/analise', builder: (_, _) => const TelaAnalise()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, nav) => ShellProfissional(nav: nav),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/inicio', builder: (_, _) => const TelaPainel())]),
          StatefulShellBranch(routes: [GoRoute(path: '/solicitacoes', builder: (_, _) => const TelaSolicitacoes())]),
          StatefulShellBranch(routes: [GoRoute(path: '/agenda', builder: (_, _) => const TelaAgenda())]),
          StatefulShellBranch(routes: [GoRoute(path: '/ganhos', builder: (_, _) => const TelaGanhos())]),
          StatefulShellBranch(routes: [GoRoute(path: '/perfil', builder: (_, _) => const TelaPerfilPro())]),
        ],
      ),
      GoRoute(path: '/pedido/:id', builder: (_, e) => TelaAtendimento(pedidoId: e.pathParameters['id']!)),
      GoRoute(
        path: '/pedido/:id/chat',
        builder: (_, e) => TelaChat(
          pedidoId: e.pathParameters['id']!,
          nomeOutro: e.uri.queryParameters['nome'] ?? '',
          fotoOutro: e.uri.queryParameters['foto'],
          subtitulo: e.uri.queryParameters['sub'],
        ),
      ),
      GoRoute(path: '/notificacoes', builder: (context, _) => TelaNotificacoes(aoAbrirPedido: (id) => context.push('/pedido/$id'))),
    ],
  );
});
