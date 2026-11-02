# Som da marca iService

Caixinha de música tocando três notas subindo, "i-ser-vice". Escolhido pelo dono do projeto em 02/11/2026
no estúdio de som (página de ajuste ao vivo) com a configuração de `config.json`.

| Arquivo | Uso |
| --- | --- |
| `iservice_som_cliente.wav` | App Cliente: toca a frase uma vez (~1,7 s) |
| `iservice_som_profissional.wav` | App Profissional: novo pedido, a frase toca duas vezes (~2,5 s) |

Nos apps o arquivo se chama sempre `iservice_som`, cada app com a sua versão:

- Android: `android/app/src/main/res/raw/iservice_som.ogg`, tocado pelo canal `iservice_avisos_v1` criado na `MainActivity`.
- iPhone: `ios/Runner/iservice_som.caf` (IMA4), incluído no alvo Runner.
- Envio: `supabase/functions/enviar-push` manda `sound` e `channel_id` em cada push.

Para regerar (mesmo motor da página de ajuste):

```sh
node tools/som/gerar.js
for a in cliente profissional; do
  ffmpeg -y -i tools/som/iservice_som_$a.wav -c:a libvorbis -q:a 6 apps/$a/android/app/src/main/res/raw/iservice_som.ogg
  ffmpeg -y -i tools/som/iservice_som_$a.wav -c:a adpcm_ima_qt -f caf apps/$a/ios/Runner/iservice_som.caf
done
```

Se o som mudar, troque também o id do canal Android (ex.: `iservice_avisos_v2`) na `MainActivity`,
no `AndroidManifest.xml` e na função `enviar-push`: no Android o som de um canal não muda depois de criado.
