import 'package:intl/intl.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';

final _brl = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 2);
final _brlInteiro = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 0);

/// R$ 1.234,50 (sem centavos quando o valor é redondo).
String reais(num? valor) {
  if (valor == null) return '—';
  return valor == valor.roundToDouble() ? _brlInteiro.format(valor) : _brl.format(valor);
}

String faixaReais(num minimo, num maximo) => '${reais(minimo)} – ${reais(maximo)}';

/// 4,9
String nota(num valor) => valor.toStringAsFixed(1).replaceAll('.', ',');

/// 850 m · 2,3 km
String distancia(num? km) {
  if (km == null) return '';
  if (km < 1) return '${(km * 1000).round()} m';
  return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
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
  final d = int.tryParse(p[0]), m = int.tryParse(p[1]), a = int.tryParse(p[2]);
  if (d == null || m == null || a == null) return null;
  final data = DateTime(a, m, d);
  if (data.day != d || data.month != m) return null;
  return data;
}
