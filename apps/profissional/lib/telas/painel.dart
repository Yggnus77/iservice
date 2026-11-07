import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../estado.dart';
import 'solicitacoes.dart' show AguardandoCliente, responderChamado, sugerirHorario;

/// Início do profissional: saudação, disponibilidade, chamados de hoje e nota,
/// chamado novo (aceitar ou recusar aqui mesmo), próximo atendimento,
/// ganhos, metas e conquistas.
class TelaPainel extends ConsumerWidget {
  const TelaPainel({super.key});

  static String _saudacao() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Bom dia,';
    if (h < 18) return 'Boa tarde,';
    return 'Boa noite,';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(meuPerfilProvider).value;
    final pro = perfil?.profissional;
    final andamento = ref.watch(pedidosProProvider('andamento')).value ?? const <Pedido>[];
    final todos = ref.watch(pedidosProProvider('todos')).value;
    final ganhos = ref.watch(ganhosProvider('semana')).value;
    final naoLidas = ref.watch(naoLidasProvider);
    final novas = andamento.where((p) => p.status == StatusPedido.solicitado).toList();
    // Próximo atendimento: o que está em curso, senão o mais cedo na agenda.
    final proximos = andamento.where((p) => p.status != StatusPedido.solicitado).toList()
      ..sort((a, b) {
        int peso(Pedido p) => p.status == StatusPedido.emAtendimento ? 0 : (p.status == StatusPedido.aCaminho ? 1 : 2);
        final c = peso(a).compareTo(peso(b));
        return c != 0 ? c : a.dataAtendimento.compareTo(b.dataAtendimento);
      });
    final hoje = DateUtils.dateOnly(DateTime.now());
    final chamadosHoje = todos?.where((p) => DateUtils.dateOnly(p.criadoEm.toLocal()) == hoje).length;
    final ocupado = proximos.any((p) => p.status == StatusPedido.aCaminho || p.status == StatusPedido.emAtendimento);
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
            color: Cores.azulEscuro,
            padding: EdgeInsets.fromLTRB(Medidas.margemTela, MediaQuery.paddingOf(context).top + 16, 8, 76),
            child: Row(children: [
              DecoratedBox(
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Cores.laranja, width: 2)),
                child: Padding(padding: const EdgeInsets.all(2), child: Avatar(nome: perfil?.nome ?? '', url: perfil?.fotoUrl)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_saudacao(), style: t.bodyMedium?.copyWith(color: const Color(0xFFC9D3E6))),
                  Text(perfil?.nome ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                ]),
              ),
              IconButton(
                tooltip: 'Notificações',
                onPressed: () => context.push('/notificacoes'),
                icon: Badge(isLabelVisible: naoLidas > 0, label: Text('$naoLidas'), child: const Icon(Symbols.notifications_rounded, color: Colors.white)),
              ),
            ]),
          ),
          Transform.translate(
            offset: const Offset(0, -56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Medidas.margemTela),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _Disponibilidade(ligado: pro?.disponivel ?? false, ocupado: ocupado),
                const SizedBox(height: 12),
                _Atende24h(ligado: pro?.atende24h ?? false),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: _Numero(
                      icone: Symbols.receipt_long_rounded,
                      rotulo: chamadosHoje == 1 ? 'chamado hoje' : 'chamados hoje',
                      valor: chamadosHoje == null ? '–' : '$chamadosHoje',
                      aoTocar: () => context.go('/solicitacoes'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Numero(
                      icone: Symbols.star_rounded,
                      estrela: true,
                      rotulo: (pro?.totalAvaliacoes ?? 0) == 0 ? 'ainda sem avaliações' : 'sua avaliação',
                      valor: (pro?.totalAvaliacoes ?? 0) == 0 ? 'Novo' : nota(pro!.notaMedia),
                    ),
                  ),
                ]),
                if (novas.isNotEmpty) ...[
                  TituloSecao(titulo: novas.length == 1 ? 'Novo chamado' : 'Novos chamados (${novas.length})'),
                  for (final p in novas) Padding(padding: const EdgeInsets.only(bottom: 12), child: _NovoChamado(key: ValueKey(p.id), p: p)),
                ],
                if (proximos.isNotEmpty) ...[
                  TituloSecao(titulo: 'Próximo atendimento', acao: 'Agenda', aoTocarAcao: () => context.go('/agenda')),
                  CartaoAtendimento(p: proximos.first),
                ],
                TituloSecao(titulo: 'Seus números', acao: 'Ganhos', aoTocarAcao: () => context.go('/ganhos')),
                Row(children: [
                  Expanded(child: _Numero(icone: Symbols.payments_rounded, rotulo: 'ganhos hoje', valor: reais(ganhos?.hoje ?? 0), aoTocar: () => context.go('/ganhos'))),
                  const SizedBox(width: 12),
                  Expanded(child: _Numero(icone: Symbols.calendar_view_week_rounded, rotulo: 'nesta semana', valor: reais(ganhos?.periodo ?? 0), aoTocar: () => context.go('/ganhos'))),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _Numero(icone: Symbols.task_alt_rounded, rotulo: 'serviços feitos', valor: '${pro?.servicosConcluidos ?? 0}')),
                  const SizedBox(width: 12),
                  Expanded(child: _Numero(icone: Symbols.thumb_up_rounded, rotulo: 'pedidos aceitos', valor: '${((pro?.taxaAceite ?? 1) * 100).round()}%')),
                ]),
                if (pro != null) ...[
                  const TituloSecao(titulo: 'Metas e conquistas'),
                  _Conquistas(pro: pro),
                ],
                const SizedBox(height: 16),
                _Dicas(pro: pro),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Cartão grande do modo disponível. Verde só quando está disponível de fato;
/// sobre o verde, texto em azul-escuro (nunca branco).
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
    final c = context.cores;
    final verde = ligado && !widget.ocupado;
    final (titulo, texto) = widget.ocupado
        ? ('Você está em atendimento', 'Você não aparece nas buscas até concluir.')
        : ligado
            ? ('Você está disponível', 'Clientes da sua região podem te chamar agora.')
            : ('Você está indisponível', 'Você não aparece nas buscas até ligar de novo.');
    final fundo = widget.ocupado ? Cores.laranjaSuave : (verde ? Cores.verde : Theme.of(context).colorScheme.surface);
    final corTexto = widget.ocupado || verde ? Cores.azulEscuro : null;
    return Material(
      color: fundo,
      elevation: 6,
      shadowColor: const Color(0x520A1F44),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: verde || widget.ocupado ? BorderSide.none : BorderSide(color: c.linha),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('MODO DISPONÍVEL', style: t.labelSmall?.copyWith(color: corTexto ?? c.textoSuave, fontWeight: FontWeight.w700, letterSpacing: .8)),
              const SizedBox(height: 4),
              Text(titulo, style: t.titleLarge?.copyWith(color: corTexto, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(texto, style: t.bodySmall?.copyWith(color: corTexto ?? c.textoSuave, fontWeight: FontWeight.w500)),
            ]),
          ),
          const SizedBox(width: 12),
          Semantics(
            label: 'Disponível para chamados',
            child: Transform.scale(
              scale: 1.15,
              child: Switch(
                value: ligado,
                onChanged: _salvando || widget.ocupado ? null : _trocar,
                activeTrackColor: Cores.azulEscuro,
                activeThumbColor: Colors.white,
                thumbIcon: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? const Icon(Symbols.check_rounded, color: Cores.verdeTexto) : null),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// "Atendo 24h": entra no botão Urgência 24h do app Cliente. Só vale quando
/// ele também está disponível; o servidor confere as duas coisas na busca.
class _Atende24h extends ConsumerStatefulWidget {
  const _Atende24h({required this.ligado});
  final bool ligado;

  @override
  ConsumerState<_Atende24h> createState() => _Atende24hState();
}

class _Atende24hState extends ConsumerState<_Atende24h> {
  bool? _otimista;
  bool _salvando = false;

  Future<void> _trocar(bool v) async {
    setState(() {
      _otimista = v;
      _salvando = true;
    });
    try {
      await ref.read(profissionalRepo).definirAtende24h(v);
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
    final c = context.cores;
    return Card(
      margin: EdgeInsets.zero,
      child: SwitchListTile(
        value: ligado,
        onChanged: _salvando ? null : _trocar,
        minTileHeight: Medidas.toque,
        contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
        secondary: const Icon(Symbols.bolt_rounded, fill: 1, color: Cores.laranja),
        title: Text('Atendo 24h', style: t.titleSmall),
        subtitle: Text(
          ligado ? 'Você aparece na Urgência 24h quando está disponível.' : 'Ligue para receber chamados de urgência a qualquer hora.',
          style: t.bodySmall?.copyWith(color: c.textoSuave),
        ),
      ),
    );
  }
}

/// Chamado novo no Início: borda laranja, prazo de resposta, descrição e
/// os botões Recusar (contorno) e Aceitar (verde, texto azul-escuro).
class _NovoChamado extends ConsumerStatefulWidget {
  const _NovoChamado({super.key, required this.p});
  final Pedido p;

  @override
  ConsumerState<_NovoChamado> createState() => _NovoChamadoState();
}

class _NovoChamadoState extends ConsumerState<_NovoChamado> {
  bool _ocupado = false;
  bool _acabou = false;

  Pedido get p => widget.p;

  Future<void> _responder(bool aceitar) async {
    setState(() => _ocupado = true);
    await responderChamado(context, ref, p, aceitar: aceitar);
    if (mounted) setState(() => _ocupado = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final profissao = ref.watch(profissaoPorIdProvider(p.profissaoId));
    final expirou = _acabou || p.tempoParaResponder == Duration.zero;
    final titulo = [profissao?.nome ?? '', if (p.distanciaKm != null) distancia(p.distanciaKm)].where((s) => s.isNotEmpty).join(' · ');
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 6,
      shadowColor: const Color(0x520A1F44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Medidas.raioCartao), side: const BorderSide(color: Cores.laranja, width: 2)),
      child: InkWell(
        borderRadius: BorderRadius.circular(Medidas.raioCartao),
        onTap: () => context.go('/solicitacoes'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: c.alertaSuave, borderRadius: BorderRadius.circular(Medidas.raioControle)),
                child: Icon(iconeProfissao(profissao?.icone ?? ''), color: c.alerta),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(titulo, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text([primeiroNome(p.outraParteNome ?? 'Cliente'), p.enderecoTexto].join(' · '), style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: c.acaoSuave, borderRadius: BorderRadius.circular(8)),
                child: Text(p.quando == QuandoPedido.agora ? 'AGORA' : (p.agendado ? diaRelativo(p.combinadoPara!) : p.quandoTexto).toUpperCase(),
                    style: t.labelSmall?.copyWith(color: c.acaoTexto, fontWeight: FontWeight.w700, letterSpacing: .6)),
              ),
            ]),
            const SizedBox(height: 12),
            if (p.especialidade != null) ...[
              Text(p.especialidade!, style: t.titleSmall),
              const SizedBox(height: 4),
            ],
            if (p.descricao.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: c.superficieSuave, borderRadius: BorderRadius.circular(Medidas.raioControle)),
                child: Text(p.descricao, style: t.bodyMedium),
              ),
            if (p.agendado) ...[
              const SizedBox(height: 10),
              Row(children: [
                Icon(Symbols.event_rounded, size: 18, color: c.acaoTexto),
                const SizedBox(width: 6),
                Expanded(child: Text('Pediu para ${p.quandoTexto.toLowerCase()}', style: t.titleSmall)),
              ]),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Icon(Symbols.timer_rounded, size: 18, color: expirou ? c.perigo : c.alerta),
              const SizedBox(width: 6),
              if (expirou)
                Text('O tempo para responder acabou', style: t.labelLarge?.copyWith(color: c.perigo))
              else ...[
                Text('Responda em ', style: t.labelLarge?.copyWith(color: c.alerta)),
                ContagemRegressiva(
                  ate: p.responderAte,
                  estilo: t.labelLarge?.copyWith(color: c.alerta),
                  aoAcabar: () {
                    if (!mounted) return;
                    setState(() => _acabou = true);
                    ref.invalidate(pedidosProProvider);
                  },
                ),
              ],
            ]),
            const SizedBox(height: 14),
            if (p.aguardandoCliente) AguardandoCliente(p: p) else ...[
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _ocupado || expirou ? null : () => _responder(false),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                    side: const BorderSide(color: Cores.bordaControle, width: 1.5),
                  ),
                  child: const Text('Recusar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _ocupado || expirou ? null : () => _responder(true),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: Cores.verde,
                    foregroundColor: Cores.azulEscuro,
                    textStyle: t.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  child: _ocupado
                      ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Cores.azulEscuro))
                      : Text(p.agendado ? 'Confirmar' : 'Aceitar'),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Center(
              child: TextButton.icon(
                onPressed: _ocupado || expirou ? null : () => sugerirHorario(context, ref, p),
                icon: const Icon(Symbols.edit_calendar_rounded),
                label: const Text('Sugerir outro horário'),
              ),
            ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _Numero extends StatelessWidget {
  const _Numero({required this.icone, required this.rotulo, required this.valor, this.aoTocar, this.estrela = false});
  final IconData icone;
  final bool estrela;
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
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: estrela ? Cores.laranjaSuave : c.acaoSuave, borderRadius: BorderRadius.circular(10)),
              child: Icon(icone, fill: estrela ? 1 : 0, color: estrela ? Cores.estrela : c.acaoTexto, size: 20),
            ),
            const SizedBox(height: 8),
            Text(valor, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
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
                Text(distancia(p.distanciaKm), style: t.bodySmall),
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
