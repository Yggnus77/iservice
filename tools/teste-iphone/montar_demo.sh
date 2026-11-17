#!/usr/bin/env bash
# Monta e compila a versão de demonstração dos dois apps (dados de exemplo, sem banco),
# usada só para testar as telas de quem já está logado (mapa, pedido, chat, agenda).
# Uso (na raiz do repositório): bash tools/teste-iphone/montar_demo.sh
set -euo pipefail
D=tools/teste-iphone/demo
python3 $D/catalogo.py
cp $D/demo.dart packages/iservice_core/lib/demo.dart
cp $D/main_demo.dart apps/cliente/lib/main_demo.dart
cp $D/main_demo_profissional.dart apps/profissional/lib/main_demo.dart
for a in cliente profissional; do
  (cd apps/$a && flutter build web -t lib/main_demo.dart --release -o build/demo)
done
