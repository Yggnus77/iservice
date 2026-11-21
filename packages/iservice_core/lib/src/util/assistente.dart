import '../telas/ajuda.dart';

/// O que o assistente do chat entendeu da mensagem.
enum IntencaoAssistente { pergunta, saudacao, agradecimento, falarComPessoa, emergencia }

class RespostaAssistente {
  const RespostaAssistente({required this.intencao, this.melhor, this.parecidas = const []});
  final IntencaoAssistente intencao;

  /// A pergunta da Central de Ajuda que melhor responde (null: não encontrou).
  final PerguntaAjuda? melhor;

  /// Outras perguntas próximas, para a pessoa escolher.
  final List<PerguntaAjuda> parecidas;
}

const _vazias = {
  'de', 'da', 'do', 'das', 'dos', 'o', 'a', 'os', 'as', 'um', 'uma', 'uns', 'umas', 'e', 'que', 'como', 'para', 'pra', 'pro',
  'por', 'no', 'na', 'nos', 'nas', 'com', 'meu', 'minha', 'meus', 'minhas', 'eu', 'me', 'se', 'em', 'ao', 'aos', 'ou', 'mas',
  'mais', 'muito', 'ja', 'tem', 'ter', 'esta', 'estou', 'isso', 'esse', 'essa', 'aqui', 'ai', 'qual', 'quais', 'onde', 'quando',
  'porque', 'pq', 'voce', 'vc', 'vcs', 'ele', 'ela', 'favor', 'gostaria', 'queria', 'quero', 'preciso', 'posso', 'pode', 'consigo',
  'fazer', 'faco', 'faz', 'sobre', 'tudo', 'app', 'aplicativo', 'iservice', 'ola', 'oi', 'bom', 'boa', 'dia', 'tarde', 'noite',
  'ajuda', 'ajudar', 'duvida', 'tenho', 'sei', 'saber', 'agora', 'hoje',
};

/// Minúsculas, sem acento e só letras e números.
String normalizarTexto(String s) {
  const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const para = 'aaaaaeeeeiiiiooooouuuucn';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = de.indexOf(ch);
    b.write(i >= 0 ? para[i] : ch);
  }
  return b.toString().replaceAll(RegExp('[^a-z0-9]+'), ' ').trim();
}

/// Raiz simples: as 5 primeiras letras. "cancelar", "cancelei" e "cancelamento" viram "cance".
String _raiz(String p) => p.length > 5 ? p.substring(0, 5) : p;

Set<String> _raizes(String texto) => {
      for (final p in normalizarTexto(texto).split(' '))
        if ((p.length >= 3 || p == 'pix') && !_vazias.contains(p)) _raiz(p),
    };

bool _temAlguma(Set<String> raizes, List<String> lista) => lista.any((x) => raizes.contains(_raiz(x)));

/// Entende a mensagem e procura a melhor resposta na Central de Ajuda.
RespostaAssistente responderAssistente(String mensagem, List<PerguntaAjuda> perguntas) {
  final norm = normalizarTexto(mensagem);
  final palavras = norm.split(' ').where((p) => p.isNotEmpty).toList();
  final raizes = _raizes(mensagem);

  if (_temAlguma(raizes, const ['emergencia', 'socorro', 'perigo', 'assalto', 'agressao', 'agrediu', 'ameaca', 'ameacou', 'acidente', 'ferido'])) {
    final melhor = perguntas.where((p) => _raizes(p.palavras).contains('emerg')).firstOrNull;
    return RespostaAssistente(intencao: IntencaoAssistente.emergencia, melhor: melhor);
  }
  if (_temAlguma(raizes, const ['atendente', 'humano', 'pessoa', 'alguem', 'atendimento', 'suporte']) && raizes.length <= 4) {
    return const RespostaAssistente(intencao: IntencaoAssistente.falarComPessoa);
  }
  if (raizes.isEmpty) {
    final agradeceu = palavras.any((p) => p.startsWith('obrigad') || p == 'valeu' || p == 'vlw');
    return RespostaAssistente(intencao: agradeceu ? IntencaoAssistente.agradecimento : IntencaoAssistente.saudacao);
  }
  if (raizes.every((r) => r.startsWith('obrig') || r == 'valeu' || r == 'certo' || r == 'blz' || r == 'beleza' || r == 'resol')) {
    return const RespostaAssistente(intencao: IntencaoAssistente.agradecimento);
  }

  final notas = <(PerguntaAjuda, double)>[];
  for (final p in perguntas) {
    final daPergunta = _raizes(p.pergunta);
    final dasPalavras = _raizes(p.palavras);
    final daCategoria = _raizes(p.categoria);
    final daResposta = _raizes(p.resposta);
    var nota = 0.0;
    for (final r in raizes) {
      if (daPergunta.contains(r) || dasPalavras.contains(r)) {
        nota += 3;
      } else if (daCategoria.contains(r)) {
        nota += 1;
      } else if (daResposta.contains(r)) {
        nota += .5;
      }
    }
    // Expressões inteiras das palavras ("não respondeu", "esqueci a senha") valem mais.
    for (final exp in p.palavras.split(',')) {
      final e = normalizarTexto(exp);
      if (e.contains(' ') && ' $norm '.contains(' $e ')) nota += 4;
    }
    if (nota > 0) notas.add((p, nota));
  }
  notas.sort((a, b) => b.$2.compareTo(a.$2));
  final boas = notas.where((n) => n.$2 >= 3).toList();
  if (boas.isEmpty) return const RespostaAssistente(intencao: IntencaoAssistente.pergunta);
  return RespostaAssistente(
    intencao: IntencaoAssistente.pergunta,
    melhor: boas.first.$1,
    parecidas: [for (final n in boas.skip(1).take(2)) if (n.$2 >= boas.first.$2 * .5) n.$1],
  );
}
