import 'package:supabase_flutter/supabase_flutter.dart';

/// Qual dos dois apps está rodando. Muda cores, textos e o fluxo de cadastro.
enum AppIService { cliente, profissional }

/// Endereço e chave pública do backend, passados na compilação:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
/// A chave pública pode ir no app: quem protege os dados são as regras do banco.
class ConfigIService {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Bucket público onde ficam fotos de perfil, portfólio e avaliações.
  static const bucketsPublicos = {'fotos', 'portfolio', 'avaliacoes'};

  static bool get configurado => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static Future<void> iniciar() async {
    if (!configurado) {
      throw StateError(
        'Faltam SUPABASE_URL e SUPABASE_ANON_KEY. Rode com --dart-define-from-file=config/dev.json.',
      );
    }
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  }
}

SupabaseClient get supabase => Supabase.instance.client;
