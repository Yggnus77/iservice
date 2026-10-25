import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Ícones das profissões. O banco guarda o nome do Material Symbol; aqui ele
/// vira o ícone (lista fixa para o app não carregar a fonte inteira).
const _icones = <String, IconData>{
  'bolt': Symbols.bolt_rounded,
  'plumbing': Symbols.plumbing_rounded,
  'key': Symbols.key_rounded,
  'directions_car': Symbols.directions_car_rounded,
  'child_care': Symbols.child_care_rounded,
  'cleaning_services': Symbols.cleaning_services_rounded,
  'format_paint': Symbols.format_paint_rounded,
  'handyman': Symbols.handyman_rounded,
  'potted_plant': Symbols.potted_plant_rounded,
  'foundation': Symbols.foundation_rounded,
  'pets': Symbols.pets_rounded,
  'ac_unit': Symbols.ac_unit_rounded,
  'local_shipping': Symbols.local_shipping_rounded,
  'chair': Symbols.chair_rounded,
  'weekend': Symbols.weekend_rounded,
  'face_retouching_natural': Symbols.face_retouching_natural_rounded,
};

IconData iconeProfissao(String nome) => _icones[nome] ?? Symbols.home_repair_service_rounded;

Color corHex(String hex) => Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));
