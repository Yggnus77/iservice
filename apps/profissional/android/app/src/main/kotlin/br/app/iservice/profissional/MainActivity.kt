package br.app.iservice.profissional

import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        criarCanalDeAvisos()
    }

    /**
     * Canal de notificação com o som da marca (a caixinha "i-ser-vice").
     * No Android 8+ o som pertence ao canal e não muda depois de criado: para trocar
     * o som no futuro, crie um canal com outro id (ex.: iservice_avisos_v2) e use-o
     * também em supabase/functions/enviar-push e no AndroidManifest.
     */
    private fun criarCanalDeAvisos() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val som = Uri.parse("android.resource://$packageName/${R.raw.iservice_som}")
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

    companion object {
        const val CANAL_AVISOS = "iservice_avisos_v1"
    }
}
