import 'package:flutter_test/flutter_test.dart';
import 'package:iservice_core/iservice_core.dart';

void main() {
  test('texto do acréscimo fora do horário segue a configuração', () {
    expect(
      textoAcrescimoForaHorario({
        'acrescimo_fora_horario': 0.2,
        'horario_comercial': {'semana': ['08:00', '18:00'], 'sabado': ['08:00', '12:00'], 'domingo': null},
      }),
      'Fora do horário comercial (segunda a sexta, 8h às 18h; sábado, 8h às 12h), em domingos e feriados, '
      'a plataforma acrescenta 20% ao preço do profissional.',
    );
    expect(textoAcrescimoForaHorario({'acrescimo_fora_horario': 0}), 'Sem acréscimo fora do horário comercial.');
    expect(textoAcrescimoForaHorario({}), contains('20%'));
  });
}
