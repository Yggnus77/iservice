import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iservice_core/iservice_core.dart';

import 'telas/acompanhar.dart';
import 'telas/avaliar.dart';
import 'telas/boas_vindas.dart';
import 'telas/busca.dart';
import 'telas/cadastro.dart';
import 'telas/enderecos.dart';
import 'telas/explorar.dart';
import 'telas/favoritos.dart';
import 'telas/inicio.dart';
import 'telas/lista_profissionais.dart';
import 'telas/pedidos.dart';
import 'telas/perfil.dart';
import 'telas/perfil_profissional.dart';
import 'telas/ranking.dart';
import 'telas/shell.dart';
import 'telas/solicitar.dart';

/// Atualiza as rotas quando o login ou o perfil mudam.
class _Atualizador extends ChangeNotifier {
  _Atualizador(Ref ref) {
    ref.listen(sessaoProvider, (_, _) => notifyListeners());
    ref.listen(meuPerfilProvider, (_, _) => notifyListeners());
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

      // Logado mas sem cadastro completo: volta ao passo que falta.
      if (!p.eCliente) {
        if (local.startsWith('/cadastro')) return null;
        final dadosOk = p.cpf != null && p.nascimento != null && p.telefone != null;
        if (!dadosOk) return '/cadastro/1';
        if (p.enderecos.isEmpty) return '/cadastro/2';
        return '/cadastro/4';
      }
      if (publica || local == '/') return '/inicio';
      return null;
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
      StatefulShellRoute.indexedStack(
        builder: (_, _, nav) => ShellCliente(nav: nav),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/inicio', builder: (_, _) => const TelaInicio())]),
          StatefulShellBranch(routes: [GoRoute(path: '/explorar', builder: (_, _) => const TelaExplorar())]),
          StatefulShellBranch(routes: [GoRoute(path: '/pedidos', builder: (_, _) => const TelaPedidos())]),
          StatefulShellBranch(routes: [GoRoute(path: '/favoritos', builder: (_, _) => const TelaFavoritos())]),
          StatefulShellBranch(routes: [GoRoute(path: '/perfil', builder: (_, _) => const TelaPerfil())]),
        ],
      ),
      GoRoute(path: '/busca', builder: (_, _) => const TelaBusca()),
      GoRoute(path: '/ranking', builder: (_, e) => TelaRanking(profissaoId: e.uri.queryParameters['profissao'])),
      GoRoute(
        path: '/profissao/:id',
        builder: (_, e) => TelaListaProfissionais(
          profissaoId: e.pathParameters['id']!,
          especialidadeId: int.tryParse(e.uri.queryParameters['esp'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/profissional/:id',
        builder: (_, e) => TelaPerfilProfissional(id: e.pathParameters['id']!, profissaoId: e.uri.queryParameters['profissao']),
      ),
      GoRoute(
        path: '/solicitar/:id',
        builder: (_, e) => TelaSolicitar(
          profissionalId: e.pathParameters['id']!,
          profissaoId: e.uri.queryParameters['profissao']!,
          especialidadeId: int.tryParse(e.uri.queryParameters['esp'] ?? ''),
        ),
      ),
      GoRoute(path: '/pedido/:id', builder: (_, e) => TelaAcompanhar(pedidoId: e.pathParameters['id']!)),
      GoRoute(
        path: '/pedido/:id/chat',
        builder: (_, e) => TelaChat(
          pedidoId: e.pathParameters['id']!,
          nomeOutro: e.uri.queryParameters['nome'] ?? '',
          fotoOutro: e.uri.queryParameters['foto'],
          subtitulo: e.uri.queryParameters['sub'],
        ),
      ),
      GoRoute(path: '/pedido/:id/avaliar', builder: (_, e) => TelaAvaliar(pedidoId: e.pathParameters['id']!)),
      GoRoute(path: '/notificacoes', builder: (context, _) => TelaNotificacoes(aoAbrirPedido: (id) => context.push('/pedido/$id'))),
      GoRoute(path: '/enderecos', builder: (_, _) => const TelaEnderecos()),
    ],
  );
});
