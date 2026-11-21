import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../estado/provedores.dart';
import '../tema/cores.dart';
import '../tema/tema.dart';
import '../widgets/componentes.dart';

/// Pergunta da Central de Ajuda (editada pela equipe no painel).
class PerguntaAjuda {
  const PerguntaAjuda({required this.categoria, required this.pergunta, required this.resposta});
  final String categoria;
  final String pergunta;
  final String resposta;
}

final ajudaProvider = FutureProvider.autoDispose<List<PerguntaAjuda>>((ref) async {
  final app = ref.read(appProvider);
  final linhas = await supabase
      .from('ajuda_perguntas')
      .select('categoria, pergunta, resposta, publico')
      .inFilter('publico', [app.name, 'todos'])
      .order('ordem')
      .order('id');
  return [
    for (final l in linhas)
      PerguntaAjuda(categoria: l['categoria'] as String, pergunta: l['pergunta'] as String, resposta: l['resposta'] as String),
  ];
});

const _diasLongos = ['', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'];

String _hora(String h) {
  final p = h.split(':');
  return p.length == 2 && p[1] == '00' ? '${int.parse(p[0])}h' : h.replaceFirst(':', 'h');
}

/// "De segunda a sábado, das 8h às 20h", a partir de app_config.horario_atendimento.
String textoHorarioAtendimento(Map<String, dynamic> config) {
  final h = config['horario_atendimento'];
  if (h is! Map) return 'De segunda a sábado, das 8h às 20h';
  final dias = [for (final d in (h['dias'] as List? ?? const [])) (d as num).toInt()]..sort();
  if (dias.isEmpty) return 'De segunda a sábado, das 8h às 20h';
  var seguidos = dias.length > 1;
  for (var i = 1; i < dias.length; i++) {
    if (dias[i] != dias[i - 1] + 1) seguidos = false;
  }
  final quando = dias.length == 7
      ? 'Todos os dias'
      : seguidos
          ? 'De ${_diasLongos[dias.first]} a ${_diasLongos[dias.last]}'
          : (dias.map((d) => _diasLongos[d]).join(', ').replaceFirstMapped(RegExp(r', ([^,]*)$'), (m) => ' e ${m[1]}'));
  return '${quando[0].toUpperCase()}${quando.substring(1)}, das ${_hora('${h['inicio'] ?? '08:00'}')} às ${_hora('${h['fim'] ?? '20:00'}')}';
}

/// Central de Ajuda: perguntas frequentes, horário e os canais de atendimento.
class TelaAjuda extends ConsumerStatefulWidget {
  const TelaAjuda({super.key});

  @override
  ConsumerState<TelaAjuda> createState() => _TelaAjudaState();
}

class _TelaAjudaState extends ConsumerState<TelaAjuda> {
  final _busca = TextEditingController();
  String _filtro = '';

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  static String _sem(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[áàâã]'), 'a')
      .replaceAll(RegExp('[éê]'), 'e')
      .replaceAll('í', 'i')
      .replaceAll(RegExp('[óôõ]'), 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ç', 'c');

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.cores;
    final perguntas = ref.watch(ajudaProvider);
    final config = ref.watch(configProvider).value ?? const {};
    final zap = (config['whatsapp_suporte'] as String?) ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Central de Ajuda')),
      body: perguntas.when(
        loading: () => const Carregando(),
        error: (e, _) => ErroNaTela(erro: e, aoTentar: () => ref.invalidate(ajudaProvider)),
        data: (lista) {
          final f = _sem(_filtro.trim());
          final filtradas = f.isEmpty ? lista : lista.where((p) => _sem('${p.pergunta} ${p.resposta} ${p.categoria}').contains(f)).toList();
          final categorias = <String>{for (final p in filtradas) p.categoria}.toList();
          return ListView(padding: const EdgeInsets.fromLTRB(Medidas.margemTela, 8, Medidas.margemTela, 32), children: [
            TextField(
              controller: _busca,
              decoration: const InputDecoration(prefixIcon: Icon(Symbols.search_rounded), hintText: 'Buscar uma dúvida'),
              textInputAction: TextInputAction.search,
              onChanged: (v) => setState(() => _filtro = v),
            ),
            const SizedBox(height: 16),
            if (filtradas.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text('Nenhuma pergunta encontrada. Fale com a gente pelos canais abaixo.', style: t.bodyMedium, textAlign: TextAlign.center),
              ),
            for (final cat in categorias) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 6),
                child: Text(cat, style: t.titleSmall?.copyWith(color: c.textoSuave)),
              ),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  for (final (i, p) in filtradas.where((p) => p.categoria == cat).indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    ExpansionTile(
                      title: Text(p.pergunta, style: t.titleSmall),
                      shape: const Border(),
                      collapsedShape: const Border(),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [Text(p.resposta, style: t.bodyMedium)],
                    ),
                  ],
                ]),
              ),
            ],
            const SizedBox(height: 24),
            Text('Ainda precisa de ajuda?', style: t.titleSmall?.copyWith(color: c.textoSuave)),
            const SizedBox(height: 6),
            Card(
              child: Column(children: [
                ListTile(
                  leading: Icon(Symbols.forum_rounded, color: c.acaoTexto),
                  title: const Text('Conversar com o suporte'),
                  subtitle: const Text('Chat com a equipe do iService, aqui no app'),
                  trailing: const Icon(Symbols.chevron_right_rounded),
                  onTap: () => context.push('/suporte'),
                ),
                const Divider(indent: 56),
                ListTile(
                  leading: const Icon(Symbols.schedule_rounded),
                  title: const Text('Horário de atendimento'),
                  subtitle: Text('${textoHorarioAtendimento(config)} (Brasília). Emergências durante um serviço: 24 horas, pelo botão no pedido.'),
                ),
                const Divider(indent: 56),
                ListTile(
                  leading: const Icon(Symbols.support_agent_rounded, color: Cores.verdeTexto),
                  title: const Text('WhatsApp do iService'),
                  trailing: const Icon(Symbols.open_in_new_rounded, size: 18),
                  onTap: zap.isEmpty
                      ? () => mostrarMensagem(context, 'O atendimento pelo WhatsApp começa no lançamento. Use o e-mail por enquanto.')
                      : () => launchUrl(Uri.parse('https://wa.me/$zap'), mode: LaunchMode.externalApplication),
                ),
                const Divider(indent: 56),
                ListTile(
                  leading: const Icon(Symbols.mail_rounded),
                  title: const Text('E-mail'),
                  subtitle: const Text('suporte@iservice.app.br'),
                  trailing: const Icon(Symbols.open_in_new_rounded, size: 18),
                  onTap: () => launchUrl(Uri.parse('mailto:suporte@iservice.app.br?subject=Ajuda%20no%20app'), mode: LaunchMode.externalApplication),
                ),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}
