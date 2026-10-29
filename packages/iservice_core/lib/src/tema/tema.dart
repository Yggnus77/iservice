import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config.dart';
import 'cores.dart';

/// Raios e espaçamentos do design system.
abstract final class Medidas {
  static const raioCartao = 16.0;
  static const raioControle = 12.0;
  static const raioPilula = 999.0;
  static const margemTela = 20.0;
  static const alturaBotao = 52.0;
}

/// Tema do app. O Cliente usa azul como cor de ação; o Profissional, laranja
/// com texto azul-escuro por cima (o branco não tem contraste no laranja).
ThemeData temaIService(AppIService app, {Brightness brilho = Brightness.light, bool letraGrande = false}) {
  final escuro = brilho == Brightness.dark;
  final pro = app == AppIService.profissional;

  final cores = CoresApp(
    acao: pro ? Cores.laranja : (escuro ? Cores.azulEscuroModo : Cores.azul),
    textoNaAcao: pro ? Cores.azulEscuro : (escuro ? Cores.fundoEscuro : Colors.white),
    acaoTexto: pro ? (escuro ? const Color(0xFFFF9F2E) : Cores.laranjaTexto) : (escuro ? Cores.azulEscuroModo : Cores.azul),
    acaoSuave: pro ? (escuro ? const Color(0xFF3A2306) : const Color(0xFFFFF1DF)) : (escuro ? const Color(0xFF12305F) : Cores.azulSuave),
    gradienteAcao: pro ? Cores.gradienteLaranja : Cores.gradienteAzul,
    superficieSuave: escuro ? Cores.superficieSuaveEscura : Cores.superficieSuave,
    linha: escuro ? Cores.linhaEscura : Cores.linha,
    textoSuave: escuro ? Cores.textoSuaveEscuro : Cores.textoSuave,
    sucesso: escuro ? const Color(0xFF2EE07A) : Cores.verdeTexto,
    sucessoSuave: escuro ? const Color(0xFF06331C) : Cores.verdeSuave,
    alerta: escuro ? const Color(0xFFFF9F2E) : Cores.laranjaTexto,
    alertaSuave: escuro ? const Color(0xFF3A2306) : Cores.laranjaSuave,
    perigo: escuro ? const Color(0xFFFF6B6B) : Cores.perigo,
    perigoSuave: escuro ? const Color(0xFF3A1414) : Cores.perigoSuave,
  );

  final texto = escuro ? Cores.textoEscuro : Cores.texto;
  final fundo = escuro ? Cores.fundoEscuro : Cores.fundo;
  final superficie = escuro ? Cores.superficieEscura : Cores.superficie;

  final esquema = ColorScheme(
    brightness: brilho,
    primary: cores.acao,
    onPrimary: cores.textoNaAcao,
    secondary: pro ? Cores.azul : Cores.laranja,
    onSecondary: pro ? Colors.white : Cores.azulEscuro,
    error: cores.perigo,
    onError: escuro ? Cores.fundoEscuro : Colors.white,
    surface: superficie,
    onSurface: texto,
    surfaceContainerHighest: cores.superficieSuave,
    outline: escuro ? const Color(0xFF687BA0) : Cores.bordaControle,
    outlineVariant: cores.linha,
  );

  final base = GoogleFonts.montserratTextTheme(ThemeData(brightness: brilho).textTheme);
  // Tamanhos do design system. "Letra grande" (acessibilidade) aumenta tudo em 15%.
  final escala = letraGrande ? 1.15 : 1.0;
  TextStyle t(TextStyle? s, double tam, FontWeight peso, double altura) =>
      (s ?? const TextStyle()).copyWith(fontSize: tam * escala, fontWeight: peso, height: altura / tam, color: texto);
  final tipografia = base.copyWith(
    displaySmall: t(base.displaySmall, 30, FontWeight.w800, 38),
    headlineMedium: t(base.headlineMedium, 24, FontWeight.w700, 31),
    headlineSmall: t(base.headlineSmall, 20, FontWeight.w700, 26),
    titleLarge: t(base.titleLarge, 18, FontWeight.w700, 24),
    titleMedium: t(base.titleMedium, 16, FontWeight.w600, 22),
    titleSmall: t(base.titleSmall, 14, FontWeight.w600, 20),
    bodyLarge: t(base.bodyLarge, 16, FontWeight.w400, 24),
    bodyMedium: t(base.bodyMedium, 15, FontWeight.w400, 22),
    bodySmall: t(base.bodySmall, 13, FontWeight.w400, 18).copyWith(color: cores.textoSuave),
    labelLarge: t(base.labelLarge, 15, FontWeight.w600, 20),
    labelMedium: t(base.labelMedium, 13, FontWeight.w600, 18),
    labelSmall: t(base.labelSmall, 11, FontWeight.w600, 14),
  );

  final bordaCampo = OutlineInputBorder(
    borderRadius: BorderRadius.circular(Medidas.raioControle),
    borderSide: BorderSide(color: esquema.outline),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brilho,
    colorScheme: esquema,
    scaffoldBackgroundColor: fundo,
    textTheme: tipografia,
    extensions: [cores],
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: fundo,
      foregroundColor: texto,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: tipografia.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: superficie,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Medidas.raioCartao),
        side: BorderSide(color: cores.linha),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: cores.acao,
        foregroundColor: cores.textoNaAcao,
        disabledBackgroundColor: cores.superficieSuave,
        disabledForegroundColor: cores.textoSuave,
        minimumSize: const Size.fromHeight(Medidas.alturaBotao),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Medidas.raioControle)),
        textStyle: tipografia.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: texto,
        minimumSize: const Size.fromHeight(Medidas.alturaBotao),
        side: BorderSide(color: cores.linha, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Medidas.raioControle)),
        textStyle: tipografia.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: cores.acaoTexto, textStyle: tipografia.labelLarge),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: superficie,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: bordaCampo,
      enabledBorder: bordaCampo.copyWith(borderSide: BorderSide(color: cores.linha, width: 1.5)),
      focusedBorder: bordaCampo.copyWith(borderSide: BorderSide(color: cores.acao, width: 2)),
      errorBorder: bordaCampo.copyWith(borderSide: BorderSide(color: cores.perigo, width: 1.5)),
      labelStyle: tipografia.bodyMedium?.copyWith(color: cores.textoSuave),
      hintStyle: tipografia.bodyMedium?.copyWith(color: cores.textoSuave),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: superficie,
      selectedColor: cores.acaoSuave,
      side: BorderSide(color: cores.linha),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Medidas.raioPilula)),
      labelStyle: tipografia.labelMedium,
      checkmarkColor: cores.acaoTexto,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: superficie,
      indicatorColor: cores.acaoSuave,
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => tipografia.labelSmall?.copyWith(color: s.contains(WidgetState.selected) ? cores.acaoTexto : cores.textoSuave),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? cores.acaoTexto : cores.textoSuave),
      ),
    ),
    dividerTheme: DividerThemeData(color: cores.linha, space: 1, thickness: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Cores.azulEscuro,
      contentTextStyle: tipografia.bodyMedium?.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Medidas.raioControle)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: superficie,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? cores.textoNaAcao : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? cores.acao : null),
    ),
  );
}
