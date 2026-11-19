import 'package:intl/intl.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';

final _brl = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$', decimalDigits: 2);
final _brlInteiro = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$', decimalDigits: 0);

/// R$ 1.234,50 (sem centavos quando o valor é redondo).
String reais(num? valor) {
  if (valor == null) return '—';
  return valor == valor.roundToDouble() ? _brlInteiro.format(valor) : _brl.format(valor);
}

String faixaReais(num minimo, num maximo) => '${reais(minimo)} – ${reais(maximo)}';

/// 4,9
String nota(num valor) => valor.toStringAsFixed(1).replaceAll('.', ',');

/// Horas trabalhadas no perfil: "45 min", "12 h", "1.240 h".
String horasTrabalhadas(int minutos) {
  if (minutos < 60) return '$minutos min';
  return '${NumberFormat.decimalPattern('pt_BR').format(minutos ~/ 60)} h';
}

/// Duração de um serviço: "45 min", "2 h 10 min".
String duracaoServico(int minutos) {
  if (minutos < 60) return '$minutos min';
  final m = minutos % 60;
  return m == 0 ? '${minutos ~/ 60} h' : '${minutos ~/ 60} h $m min';
}

/// 850 m · 2,3 km
String distancia(num? km) {
  if (km == null) return '';
  if (km < 1) return '${(km * 1000).round()} m';
  return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
}

/// "menos de 1 min" · "cerca de 3 min"
String tempoResposta(int segundos) {
  if (segundos < 60) return 'menos de 1 min';
  return 'cerca de ${(segundos / 60).ceil()} min';
}

String primeiroNome(String nome) => nome.trim().split(RegExp(r'\s+')).first;

String hora(DateTime d) => DateFormat.Hm('pt_BR').format(d.toLocal());

/// "Hoje, 14:30" · "Ontem" · "12 de out."
String quandoFoi(DateTime d) {
  final local = d.toLocal();
  final agora = DateTime.now();
  final hoje = DateTime(agora.year, agora.month, agora.day);
  final dia = DateTime(local.year, local.month, local.day);
  final dif = hoje.difference(dia).inDays;
  if (dif == 0) return 'Hoje, ${hora(local)}';
  if (dif == 1) return 'Ontem, ${hora(local)}';
  if (dif < 7) return '${DateFormat.EEEE('pt_BR').format(local)}, ${hora(local)}';
  return DateFormat("d 'de' MMM", 'pt_BR').format(local);
}

String dataCurta(DateTime d) => DateFormat('dd/MM/yyyy').format(d.toLocal());

/// "Ter, 27/10 às 14:00"
String diaEHora(DateTime d) {
  final l = d.toLocal();
  final s = DateFormat("EEE, dd/MM 'às' HH:mm", 'pt_BR').format(l);
  return s[0].toUpperCase() + s.substring(1);
}

/// "Hoje às 15:30" · "Amanhã às 09:00" · "Sexta, 14/11 às 09:00"
String diaRelativoEHora(DateTime d) => '${diaRelativo(d)} às ${hora(d)}';

/// "Hoje" · "Amanhã" · "Sexta, 14/11"
String diaRelativo(DateTime d) {
  final l = d.toLocal();
  final agora = DateTime.now();
  final dif = DateTime(l.year, l.month, l.day).difference(DateTime(agora.year, agora.month, agora.day)).inDays;
  if (dif == 0) return 'Hoje';
  if (dif == 1) return 'Amanhã';
  final s = DateFormat('EEEE, dd/MM', 'pt_BR').format(l).replaceFirst('-feira', '');
  return s[0].toUpperCase() + s.substring(1);
}

String soDigitos(String s) => s.replaceAll(RegExp(r'\D'), '');

MaskTextInputFormatter mascaraCpf() => MaskTextInputFormatter(mask: '###.###.###-##', filter: {'#': RegExp(r'\d')});
MaskTextInputFormatter mascaraTelefone() => MaskTextInputFormatter(mask: '(##) # ####-####', filter: {'#': RegExp(r'\d')});
MaskTextInputFormatter mascaraCep() => MaskTextInputFormatter(mask: '#####-###', filter: {'#': RegExp(r'\d')});
MaskTextInputFormatter mascaraData() => MaskTextInputFormatter(mask: '##/##/####', filter: {'#': RegExp(r'\d')});

String cpfFormatado(String cpf) {
  final d = soDigitos(cpf);
  if (d.length != 11) return cpf;
  return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9)}';
}

String telefoneFormatado(String tel) {
  final d = soDigitos(tel);
  if (d.length != 11) return tel;
  return '(${d.substring(0, 2)}) ${d[2]} ${d.substring(3, 7)}-${d.substring(7)}';
}

/// Converte 'dd/mm/aaaa' em data, ou null se inválida.
DateTime? lerData(String s) {
  final p = s.split('/');
  if (p.length != 3 || p[2].length != 4) return null;
  final d = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  final a = int.tryParse(p[2]);
  if (d == null || m == null || a == null) return null;
  final data = DateTime(a, m, d);
  if (data.day != d || data.month != m) return null;
  return data;
}

/// Regra do acréscimo fora do horário comercial, em uma linha para o cliente.
/// Lê `acrescimo_fora_horario` (0,2 = 20%) e `horario_comercial` da configuração.
String textoAcrescimoForaHorario(Map<String, dynamic> config) {
  final pct = ((config['acrescimo_fora_horario'] as num?)?.toDouble() ?? 0.2) * 100;
  if (pct <= 0) return 'Sem acréscimo fora do horário comercial.';
  final h = config['horario_comercial'];
  String faixa(Object? v) {
    if (v is! List || v.length < 2) return '';
    String hora(Object? x) {
      final p = '$x'.split(':');
      final m = p.length > 1 ? p[1] : '00';
      return m == '00' ? '${int.tryParse(p.first) ?? p.first}h' : '${int.tryParse(p.first) ?? p.first}h$m';
    }
    return '${hora(v[0])} às ${hora(v[1])}';
  }
  final semana = h is Map ? faixa(h['semana']) : '8h às 18h';
  final sabado = h is Map ? faixa(h['sabado']) : '8h às 12h';
  final horario = [
    if (semana.isNotEmpty) 'segunda a sexta, $semana',
    if (sabado.isNotEmpty) 'sábado, $sabado',
  ].join('; ');
  final p = pct == pct.roundToDouble() ? pct.toStringAsFixed(0) : pct.toStringAsFixed(1).replaceAll('.', ',');
  return 'Fora do horário comercial ($horario), em domingos e feriados, a plataforma acrescenta $p% ao preço do profissional.';
}


/// Deslocamento somado a todo pedido: parte fixa + valor por km entre o profissional
/// e o cliente (mesma regra de public.valor_deslocamento). O cliente vê um valor só,
/// já com o deslocamento. Os números vêm do app_config ao carregar a configuração.
class Deslocamento {
  Deslocamento._();
  static double base = 20;
  static double porKm = 1.5;
  static double taxaServico = 0.1;
  static bool taxaServicoAtiva = false;

  static void configurar(Map<String, dynamic> config) {
    base = (config['deslocamento_base'] as num?)?.toDouble() ?? base;
    porKm = (config['deslocamento_por_km'] as num?)?.toDouble() ?? porKm;
    taxaServico = (config['taxa_servico'] as num?)?.toDouble() ?? taxaServico;
    taxaServicoAtiva = config['taxa_servico_ativa'] == true;
  }

  /// Valor do deslocamento para a distância (arredondado a R$ 1).
  static double valor(double? km) => km == null || km < 0 ? 0 : (base + km * porKm).roundToDouble();

  /// Taxa de serviço do cliente sobre um valor (0 enquanto estiver desligada).
  static double taxaSobre(double valor) =>
      !taxaServicoAtiva || valor <= 0 ? 0 : (valor * taxaServico * 100).roundToDouble() / 100;
}


/// O texto tem telefone, e-mail, link, @ de rede social ou Pix/WhatsApp?
/// Mesma ideia de public.ocultar_contatos (o banco esconde de qualquer jeito;
/// aqui o app avisa antes de enviar).
bool temContato(String texto) {
  final padroes = [
    RegExp(r'[A-Za-z0-9._%+-]+\s*(@|\(at\)|\[at\])\s*[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+', caseSensitive: false),
    RegExp(r'(https?://|www\.)\S+', caseSensitive: false),
    RegExp(r'\b[A-Za-z0-9-]+\.(com|net|org|me|app|io|ly|link|bio|site|online|br)(\.br)?\b', caseSensitive: false),
    RegExp(r'(^|\s)@[A-Za-z0-9._]{3,}'),
    RegExp(r'\+?\d([\s().-]*\d){8,}'),
    RegExp(r'\b(pix|whats\s*app|whats|zap\s*zap|zap|wpp|telegram|instagram|insta|facebook|messenger|signal)\b', caseSensitive: false),
  ];
  return padroes.any((r) => r.hasMatch(texto));
}

/// Texto do aviso mostrado quando alguém tenta passar um contato.
const avisoContatoOculto =
    'Por segurança, não é permitido trocar telefone, e-mail, redes sociais ou Pix. '
    'Tudo é combinado e pago pela plataforma, com garantia do iService. '
    'Se enviar, esse trecho aparece como "[contato oculto]".';
