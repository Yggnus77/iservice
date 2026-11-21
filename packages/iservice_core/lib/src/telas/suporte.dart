import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../tema/cores.dart';
import '../tema/tema.dart';
import '../util/assistente.dart';
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

/// Uma fala do assistente (ou da pessoa, antes de ir para a equipe). Fica só no aparelho.
class _ItemBot {
  _ItemBot.pessoa(this.texto)
      : daPessoa = true,
        titulo = null,
        sugestoes = const [],
        oferecerPessoa = false,
        perguntaOriginal = null;
  _ItemBot.assistente(this.texto, {this.titulo, this.sugestoes = const [], this.oferecerPessoa = false, this.perguntaOriginal})
      : daPessoa = false;
  final bool daPessoa;
  final String texto;
  final String? titulo;
  final List<PerguntaAjuda> sugestoes;
  bool oferecerPessoa;
  final String? perguntaOriginal;
}

/// "Falar com o suporte": primeiro o assistente responde com a Central de Ajuda; se não
/// resolver, a conversa vai para a equipe (caixa do suporte do painel), igual nos dois apps.
class TelaSuporte extends ConsumerStatefulWidget {
  const TelaSuporte({super.key});

  @override
  ConsumerState<TelaSuporte> createState() => _TelaSuporteState();
}

class _TelaSuporteState extends ConsumerState<TelaSuporte> with WidgetsBindingObserver {
  final _texto = TextEditingController();
  final _bot = <_ItemBot>[];
  _EstadoSuporte? _estado;
  Object? _erro;
  bool _enviando = false;
  bool _comPessoa = false;
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

  /// Com a equipe: há atendimento aberto, ou a pessoa pediu para falar com alguém.
  bool get _modoPessoa {
    final e = _estado;
    return e != null && (_comPessoa || (e.protocolo != null && !e.encerrada));
  }

  Future<void> _carregar() async {
    try {
      final r = await supabase.rpc('suporte_app_estado');
      if (mounted) setState(() { _estado = _EstadoSuporte(Map<String, dynamic>.from(r as Map)); _erro = null; });
    } catch (e) {
      if (mounted && _estado == null) setState(() => _erro = e);
    }
  }

  Future<void> _enviarParaEquipe(String t) async {
    setState(() => _enviando = true);
    try {
      final r = await supabase.rpc('suporte_app_enviar', params: {'p_texto': t});
      if (mounted) setState(() { _estado = _EstadoSuporte(Map<String, dynamic>.from(r as Map)); _comPessoa = true; _bot.clear(); });
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _enviar() async {
    final t = _texto.text.trim();
    if (t.isEmpty || _enviando) return;
    _texto.clear();
    if (_modoPessoa) {
      await _enviarParaEquipe(t);
    } else {
      await _perguntar(t);
    }
  }

  /// O assistente procura a resposta na Central de Ajuda.
  Future<void> _perguntar(String t) async {
    final perguntas = await ref.read(ajudaProvider.future).catchError((_) => <PerguntaAjuda>[]);
    if (!mounted) return;
    final r = responderAssistente(t, perguntas);
    final online = _estado?.online ?? false;
    setState(() {
      _bot.add(_ItemBot.pessoa(t));
      switch (r.intencao) {
        case IntencaoAssistente.saudacao:
          _bot.add(_ItemBot.assistente('Olá! Me conte a sua dúvida em poucas palavras, ou escolha um assunto abaixo.'));
        case IntencaoAssistente.agradecimento:
          _bot.add(_ItemBot.assistente('Por nada! Se precisar de mais alguma coisa, é só escrever.'));
        case IntencaoAssistente.falarComPessoa:
          _comPessoa = true;
          _bot.clear();
        case IntencaoAssistente.emergencia:
          _bot.add(_ItemBot.assistente(
            'Se houver risco agora, ligue 190 (polícia) ou 192 (SAMU). Durante um serviço, use o botão de emergência no pedido: '
            'a equipe do iService é avisada na hora, 24 horas.',
            titulo: 'Emergência',
            oferecerPessoa: true,
            perguntaOriginal: t,
          ));
        case IntencaoAssistente.pergunta:
          final m = r.melhor;
          if (m == null) {
            _bot.add(_ItemBot.assistente(online
                ? 'Não encontrei uma resposta pronta para isso. Passei a sua mensagem para a nossa equipe, que continua por aqui.'
                : 'Não encontrei uma resposta pronta para isso. Passei a sua mensagem para a nossa equipe. Ninguém está online agora; respondemos por aqui assim que alguém entrar.'));
          } else {
            _bot.add(_ItemBot.assistente(m.resposta, titulo: m.pergunta, sugestoes: r.parecidas, oferecerPessoa: true, perguntaOriginal: t));
          }
      }
    });
    if (r.intencao == IntencaoAssistente.pergunta && r.melhor == null) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) await _enviarParaEquipe(t);
    }
  }

  void _mostrarPergunta(PerguntaAjuda p) {
    setState(() {
      for (final b in _bot) {
        b.oferecerPessoa = false;
      }
      _bot.add(_ItemBot.pessoa(p.pergunta));
      _bot.add(_ItemBot.assistente(p.resposta, titulo: p.pergunta, oferecerPessoa: true, perguntaOriginal: p.pergunta));
    });
  }

  void _resolveu(_ItemBot b) => setState(() {
        b.oferecerPessoa = false;
        _bot.add(_ItemBot.assistente('Que bom que ajudou! Se precisar de mais alguma coisa, é só escrever.'));
      });

  Future<void> _naoResolveu(_ItemBot b) async {
    setState(() => b.oferecerPessoa = false);
    await _enviarParaEquipe(b.perguntaOriginal ?? 'Preciso de ajuda.');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final t = Theme.of(context).textTheme;
    final e = _estado;
    final pessoa = _modoPessoa;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          Stack(clipBehavior: Clip.none, children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: c.acaoSuave,
              child: Icon(pessoa ? Symbols.support_agent_rounded : Symbols.smart_toy_rounded, color: c.acaoTexto),
            ),
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
              Text(pessoa ? 'Suporte iService' : 'Assistente iService', style: t.titleSmall),
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
                  if (pessoa && !e.online) _AvisoOffline(estado: e),
                  Expanded(child: pessoa ? _conversaComEquipe(e) : _conversaComAssistente(e)),
                  if (pessoa && e.protocolo != null)
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
                              hintText: pessoa ? 'Escreva para a equipe' : 'Escreva a sua dúvida',
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

  Widget _conversaComEquipe(_EstadoSuporte e) {
    final c = context.cores;
    final t = Theme.of(context).textTheme;
    if (e.mensagens.isEmpty) {
      return EstadoVazio(
        icone: Symbols.support_agent_rounded,
        titulo: 'Fale com a nossa equipe',
        texto: e.online
            ? 'Escreva a sua dúvida. Uma pessoa da equipe responde por aqui.'
            : 'Deixe a sua mensagem. Assim que alguém da equipe entrar, responde por aqui e você recebe um aviso.',
      );
    }
    return ListView.builder(
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
        return _Balao(m: e.mensagens[e.mensagens.length - 1 - (i - (e.encerrada ? 1 : 0))]);
      },
    );
  }

  Widget _conversaComAssistente(_EstadoSuporte e) {
    final c = context.cores;
    final t = Theme.of(context).textTheme;
    final perguntas = ref.watch(ajudaProvider).value ?? const <PerguntaAjuda>[];
    final assuntos = <String>{for (final p in perguntas) p.categoria}.toList();
    final itens = <Widget>[
      if (e.protocolo != null && e.encerrada)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Center(
            child: TextButton.icon(
              onPressed: () => setState(() => _comPessoa = true),
              icon: const Icon(Symbols.history_rounded, size: 18),
              label: Text('Ver o último atendimento (${e.protocolo})'),
            ),
          ),
        ),
      const _BalaoAssistente(
        texto: 'Olá! Sou o assistente do iService. Escreva a sua dúvida ou escolha um assunto. '
            'Se eu não resolver, chamo uma pessoa da nossa equipe.',
      ),
      if (assuntos.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final a in assuntos)
              ActionChip(
                label: Text(a),
                onPressed: () => setState(() {
                  _bot.add(_ItemBot.pessoa(a));
                  _bot.add(_ItemBot.assistente('Sobre $a, estas são as dúvidas mais comuns:',
                      sugestoes: perguntas.where((p) => p.categoria == a).toList()));
                }),
              ),
          ]),
        ),
      for (final b in _bot)
        if (b.daPessoa)
          _Balao(m: _MsgSuporte(id: 0, minha: true, texto: b.texto, criadaEm: DateTime.now()), semHora: true)
        else ...[
          _BalaoAssistente(texto: b.texto, titulo: b.titulo),
          if (b.sugestoes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in b.sugestoes) ActionChip(avatar: const Icon(Symbols.help_rounded, size: 18), label: Text(p.pergunta), onPressed: () => _mostrarPergunta(p)),
              ]),
            ),
          if (b.oferecerPessoa)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                if (b.titulo != 'Emergência')
                  ActionChip(
                    avatar: Icon(Symbols.thumb_up_rounded, size: 18, color: c.sucesso),
                    label: const Text('Resolveu'),
                    onPressed: () => _resolveu(b),
                  ),
                ActionChip(
                  avatar: Icon(Symbols.support_agent_rounded, size: 18, color: c.acaoTexto),
                  label: Text(b.titulo == 'Emergência' ? 'Falar com a equipe' : 'Não resolveu, falar com uma pessoa'),
                  onPressed: _enviando ? null : () => _naoResolveu(b),
                ),
              ]),
            ),
        ],
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Center(
          child: TextButton.icon(
            onPressed: () => setState(() { _comPessoa = true; _bot.clear(); }),
            icon: const Icon(Symbols.support_agent_rounded, size: 18),
            label: const Text('Prefiro falar direto com uma pessoa'),
          ),
        ),
      ),
      Text(e.online ? 'Equipe online agora.' : 'Equipe offline agora. Você também pode escrever para $emailSuporte.',
          textAlign: TextAlign.center, style: t.labelSmall?.copyWith(color: c.textoSuave)),
    ];
    // Lista de baixo para cima: a última fala fica sempre visível perto do campo.
    return ListView(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: itens.reversed.toList(),
    );
  }
}

class _BalaoAssistente extends StatelessWidget {
  const _BalaoAssistente({required this.texto, this.titulo});
  final String texto;
  final String? titulo;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final t = Theme.of(context).textTheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .82),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: c.superficieSuave,
          border: Border.all(color: c.linha),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18), topRight: Radius.circular(18), bottomLeft: Radius.circular(4), bottomRight: Radius.circular(18)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Symbols.smart_toy_rounded, size: 14, color: c.acaoTexto),
            const SizedBox(width: 4),
            Text('Assistente', style: t.labelSmall?.copyWith(color: c.acaoTexto, fontWeight: FontWeight.w700)),
          ]),
          if (titulo != null) ...[
            const SizedBox(height: 4),
            Text(titulo!, style: t.titleSmall),
          ],
          const SizedBox(height: 4),
          SelectableText(texto, style: t.bodyMedium),
        ]),
      ),
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
  const _Balao({required this.m, this.semHora = false});
  final _MsgSuporte m;
  final bool semHora;

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
          if (!semHora) ...[
            const SizedBox(height: 2),
            Text(diaRelativoEHora(m.criadaEm), style: t.labelSmall?.copyWith(color: minha ? c.textoNaAcao.withValues(alpha: .75) : c.textoSuave)),
          ],
        ]),
      ),
    );
  }
}
