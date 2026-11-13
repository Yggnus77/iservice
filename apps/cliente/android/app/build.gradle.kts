import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Chave de upload da Play Store (nunca vai para o git).
// Lida de android/key.properties (no computador) ou de variáveis de ambiente
// (no GitHub Actions: ANDROID_KEYSTORE_PATH, ANDROID_KEYSTORE_SENHA, ANDROID_KEY_ALIAS).
// Sem a chave, o release continua assinado com a chave debug (só para testes).
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) FileInputStream(f).use { load(it) }
}
fun chave(prop: String, env: String): String? =
    (keyProps.getProperty(prop) ?: System.getenv(env))?.takeIf { it.isNotBlank() }
val keystorePath = chave("storeFile", "ANDROID_KEYSTORE_PATH")
val keystoreSenha = chave("storePassword", "ANDROID_KEYSTORE_SENHA")
val aliasChave = chave("keyAlias", "ANDROID_KEY_ALIAS") ?: "upload"
val senhaChave = chave("keyPassword", "ANDROID_KEY_SENHA") ?: keystoreSenha
val temChaveUpload = keystorePath != null && keystoreSenha != null && file(keystorePath).exists()

android {
    namespace = "br.app.iservice.cliente"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "br.app.iservice.cliente"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (temChaveUpload) {
            create("upload") {
                storeFile = file(keystorePath!!)
                storePassword = keystoreSenha
                keyAlias = aliasChave
                keyPassword = senhaChave
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (temChaveUpload) {
                signingConfigs.getByName("upload")
            } else {
                logger.warn("iService: chave de upload ausente; release assinado com a chave debug (não serve para a Play Store).")
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
