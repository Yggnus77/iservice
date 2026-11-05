package br.app.iservice.profissional

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        criarCanalDeAvisos()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Com o app aberto o FCM não mostra o aviso sozinho: o Flutter pede aqui
        // para pô-lo na barra de notificações, no canal com o som do iService.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "br.app.iservice/avisos").setMethodCallHandler { chamada, resposta ->
            if (chamada.method == "mostrar") {
                mostrarAviso(chamada.argument<String>("titulo") ?: "iService", chamada.argument<String>("corpo") ?: "")
                resposta.success(null)
            } else {
                resposta.notImplemented()
            }
        }
    }

    private val som: Uri get() = Uri.parse("android.resource://$packageName/${R.raw.iservice_som}")

    /**
     * Canal de notificação com o som da marca (a caixinha "i-ser-vice").
     * No Android 8+ o som pertence ao canal e não muda depois de criado: para trocar
     * o som no futuro, crie um canal com outro id (ex.: iservice_avisos_v2) e use-o
     * também em supabase/functions/enviar-push e no AndroidManifest.
     */
    private fun criarCanalDeAvisos() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val atributos = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val canal = NotificationChannel(CANAL_AVISOS, "Avisos do iService", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Pedidos, mensagens e andamento do serviço"
            setSound(som, atributos)
            enableVibration(true)
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(canal)
    }

    private fun mostrarAviso(titulo: String, corpo: String) {
        val abrir = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val construtor = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CANAL_AVISOS)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this).setSound(som).setPriority(Notification.PRIORITY_HIGH)
        }
        val aviso = construtor
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(titulo)
            .setContentText(corpo)
            .setStyle(Notification.BigTextStyle().bigText(corpo))
            .setAutoCancel(true)
            .setContentIntent(abrir)
            .build()
        // Sem a permissão de notificações (Android 13+) o sistema só ignora o aviso.
        getSystemService(NotificationManager::class.java).notify(System.currentTimeMillis().toInt(), aviso)
    }

    companion object {
        const val CANAL_AVISOS = "iservice_avisos_v1"
    }
}
