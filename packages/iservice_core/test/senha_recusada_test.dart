import 'package:flutter_test/flutter_test.dart';
import 'package:iservice_core/src/dados/repositorios.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('senha vazada explica o vazamento', () {
    final e = ErroIService.de(AuthWeakPasswordException(
      message: 'Password is known to be weak and easy to guess, please choose a different one.',
      statusCode: '422',
      reasons: const ['pwned'],
    ));
    expect(e.codigo, 'senha_vazada');
    expect(e.mensagem, contains('vazamentos'));
  });

  test('senha curta diz o que falta', () {
    expect(mensagemSenhaRecusada(const ['length']), 'A senha precisa ter pelo menos 8 caracteres.');
    expect(mensagemSenhaRecusada(const ['length', 'characters']), 'A senha precisa ter pelo menos 8 caracteres e misturar letras e números.');
  });

  test('mensagem sem motivos ainda reconhece vazamento', () {
    expect(mensagemSenhaRecusada(const [], 'Password is known to be weak and easy to guess'), contains('vazamentos'));
  });
}
