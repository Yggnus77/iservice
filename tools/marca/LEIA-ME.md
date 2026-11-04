# Gerador da marca

Redesenha o emblema iService em vetor limpo (pin em três partes, palavra em
Montserrat Black Italic convertida em curvas, seta e anel) e grava todos os
ícones e imagens nos apps, no site e no painel.

```bash
pip install fonttools shapely
mkdir -p tools/marca/fontes && cd tools/marca/fontes
curl -LO "https://raw.githubusercontent.com/google/fonts/main/ofl/montserrat/Montserrat%5Bwght%5D.ttf"
curl -LO "https://raw.githubusercontent.com/google/fonts/main/ofl/montserrat/Montserrat-Italic%5Bwght%5D.ttf"
python3 -m fontTools.varLib.instancer "Montserrat-Italic[wght].ttf" wght=900 -o black-italic.ttf
python3 -m fontTools.varLib.instancer "Montserrat[wght].ttf" wght=700 -o bold.ttf
python3 -m fontTools.varLib.instancer "Montserrat[wght].ttf" wght=800 -o xbold.ttf
cd ../../..
python3 tools/marca/gerar.py tools/marca/saida          # SVGs
python3 tools/marca/aplicar.py tools/marca/saida/svg .   # PNGs no repositório (precisa de node + playwright e ImageMagick)
```

Medidas e cores ficam em `marca.py`; posições de cada peça em `gerar.py`.
