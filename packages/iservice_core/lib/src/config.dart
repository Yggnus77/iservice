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

  /// Endereço público onde ficam as versões web dos apps (links de e-mail voltam para cá).
  static const urlSite = String.fromEnvironment('URL_SITE', defaultValue: 'https://iservice.app.br');

  static String urlDoApp(AppIService app) => '$urlSite/${app.name}/';

  /// Botão "Entrar com Google". Fica desligado até o Google estar configurado
  /// no Supabase (Authentication > Sign In / Providers > Google). Ligar com
  /// --dart-define=LOGIN_GOOGLE=true.
  static const loginGoogle = bool.fromEnvironment('LOGIN_GOOGLE');

  /// Endereço para onde o login com Google volta no celular (deep link do app).
  static String retornoLogin(AppIService app) => 'br.app.iservice.${app.name}://login-callback/';

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
