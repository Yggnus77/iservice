#!/usr/bin/env bash
# Abre os apps no Safari de verdade, dentro do simulador de iPhone do Xcode (só em Mac).
# Uso: bash tools/teste-iphone/simulador.sh <pasta-de-saida>
set -uo pipefail
OUT=${1:-capturas-simulador}; mkdir -p "$OUT"
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
d=json.load(sys.stdin)["devices"]
cands=[(k,x) for k,v in d.items() if "iOS" in k for x in v if x["name"].startswith("iPhone") and "Pro" not in x["name"] and "Plus" not in x["name"]]
cands.sort(key=lambda c:(c[0],c[1]["name"]))
k,x=cands[-1]; print(x["udid"]); print(x["name"], k, file=sys.stderr)')
echo "Simulador: $UDID"
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl location "$UDID" set -15.8145,-47.9005 || true
xcrun simctl privacy "$UDID" grant location com.apple.mobilesafari || true
sleep 10
abrir() { # nome url segundos
  xcrun simctl terminate "$UDID" com.apple.mobilesafari >/dev/null 2>&1 || true
  xcrun simctl openurl "$UDID" "$2"; sleep "$3"
  xcrun simctl io "$UDID" screenshot "$OUT/sim-$1.png" && echo "captura $1"
}
abrir aquecimento "https://iservice.app.br/" 25
abrir cliente-boas-vindas "https://iservice.app.br/cliente/" 40
abrir profissional-boas-vindas "https://iservice.app.br/profissional/" 40
abrir demo-cliente-inicio "http://localhost:8101/?etapa=caminho#/inicio" 40
abrir demo-profissional-inicio "http://localhost:8102/?etapa=solicitado#/inicio" 40
xcrun simctl spawn "$UDID" log show --last 5m --predicate 'process == "MobileSafari" OR process == "com.apple.WebKit.WebContent"' --style compact 2>/dev/null | grep -iE "crash|jetsam|terminated|error" | tail -40 > "$OUT/log-safari.txt" || true
xcrun simctl list devices booted > "$OUT/aparelho.txt"
