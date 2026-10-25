import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iservice_core/iservice_core.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../estado.dart';

/// Pedido direcionado: vai só para o profissional escolhido.
/// Só "agora" ou "hoje"; outro dia apenas se combinado com ele (até 7 dias).
class TelaSolicitar extends ConsumerStatefulWidget {
  const TelaSolicitar({super.key, required this.profissionalId, required this.profissaoId, this.especialidadeId});
  final String profissionalId;
  final String profissaoId;
  final int? especialidadeId;

  @override
  ConsumerState<TelaSolicitar> createState() => _TelaSolicitarState();
}

class _TelaSolicitarState extends ConsumerState<TelaSolicitar> {
  late int? _esp = widget.especialidadeId;
  final _descricao = TextEditingController();
  QuandoPedido _quando = QuandoPedido.agora;
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

  Future<void> _escolherHorario(int diasMax) async {
    final agora = DateTime.now();
    final dia = await showDatePicker(
      context: context,
      firstDate: agora,
      lastDate: agora.add(Duration(days: diasMax)),
      initialDate: _combinado ?? agora.add(const Duration(days: 1)),
      helpText: 'Dia combinado com o profissional',
    );
    if (dia == null || !mounted) return;
    final hora = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 9, minute: 0), helpText: 'Horário combinado');
    if (hora == null) return;
    setState(() => _combinado = DateTime(dia.year, dia.month, dia.day, hora.hour, hora.minute));
  }

  Future<void> _enviar(PerfilProfissional pro, Endereco? endereco) async {
    if (endereco == null) {
      mostrarMensagem(context, 'Cadastre um endereço para o atendimento.');
      return;
    }
    if (_quando == QuandoPedido.hoje && _janela == null) {
      mostrarMensagem(context, 'Escolha a janela de horário de hoje.');
      return;
    }
    if (_quando == QuandoPedido.combinado && _combinado == null) {
      mostrarMensagem(context, 'Escolha o dia e o horário combinados.');
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
              Expanded(child: Text('O pedido vai só para ${primeiroNome(p.nome)}. Ele tem 10 minutos para responder.', style: t.bodySmall)),
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
            SegmentedButton<QuandoPedido>(
              segments: const [
                ButtonSegment(value: QuandoPedido.agora, label: Text('Agora'), icon: Icon(Symbols.bolt_rounded)),
                ButtonSegment(value: QuandoPedido.hoje, label: Text('Hoje'), icon: Icon(Symbols.today_rounded)),
                ButtonSegment(value: QuandoPedido.combinado, label: Text('Combinar'), icon: Icon(Symbols.handshake_rounded)),
              ],
              selected: {_quando},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _quando = s.first),
            ),
            const SizedBox(height: 10),
            switch (_quando) {
              QuandoPedido.agora => Text('Atendimento o quanto antes. Taxa de urgência de ${reais(taxa)}.', style: t.bodySmall),
              QuandoPedido.hoje => janelas.isEmpty
                  ? Text('Não há mais janelas hoje. Use "Agora" ou combine um horário.', style: t.bodySmall)
                  : Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final j in janelas) ChoiceChip(label: Text(j), selected: _janela == j, onSelected: (s) => setState(() => _janela = s ? j : null)),
                    ]),
              QuandoPedido.combinado => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Use só se você já combinou o horário com ${primeiroNome(p.nome)} (até $diasMax dias).', style: t.bodySmall),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _escolherHorario(diasMax),
                    icon: const Icon(Symbols.event_rounded),
                    label: Text(_combinado == null ? 'Escolher dia e horário' : diaEHora(_combinado!)),
                  ),
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
                      context.push('/enderecos');
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
                  _Linha('Preço de ${primeiroNome(p.nome)}', esp?.preco == null ? 'Combinado no local' : 'a partir de ${reais(esp!.preco)}'),
                  if (_quando == QuandoPedido.agora) _Linha('Taxa de urgência', reais(taxa)),
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
              child: BotaoPrincipal(rotulo: 'Enviar pedido para ${primeiroNome(p.nome)}', carregando: _enviando, aoTocar: () => _enviar(p, endereco)),
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
