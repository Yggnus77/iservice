import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../tema/cores.dart';
import '../tema/tema.dart';
import '../util/formatos.dart';
import '../widgets/componentes.dart';
import 'ajuda.dart';

const emailSuporte = 'suporte@iservice.app.br';

/// Abre o e-mail do aparelho já endereçado ao suporte.
Future<void> mandarEmailSuporte({String? protocolo}) => launchUrl(
      Uri.parse('mailto:$emailSuporte?subject=${Uri.encodeComponent(protocolo == null ? 'Ajuda no app' : 'Ajuda no app [$protocolo]')}'),
      mode: LaunchMode.externalApplication,
    );

class _MsgSuporte {
  const _MsgSuporte({required this.id, required this.minha, required this.texto, required this.criadaEm, this.autor});
  final int id;
  final bool minha;
  final String texto;
  final String? autor;
  final DateTime criadaEm;
}

class _EstadoSuporte {
  _EstadoSuporte(Map<String, dynamic> j)
      : online = j['online'] == true,
        emHorario = j['em_horario'] == true,
        horario = textoHorarioAtendimento({'horario_atendimento': j['horario']}),
        protocolo = (j['conversa'] as Map?)?['protocolo'] as String?,
        encerrada = (j['conversa'] as Map?)?['status'] == 'encerrado',
        mensagens = [
          for (final m in ((j['conversa'] as Map?)?['mensagens'] as List? ?? const []))
            _MsgSuporte(
              id: (m['id'] as num).toInt(),
              minha: m['minha'] == true,
              texto: (m['texto'] as String?) ?? '',
              autor: (m['autor'] as String?)?.trim().isEmpty ?? true ? null : m['autor'] as String,
              criadaEm: DateTime.parse(m['criada_em'] as String),
            ),
        ];
  final bool online;
  final bool emHorario;
  final String horario;
  final String? protocolo;
  final bool encerrada;
  final List<_MsgSuporte> mensagens;
}

/// "Falar com o suporte": conversa da pessoa com a equipe do iService, igual nos dois apps.
/// As mensagens caem na caixa do suporte do painel; a resposta chega por aviso e aparece aqui.
class TelaSuporte extends StatefulWidget {
  const TelaSuporte({super.key});

  @override
  State<TelaSuporte> createState() => _TelaSuporteState();
}

class _TelaSuporteState extends State<TelaSuporte> with WidgetsBindingObserver {
  final _texto = TextEditingController();
  _EstadoSuporte? _estado;
  Object? _erro;
  bool _enviando = false;
  Timer? _timer;
  bool _ativo = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_carregar());
    // Sem tempo real nesta tabela: confere a cada 6 s enquanto a tela está aberta.
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (_ativo) unawaited(_carregar());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    _ativo = s == AppLifecycleState.resumed;
    if (_ativo) unawaited(_carregar());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _texto.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final r = await supabase.rpc('suporte_app_estado');
      if (mounted) setState(() { _estado = _EstadoSuporte(Map<String, dynamic>.from(r as Map)); _erro = null; });
    } catch (e) {
      if (mounted && _estado == null) setState(() => _erro = e);
    }
  }

  Future<void> _enviar() async {
    final t = _texto.text.trim();
    if (t.isEmpty || _enviando) return;
    setState(() => _enviando = true);
    try {
      final r = await supabase.rpc('suporte_app_enviar', params: {'p_texto': t});
      _texto.clear();
      if (mounted) setState(() => _estado = _EstadoSuporte(Map<String, dynamic>.from(r as Map)));
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final t = Theme.of(context).textTheme;
    final e = _estado;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          Stack(clipBehavior: Clip.none, children: [
            CircleAvatar(radius: 19, backgroundColor: c.acaoSuave, child: Icon(Symbols.support_agent_rounded, color: c.acaoTexto)),
            if (e != null)
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    color: e.online ? c.sucesso : c.textoSuave,
                    shape: BoxShape.circle,
                    border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2),
                  ),
                ),
              ),
          ]),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Suporte iService', style: t.titleSmall),
              Text(
                e == null ? 'Carregando…' : e.online ? 'Equipe online agora' : 'Equipe offline no momento',
                style: t.bodySmall?.copyWith(color: e?.online ?? false ? c.sucesso : c.textoSuave),
              ),
            ]),
          ),
        ]),
        actions: [
          IconButton(tooltip: 'Mandar e-mail', icon: const Icon(Symbols.mail_rounded), onPressed: () => mandarEmailSuporte(protocolo: e?.protocolo)),
        ],
      ),
      body: _erro != null && e == null
          ? ErroNaTela(erro: _erro!, aoTentar: () { setState(() => _erro = null); unawaited(_carregar()); })
          : e == null
              ? const Carregando()
              : Column(children: [
                  if (!e.online) _AvisoOffline(estado: e),
                  Expanded(
                    child: e.mensagens.isEmpty
                        ? EstadoVazio(
                            icone: Symbols.support_agent_rounded,
                            titulo: 'Como podemos ajudar?',
                            texto: e.online
                                ? 'Escreva sua dúvida. Uma pessoa da nossa equipe responde por aqui.'
                                : 'Deixe sua mensagem. Assim que alguém da equipe entrar, responde por aqui e você recebe um aviso.',
                          )
                        : ListView.builder(
                            reverse: true,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            itemCount: e.mensagens.length + (e.encerrada ? 1 : 0),
                            itemBuilder: (_, i) {
                              if (e.encerrada && i == 0) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  child: Text('Atendimento encerrado. Se precisar de algo mais, é só escrever.',
                                      textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: c.textoSuave)),
                                );
                              }
                              final m = e.mensagens[e.mensagens.length - 1 - (i - (e.encerrada ? 1 : 0))];
                              return _Balao(m: m);
                            },
                          ),
                  ),
                  if (e.protocolo != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text('Protocolo ${e.protocolo}', style: t.labelSmall?.copyWith(color: c.textoSuave)),
                    ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
                      child: Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _texto,
                            minLines: 1,
                            maxLines: 5,
                            maxLength: 2000,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: 'Escreva para o suporte',
                              counterText: '',
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(Medidas.raioPilula)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Medidas.raioPilula), borderSide: BorderSide(color: c.linha)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton.filled(
                          tooltip: 'Enviar',
                          onPressed: _enviando ? null : _enviar,
                          style: IconButton.styleFrom(backgroundColor: c.acao, foregroundColor: c.textoNaAcao, minimumSize: const Size(48, 48)),
                          icon: _enviando
                              ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: c.textoNaAcao))
                              : const Icon(Symbols.send_rounded, fill: 1),
                        ),
                      ]),
                    ),
                  ),
                ]),
    );
  }
}

class _AvisoOffline extends StatelessWidget {
  const _AvisoOffline({required this.estado});
  final _EstadoSuporte estado;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final t = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(color: c.superficieSuave, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.linha)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Symbols.schedule_rounded, size: 18, color: c.textoSuave),
          const SizedBox(width: 6),
          Expanded(child: Text('Ninguém da equipe está online agora', style: t.titleSmall)),
        ]),
        const SizedBox(height: 4),
        Text(
          '${estado.emHorario ? 'Pode deixar sua mensagem aqui que respondemos assim que alguém entrar.' : 'Nosso horário: ${estado.horario} (Brasília). Pode deixar sua mensagem aqui.'}'
          ' Se preferir, mande um e-mail para $emailSuporte.',
          style: t.bodySmall,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => mandarEmailSuporte(protocolo: estado.protocolo),
            icon: const Icon(Symbols.mail_rounded, size: 18),
            label: const Text('Mandar e-mail para o suporte'),
          ),
        ),
        Text('Emergência durante um serviço? Use o botão de emergência no pedido, 24 horas.', style: t.labelSmall?.copyWith(color: c.textoSuave)),
        const SizedBox(height: 4),
      ]),
    );
  }
}

class _Balao extends StatelessWidget {
  const _Balao({required this.m});
  final _MsgSuporte m;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final t = Theme.of(context).textTheme;
    final minha = m.minha;
    return Align(
      alignment: minha ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        decoration: BoxDecoration(
          color: minha ? c.acao : Theme.of(context).colorScheme.surface,
          border: minha ? null : Border.all(color: c.linha),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(minha ? 18 : 4),
            bottomRight: Radius.circular(minha ? 4 : 18),
          ),
        ),
        child: Column(crossAxisAlignment: minha ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
          if (!minha)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(m.autor == null ? 'Equipe iService' : '${m.autor} · Equipe iService',
                  style: t.labelSmall?.copyWith(color: c.acaoTexto, fontWeight: FontWeight.w700)),
            ),
          SelectableText(m.texto, style: t.bodyMedium?.copyWith(color: minha ? c.textoNaAcao : null)),
          const SizedBox(height: 2),
          Text(diaRelativoEHora(m.criadaEm), style: t.labelSmall?.copyWith(color: minha ? c.textoNaAcao.withValues(alpha: .75) : c.textoSuave)),
        ]),
      ),
    );
  }
}
