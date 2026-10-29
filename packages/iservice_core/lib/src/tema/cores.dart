import 'package:flutter/material.dart';

/// Tokens do design system iService (guia de identidade de 23/10/2026).
/// Regra de contraste: nunca texto branco sobre laranja ou verde.
abstract final class Cores {
  static const azul = Color(0xFF0052CC);
  static const laranja = Color(0xFFFF8A00);
  static const verde = Color(0xFF00C853);
  static const azulEscuro = Color(0xFF0A1F44);
  static const estrela = Color(0xFFFFB400);
  static const noite = Color(0xFF011031);

  static const fundo = Color(0xFFF4F6FB);
  static const superficie = Color(0xFFFFFFFF);
  static const superficieSuave = Color(0xFFEEF2F8);
  static const linha = Color(0xFFE1E6EF);
  static const bordaControle = Color(0xFF7A879D);
  static const texto = Color(0xFF0A1F44);
  static const textoSuave = Color(0xFF4A5B78);

  static const azulSuave = Color(0xFFE8F0FC);
  static const laranjaTexto = Color(0xFFB25F00);
  static const laranjaSuave = Color(0xFFFFF4E5);
  static const verdeTexto = Color(0xFF00873A);
  static const verdeSuave = Color(0xFFE6F9EE);
  static const perigo = Color(0xFFC62828);
  static const perigoSuave = Color(0xFFFDECEC);

  // Modo escuro
  static const fundoEscuro = Color(0xFF06122B);
  static const superficieEscura = Color(0xFF0E2149);
  static const superficieSuaveEscura = Color(0xFF142A58);
  static const linhaEscura = Color(0xFF213A6B);
  static const textoEscuro = Color(0xFFEEF2FA);
  static const textoSuaveEscuro = Color(0xFFA6B3CC);
  static const azulEscuroModo = Color(0xFF5B9BFF);

  static const gradienteMarca = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0A1F44), Color(0xFF0D3A8C)],
  );
  static const gradienteAzul = LinearGradient(colors: [Color(0xFF1A6CF0), Color(0xFF0046B8)]);
  static const gradienteLaranja = LinearGradient(colors: [Color(0xFFFFA133), Color(0xFFFF7A00)]);

  /// Imagem da marca (profissional de costas, logo e categorias). O profissional fica
  /// à esquerda; em telas em pé, [focoFundo] mostra ele em vez de cortar o logo ao meio.
  static const imagemFundo = AssetImage('assets/fundo.jpg', package: 'iservice_core');
  static const focoFundo = Alignment.centerLeft;

  /// Recorte da mesma imagem só com o telhado e a casa, sem textos, para cabeçalhos e cartões.
  static const imagemCabecalho = AssetImage('assets/fundo-cabecalho.jpg', package: 'iservice_core');

  /// Fundo das áreas escuras da marca: a imagem com uma camada azul-escura por cima,
  /// para o texto branco continuar legível. [escurecer] vai de 0 (só a imagem) a 1.
  /// Por padrão usa o recorte sem textos; telas cheias passam [imagemFundo].
  static BoxDecoration fundoMarca({
    double escurecer = .78,
    BorderRadius? raio,
    Alignment alinhamento = Alignment.center,
    ImageProvider imagem = imagemCabecalho,
  }) =>
      BoxDecoration(
        color: azulEscuro,
        borderRadius: raio,
        image: DecorationImage(
          image: imagem,
          fit: BoxFit.cover,
          alignment: alinhamento,
          colorFilter: ColorFilter.mode(azulEscuro.withValues(alpha: escurecer), BlendMode.srcOver),
        ),
      );
}

/// Cores que mudam entre o app Cliente (azul) e o Profissional (laranja).
@immutable
class CoresApp extends ThemeExtension<CoresApp> {
  const CoresApp({
    required this.acao,
    required this.textoNaAcao,
    required this.acaoTexto,
    required this.acaoSuave,
    required this.gradienteAcao,
    required this.superficieSuave,
    required this.linha,
    required this.textoSuave,
    required this.sucesso,
    required this.sucessoSuave,
    required this.alerta,
    required this.alertaSuave,
    required this.perigo,
    required this.perigoSuave,
  });

  /// Cor dos botões principais.
  final Color acao;

  /// Cor do texto em cima de [acao].
  final Color textoNaAcao;

  /// Cor da ação quando usada como texto/ícone sobre o fundo.
  final Color acaoTexto;
  final Color acaoSuave;
  final Gradient gradienteAcao;
  final Color superficieSuave;
  final Color linha;
  final Color textoSuave;
  final Color sucesso;
  final Color sucessoSuave;
  final Color alerta;
  final Color alertaSuave;
  final Color perigo;
  final Color perigoSuave;

  @override
  CoresApp copyWith({Color? acao}) => CoresApp(
        acao: acao ?? this.acao,
        textoNaAcao: textoNaAcao,
        acaoTexto: acaoTexto,
        acaoSuave: acaoSuave,
        gradienteAcao: gradienteAcao,
        superficieSuave: superficieSuave,
        linha: linha,
        textoSuave: textoSuave,
        sucesso: sucesso,
        sucessoSuave: sucessoSuave,
        alerta: alerta,
        alertaSuave: alertaSuave,
        perigo: perigo,
        perigoSuave: perigoSuave,
      );

  @override
  CoresApp lerp(CoresApp? other, double t) => t < .5 || other == null ? this : other;
}

extension CoresDoContexto on BuildContext {
  CoresApp get cores => Theme.of(this).extension<CoresApp>()!;
}
