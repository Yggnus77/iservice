import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../estado.dart';

/// Início do profissional: disponibilidade, ganhos de hoje, solicitação nova,
/// próximo atendimento, números e conquistas.
class TelaPainel extends ConsumerWidget {
  const TelaPainel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(meuPerfilProvider).value;
    final pro = perfil?.profissional;
    final andamento = ref.watch(pedidosProProvider('andamento')).value ?? const <Pedido>[];
    final ganhos = ref.watch(ganhosProvider('semana')).value;
    final naoLidas = ref.watch(naoLidasProvider);
    final novas = andamento.where((p) => p.status == StatusPedido.solicitado).toList();
    final proximos = andamento.where((p) => p.status != StatusPedido.solicitado).toList();
    final t = Theme.of(context).textTheme;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(meuPerfilProvider);
          ref.invalidate(pedidosProProvider);
          ref.invalidate(ganhosProvider);
        },
        child: ListView(padding: EdgeInsets.zero, children: [
          Container(
            decoration: Cores.fundoMarca(alinhamento: Alignment.topCenter),
            padding: EdgeInsets.fromLTRB(Medidas.margemTela, MediaQuery.paddingOf(context).top + 12, 8, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Avatar(nome: perfil?.nome ?? '', url: perfil?.fotoUrl, tamanho: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Olá, ${primeiroNome(perfil?.nome ?? '')}', style: t.titleMedium?.copyWith(color: Colors.white)),
                    if (pro != null && pro.totalAvaliacoes > 0)
                      Row(children: [
                        const Icon(Symbols.star_rounded, fill: 1, size: 16, color: Cores.estrela),
                        const SizedBox(width: 3),
                        Text('${nota(pro.notaMedia)} · ${pro.totalAvaliacoes} avaliações', style: t.labelMedium?.copyWith(color: Colors.white70)),
                      ])
                    else
                      Text('Bem-vindo ao iService', style: t.labelMedium?.copyWith(color: Colors.white70)),
                  ]),
                ),
                IconButton(
                  tooltip: 'Notificações',
                  onPressed: () => context.push('/notificacoes'),
                  icon: Badge(isLabelVisible: naoLidas > 0, label: Text('$naoLidas'), child: const Icon(Symbols.notifications_rounded, color: Colors.white)),
                ),
              ]),
              const SizedBox(height: 18),
              Padding(padding: const EdgeInsets.only(right: 12), child: _Disponibilidade(ligado: pro?.disponivel ?? false, ocupado: proximos.any((p) => p.status == StatusPedido.aCaminho || p.status == StatusPedido.emAtendimento))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 16, Medidas.margemTela, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final p in novas) Padding(padding: const EdgeInsets.only(bottom: 12), child: _AvisoNova(p: p)),
              Row(children: [
                Expanded(child: _Numero(icone: Symbols.payments_rounded, rotulo: 'Ganhos hoje', valor: reais(ganhos?.hoje ?? 0), aoTocar: () => context.go('/ganhos'))),
                const SizedBox(width: 12),
                Expanded(child: _Numero(icone: Symbols.calendar_view_week_rounded, rotulo: 'Nesta semana', valor: reais(ganhos?.periodo ?? 0), aoTocar: () => context.go('/ganhos'))),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _Numero(icone: Symbols.task_alt_rounded, rotulo: 'Serviços feitos', valor: '${pro?.servicosConcluidos ?? 0}')),
                const SizedBox(width: 12),
                Expanded(child: _Numero(icone: Symbols.thumb_up_rounded, rotulo: 'Pedidos aceitos', valor: '${((pro?.taxaAceite ?? 1) * 100).round()}%')),
              ]),
              if (proximos.isNotEmpty) ...[
                TituloSecao(titulo: 'Próximo atendimento', acao: 'Agenda', aoTocarAcao: () => context.go('/agenda')),
                CartaoAtendimento(p: proximos.first),
              ],
              if (pro != null) ...[
                const TituloSecao(titulo: 'Metas e conquistas'),
                _Conquistas(pro: pro),
              ],
              const SizedBox(height: 16),
              _Dicas(pro: pro),
              const SizedBox(height: 24),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Disponibilidade extends ConsumerStatefulWidget {
  const _Disponibilidade({required this.ligado, required this.ocupado});
  final bool ligado;
  final bool ocupado;

  @override
  ConsumerState<_Disponibilidade> createState() => _DisponibilidadeState();
}

class _DisponibilidadeState extends ConsumerState<_Disponibilidade> {
  bool? _otimista;
  bool _salvando = false;

  Future<void> _trocar(bool v) async {
    setState(() {
      _otimista = v;
      _salvando = true;
    });
    try {
      await ref.read(profissionalRepo).definirDisponivel(v);
      ref.invalidate(meuPerfilProvider);
    } catch (e) {
      if (mounted) {
        setState(() => _otimista = null);
        mostrarErro(context, e);
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ligado = _otimista ?? widget.ligado;
    final t = Theme.of(context).textTheme;
    final (titulo, texto) = widget.ocupado
        ? ('Em atendimento', 'Você não aparece nas buscas até concluir.')
        : ligado
            ? ('Disponível para pedidos', 'Clientes perto de você podem te chamar agora.')
            : ('Indisponível', 'Ligue para voltar a aparecer nas buscas.');
    return Material(
      color: ligado && !widget.ocupado ? Cores.verdeSuave : Colors.white,
      borderRadius: BorderRadius.circular(Medidas.raioCartao),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        child: Row(children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(shape: BoxShape.circle, color: widget.ocupado ? Cores.laranja : (ligado ? Cores.verde : Cores.bordaControle)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo, style: t.titleSmall?.copyWith(color: Cores.azulEscuro)),
              Text(texto, style: t.bodySmall?.copyWith(color: Cores.textoSuave)),
            ]),
          ),
          Semantics(
            label: 'Disponível para pedidos',
            child: Switch(value: ligado, onChanged: _salvando ? null : _trocar, activeTrackColor: Cores.verde, activeThumbColor: Colors.white),
          ),
        ]),
      ),
    );
  }
}

class _AvisoNova extends StatelessWidget {
  const _AvisoNova({required this.p});
  final Pedido p;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    return Material(
      color: c.acao,
      borderRadius: BorderRadius.circular(Medidas.raioCartao),
      child: InkWell(
        borderRadius: BorderRadius.circular(Medidas.raioCartao),
        onTap: () => context.go('/solicitacoes'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Icon(Symbols.notifications_active_rounded, fill: 1, color: c.textoNaAcao),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Nova solicitação de ${primeiroNome(p.outraParteNome ?? '')}', style: t.titleSmall?.copyWith(color: c.textoNaAcao)),
                Text(p.especialidade ?? p.quandoTexto, style: t.bodySmall?.copyWith(color: c.textoNaAcao)),
              ]),
            ),
            ContagemRegressiva(ate: p.responderAte, estilo: t.titleMedium?.copyWith(color: c.textoNaAcao)),
          ]),
        ),
      ),
    );
  }
}

class _Numero extends StatelessWidget {
  const _Numero({required this.icone, required this.rotulo, required this.valor, this.aoTocar});
  final IconData icone;
  final String rotulo;
  final String valor;
  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(Medidas.raioCartao),
        onTap: aoTocar,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icone, color: c.acaoTexto, size: 22),
            const SizedBox(height: 8),
            Text(valor, style: t.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(rotulo, style: t.bodySmall),
          ]),
        ),
      ),
    );
  }
}

/// Cartão de um atendimento aceito (usado no Início e na Agenda).
class CartaoAtendimento extends ConsumerWidget {
  const CartaoAtendimento({super.key, required this.p});
  final Pedido p;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final profissao = ref.watch(profissaoPorIdProvider(p.profissaoId));
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(Medidas.raioCartao),
        onTap: () => context.push('/pedido/${p.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Avatar(nome: p.outraParteNome ?? '', url: p.outraParteFoto, tamanho: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.outraParteNome ?? '', style: t.titleSmall),
                  Text(p.especialidade ?? profissao?.nome ?? '', style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              EtiquetaStatus(status: p.status),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Icon(Symbols.schedule_rounded, size: 16, color: c.textoSuave),
              const SizedBox(width: 6),
              Text(p.quandoTexto, style: t.bodySmall),
              if (p.distanciaKm != null) ...[
                const SizedBox(width: 14),
                Icon(Symbols.near_me_rounded, size: 16, color: c.textoSuave),
                const SizedBox(width: 4),
                Text(distancia(p.distanciaKm!), style: t.bodySmall),
              ],
              const Spacer(),
              if (p.naoLidas > 0) Badge(label: Text('${p.naoLidas}'), child: Icon(Symbols.chat_rounded, size: 20, color: c.acaoTexto)),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Icon(Symbols.location_on_rounded, size: 16, color: c.textoSuave),
              const SizedBox(width: 6),
              Expanded(child: Text(p.enderecoTexto, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Metas: marcos de serviços concluídos, nota alta, confiabilidade e selo verificado.
class _Conquistas extends StatelessWidget {
  const _Conquistas({required this.pro});
  final MeuCadastroProfissional pro;

  static const _marcos = [1, 10, 25, 50, 100, 250, 500, 1000];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final feitos = pro.servicosConcluidos;
    final proximo = _marcos.firstWhere((m) => m > feitos, orElse: () => feitos + 1);
    final anterior = _marcos.lastWhere((m) => m <= feitos, orElse: () => 0);
    final progresso = proximo == anterior ? 1.0 : (feitos - anterior) / (proximo - anterior);
    final conquistas = [
      (Symbols.verified_rounded, 'Verificado', pro.verificado),
      (Symbols.rocket_launch_rounded, 'Primeiro serviço', feitos >= 1),
      (Symbols.workspace_premium_rounded, '50 serviços', feitos >= 50),
      (Symbols.star_rounded, 'Nota 4,8+', pro.totalAvaliacoes >= 10 && pro.notaMedia >= 4.8),
      (Symbols.bolt_rounded, 'Sempre responde', pro.pedidosRecebidos >= 10 && pro.taxaAceite >= 0.9),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Próxima meta: $proximo serviços', style: t.titleSmall)),
            Text('$feitos/$proximo', style: t.labelMedium?.copyWith(color: c.acaoTexto)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: progresso.clamp(0, 1), minHeight: 8, color: c.acao, backgroundColor: c.superficieSuave),
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final (icone, nome, ok) in conquistas)
              Opacity(
                opacity: ok ? 1 : 0.4,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: ok ? c.acaoSuave : c.superficieSuave),
                    child: Icon(icone, fill: ok ? 1 : 0, color: ok ? c.acaoTexto : c.textoSuave),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(width: 64, child: Text(nome, style: t.labelSmall, textAlign: TextAlign.center, maxLines: 2)),
                ]),
              ),
          ]),
        ]),
      ),
    );
  }
}

class _Dicas extends StatelessWidget {
  const _Dicas({required this.pro});
  final MeuCadastroProfissional? pro;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final dica = switch (pro) {
      null => null,
      final p when (p.bio ?? '').trim().isEmpty => 'Escreva um "Sobre você" no Perfil. Clientes escolhem quem se apresenta.',
      final p when p.totalAvaliacoes < 5 => 'Você está em destaque como profissional novo. Capriche nos primeiros atendimentos.',
      _ => 'Fotos de antes e depois no portfólio aumentam as chances de ser escolhido.',
    };
    if (dica == null) return const SizedBox.shrink();
    return Material(
      color: Cores.azulSuave,
      borderRadius: BorderRadius.circular(Medidas.raioCartao),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          const Icon(Symbols.lightbulb_rounded, fill: 1, color: Cores.azul),
          const SizedBox(width: 12),
          Expanded(child: Text(dica, style: t.bodySmall?.copyWith(color: Cores.azulEscuro))),
        ]),
      ),
    );
  }
}
