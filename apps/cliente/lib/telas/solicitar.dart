import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../estado.dart';

/// Pedido direcionado: vai só para o profissional escolhido.
/// "Agora" (com taxa de urgência), "Hoje" numa janela, ou agendado para um dia
/// da agenda (até dias_max_combinado dias), mesmo com ele ocupado agora.
class TelaSolicitar extends ConsumerStatefulWidget {
  const TelaSolicitar({super.key, required this.profissionalId, required this.profissaoId, this.especialidadeId, this.agendar = false});
  final String profissionalId;
  final String profissaoId;
  final int? especialidadeId;

  /// Abre já em "Agendar" (vindo de um profissional ocupado agora).
  final bool agendar;

  @override
  ConsumerState<TelaSolicitar> createState() => _TelaSolicitarState();
}

class _TelaSolicitarState extends ConsumerState<TelaSolicitar> {
  late int? _esp = widget.especialidadeId;
  final _descricao = TextEditingController();
  late QuandoPedido _quando = widget.agendar ? QuandoPedido.combinado : QuandoPedido.agora;
  String? _janela;
  DateTime? _combinado;
  int? _enderecoId;
  bool _enviando = false;

  List<String> _janelasDeHoje(Map<String, dynamic> config) {
    final todas = List<String>.from((config['janelas_hoje'] as List?) ?? const ['14:00–16:00', '16:00–18:00', '18:00–20:00', '20:00–22:00']);
    final agora = DateTime.now();
    // Só janelas que ainda não começaram (com 30 min de folga).
    return todas.where((j) {
      final h = int.tryParse(j.split(':').first) ?? 0;
      return DateTime(agora.year, agora.month, agora.day, h).isAfter(agora.add(const Duration(minutes: 30)));
    }).toList();
  }

  Future<void> _escolherHorario(PerfilProfissional pro, int diasMax) async {
    final ocupados = await ref.read(pedidosRepo).horariosOcupados(pro.id).catchError((_) => <DateTime>[]);
    if (!mounted) return;
    final h = await escolherHorarioAgenda(
      context,
      diasMax: diasMax,
      titulo: 'Agendar com ${primeiroNome(pro.nome)}',
      subtitulo: 'Escolha um dia nos próximos $diasMax dias. ${primeiroNome(pro.nome)} confirma ou sugere outro horário.',
      ocupados: ocupados,
      inicial: _combinado,
      rotuloConfirmar: 'Escolher',
    );
    if (h != null) setState(() => _combinado = h);
  }

  Future<void> _enviar(PerfilProfissional pro, Endereco? endereco) async {
    if (!pro.disponivel) _quando = QuandoPedido.combinado;
    if (endereco == null) {
      mostrarMensagem(context, 'Cadastre um endereço para o atendimento.');
      return;
    }
    if (_quando == QuandoPedido.hoje && _janela == null) {
      mostrarMensagem(context, 'Escolha a janela de horário de hoje.');
      return;
    }
    if (_quando == QuandoPedido.combinado && _combinado == null) {
      mostrarMensagem(context, 'Escolha o dia e o horário do agendamento.');
      return;
    }
    setState(() => _enviando = true);
    try {
      final pedido = await ref.read(pedidosRepo).criar(
            profissionalId: pro.id,
            profissaoId: widget.profissaoId,
            enderecoId: endereco.id,
            quando: _quando,
            especialidadeId: _esp,
            descricao: _descricao.text.trim(),
            janela: _quando == QuandoPedido.hoje ? _janela : null,
            combinadoPara: _quando == QuandoPedido.combinado ? _combinado : null,
          );
      ref.invalidate(pedidosClienteProvider);
      if (mounted) context.pushReplacement('/pedido/${pedido.id}');
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pro = ref.watch(perfilProfissionalProvider(widget.profissionalId));
    final perfil = ref.watch(meuPerfilProvider).value;
    final config = ref.watch(configProvider).value ?? const {};
    final t = Theme.of(context).textTheme;
    final c = context.cores;

    return pro.when(
      loading: () => const Scaffold(body: Carregando()),
      error: (e, _) => Scaffold(appBar: AppBar(), body: ErroNaTela(erro: e)),
      data: (p) {
        if (p == null) return Scaffold(appBar: AppBar(), body: const EstadoVazio(icone: Symbols.person_off_rounded, titulo: 'Profissional indisponível'));
        final profissao = p.profissoes.where((x) => x.id == widget.profissaoId).firstOrNull;
        final esps = profissao?.especialidades ?? const <Especialidade>[];
        final esp = esps.where((e) => e.id == _esp).firstOrNull;
        final enderecos = perfil?.enderecos ?? const <Endereco>[];
        final endereco = enderecos.where((e) => e.id == _enderecoId).firstOrNull ?? perfil?.enderecoPrincipal;
        final taxa = (config['taxa_urgencia'] as num?)?.toDouble() ?? 15;
        final diasMax = (config['dias_max_combinado'] as num?)?.toInt() ?? 7;
        final janelas = _janelasDeHoje(config);
        // Ocupado agora: só dá para agendar.
        final soAgendar = !p.disponivel;
        final quando = soAgendar ? QuandoPedido.combinado : _quando;
        final prazoMin = quando == QuandoPedido.combinado
            ? (config['prazo_resposta_agendado_min'] as num?)?.toInt() ?? 120
            : (config['prazo_resposta_min'] as num?)?.toInt() ?? 10;
        final prazoTexto = prazoMin >= 60 && prazoMin % 60 == 0 ? '${prazoMin ~/ 60} ${prazoMin == 60 ? 'hora' : 'horas'}' : '$prazoMin minutos';
        // Faixa comum na região do endereço, na mesma forma de cobrança do profissional.
        final faixa = esp?.preco == null ? null : ref.watch(faixaPrecoProvider((esp!.id, endereco?.regiaoId, esp.cobranca))).value;
        final regiao = (ref.watch(regioesProvider).value ?? const <Regiao>[]).where((r) => r.id == endereco?.regiaoId).firstOrNull;

        return Scaffold(
          appBar: AppBar(title: const Text('Solicitar serviço')),
          body: ListView(padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 0, Medidas.margemTela, 24), children: [
            Card(
              child: ListTile(
                leading: Avatar(nome: p.nome, url: p.fotoUrl),
                title: Text(p.nome, style: t.titleSmall),
                subtitle: Row(children: [
                  Text(profissao?.nome ?? ''),
                  const SizedBox(width: 8),
                  if (!p.novo) NotaCompacta(nota: p.notaMedia, tamanho: 12),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Symbols.lock_person_rounded, size: 16, color: c.textoSuave),
              const SizedBox(width: 6),
              Expanded(child: Text('O pedido vai só para ${primeiroNome(p.nome)}, que tem até $prazoTexto para responder.', style: t.bodySmall)),
            ]),
            const TituloSecao(titulo: 'O que você precisa?'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in esps) ChoiceChip(label: Text(e.nome), selected: _esp == e.id, onSelected: (s) => setState(() => _esp = s ? e.id : null)),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _descricao,
              minLines: 3,
              maxLines: 6,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Descreva o problema. Ex.: o chuveiro desarma o disjuntor quando liga no quente.',
                helperText: 'Dica: use o microfone do teclado para ditar.',
              ),
            ),
            const TituloSecao(titulo: 'Quando?'),
            if (soAgendar)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: c.alertaSuave, borderRadius: BorderRadius.circular(Medidas.raioControle)),
                child: Row(children: [
                  Icon(Symbols.event_busy_rounded, color: c.alerta),
                  const SizedBox(width: 10),
                  Expanded(child: Text('${primeiroNome(p.nome)} está ocupado agora. Agende um dia e horário nos próximos $diasMax dias.', style: t.bodyMedium)),
                ]),
              )
            else
              SegmentedButton<QuandoPedido>(
                segments: const [
                  ButtonSegment(value: QuandoPedido.agora, label: Text('Agora'), icon: Icon(Symbols.bolt_rounded)),
                  ButtonSegment(value: QuandoPedido.hoje, label: Text('Hoje'), icon: Icon(Symbols.today_rounded)),
                  ButtonSegment(value: QuandoPedido.combinado, label: Text('Agendar'), icon: Icon(Symbols.event_rounded)),
                ],
                selected: {quando},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _quando = s.first),
              ),
            const SizedBox(height: 10),
            switch (quando) {
              QuandoPedido.agora => Text('Atendimento o quanto antes. Taxa de urgência de ${reais(taxa)}.', style: t.bodySmall),
              QuandoPedido.hoje => janelas.isEmpty
                  ? Text('Não há mais janelas hoje. Use "Agora" ou agende outro dia.', style: t.bodySmall)
                  : Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final j in janelas) ChoiceChip(label: Text(j), selected: _janela == j, onSelected: (s) => setState(() => _janela = s ? j : null)),
                    ]),
              QuandoPedido.combinado => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (!soAgendar)
                    Text('Escolha um dia nos próximos $diasMax dias, sem taxa de urgência. ${primeiroNome(p.nome)} confirma ou sugere outro horário.', style: t.bodySmall),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _escolherHorario(p, diasMax),
                    icon: const Icon(Symbols.calendar_month_rounded),
                    label: Text(_combinado == null ? 'Escolher dia e horário' : diaRelativoEHora(_combinado!)),
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    Icon(Symbols.notifications_active_rounded, size: 16, color: c.textoSuave),
                    const SizedBox(width: 6),
                    Expanded(child: Text('Confirmado, vocês dois recebem o aviso, e um lembrete na véspera e 1 hora antes.', style: t.bodySmall)),
                  ]),
                ]),
            },
            const TituloSecao(titulo: 'Onde?'),
            Card(
              child: ListTile(
                leading: Icon(Symbols.location_on_rounded, fill: 1, color: c.acaoTexto),
                title: Text(endereco?.linha1 ?? 'Nenhum endereço'),
                subtitle: endereco?.referencia == null || endereco!.referencia!.isEmpty ? null : Text(endereco.referencia!),
                trailing: TextButton(
                  onPressed: () async {
                    if (enderecos.length < 2) {
                      unawaited(context.push('/enderecos'));
                      return;
                    }
                    final e = await escolherEmLista<Endereco>(context, titulo: 'Endereço do atendimento', opcoes: enderecos, rotulo: (e) => '${e.rotulo}: ${e.linha1}', atual: endereco);
                    if (e != null) setState(() => _enderecoId = e.id);
                  },
                  child: const Text('Trocar'),
                ),
              ),
            ),
            const TituloSecao(titulo: 'Valores'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  _Linha('Preço de ${primeiroNome(p.nome)}', esp?.preco == null ? 'Combinado no local' : 'em média ${reais(esp!.preco)} ${esp.cobranca.unidade}'),
                  if (faixa != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 4),
                      child: Text(
                        'Comum ${regiao == null ? 'na região' : 'em ${regiao.nome}'}: ${faixaReais(faixa.minimo, faixa.maximo)} ${esp!.cobranca.unidade}',
                        style: t.bodySmall,
                      ),
                    ),
                  if (quando == QuandoPedido.agora) _Linha('Taxa de urgência', reais(taxa)),
                  const Divider(height: 20),
                  Row(children: [
                    Icon(Symbols.payments_rounded, size: 18, color: c.textoSuave),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Você paga direto ao profissional, depois do serviço.', style: t.bodySmall)),
                  ]),
                ]),
              ),
            ),
          ]),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 8, Medidas.margemTela, 12),
              child: BotaoPrincipal(rotulo: quando == QuandoPedido.combinado ? 'Pedir agendamento a ${primeiroNome(p.nome)}' : 'Enviar pedido para ${primeiroNome(p.nome)}', carregando: _enviando, aoTocar: () => _enviar(p, endereco)),
            ),
          ),
        );
      },
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha(this.rotulo, this.valor);
  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [Expanded(child: Text(rotulo, style: t.bodyMedium)), Text(valor, style: t.titleSmall)]),
    );
  }
}
