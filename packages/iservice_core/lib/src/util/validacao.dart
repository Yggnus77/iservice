import 'formatos.dart';

/// Validações dos formulários. Cada uma devolve a mensagem de erro ou null.
abstract final class Validar {
  static String? obrigatorio(String? v, [String campo = 'Este campo']) =>
      (v == null || v.trim().isEmpty) ? '$campo é obrigatório.' : null;

  static String? nomeCompleto(String? v) {
    final n = (v ?? '').trim();
    if (n.isEmpty) return 'Informe seu nome.';
    if (!n.contains(' ') || n.length < 5) return 'Informe nome e sobrenome.';
    return null;
  }

  static bool cpfValido(String cpf) {
    final d = soDigitos(cpf);
    if (d.length != 11 || RegExp(r'^(\d)\1{10}$').hasMatch(d)) return false;
    final n = d.split('').map(int.parse).toList();
    int dv(int ate) {
      var s = 0;
      for (var i = 0; i < ate; i++) {
        s += n[i] * (ate + 1 - i);
      }
      final r = s % 11;
      return r < 2 ? 0 : 11 - r;
    }

    return dv(9) == n[9] && dv(10) == n[10];
  }

  static String? cpf(String? v) => cpfValido(v ?? '') ? null : 'CPF inválido. Confira os números.';

  static String? telefone(String? v) {
    final d = soDigitos(v ?? '');
    return d.length == 11 && d[2] == '9' ? null : 'Informe um celular com DDD.';
  }

  static String? nascimento(String? v) {
    final data = lerData(v ?? '');
    if (data == null) return 'Use o formato dd/mm/aaaa.';
    final hoje = DateTime.now();
    final idade = hoje.year - data.year - ((hoje.month < data.month || (hoje.month == data.month && hoje.day < data.day)) ? 1 : 0);
    if (idade < 18) return 'É preciso ter 18 anos ou mais.';
    if (idade > 110) return 'Confira o ano de nascimento.';
    return null;
  }

  static String? email(String? v) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'E-mail inválido.';

  static String? senha(String? v) {
    final s = v ?? '';
    if (s.length < 8) return 'Use pelo menos 8 caracteres.';
    if (!RegExp(r'[A-Za-z]').hasMatch(s) || !RegExp(r'\d').hasMatch(s)) return 'Misture letras e números.';
    return null;
  }

  static String? cep(String? v) {
    final d = soDigitos(v ?? '');
    return d.isEmpty || d.length == 8 ? null : 'CEP com 8 números.';
  }
}
