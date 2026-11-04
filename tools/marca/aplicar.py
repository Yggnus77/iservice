"""Renderiza os SVGs da marca e grava os PNGs no repositório.

uso: python3 aplicar.py <pasta-svg> <repo>
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

SVG, REPO = sys.argv[1], sys.argv[2]
RENDER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "render.js")
TMP = tempfile.mkdtemp()
NAVY = "#06122B"


def dims(nome):
    s = open(os.path.join(SVG, nome)).read(400)
    m = re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', s)
    return float(m.group(1)), float(m.group(2))


mestres = {}
fila = []


def mestre(nome, largura):
    w, h = dims(nome)
    alt = round(largura * h / w)
    saida = os.path.join(TMP, nome.replace(".svg", f"-{largura}.png"))
    fila.extend([os.path.join(SVG, nome), saida, str(largura), str(alt)])
    mestres[(nome, largura)] = saida
    return saida


def rodar_fila():
    subprocess.run(["node", RENDER, *fila], check=True)


def im(*args):
    subprocess.run(["convert", *args], check=True)


def reduzir(src, dst, w, h=None, sem_alfa=False, fundo=NAVY):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    geo = f"{w}x{h or w}"
    a = [src, "-filter", "Lanczos", "-resize", geo]
    if sem_alfa:
        a += ["-background", fundo, "-alpha", "remove", "-alpha", "off"]
    a += ["-strip", "-define", "png:exclude-chunks=date,time", dst]
    im(*a)


def cantos(src, dst, w, raio=0.2):
    """Ícone legado do Android: quadrado com cantos arredondados."""
    r = round(w * raio)
    tmp = dst + ".mask.png"
    im("-size", f"{w}x{w}", "xc:none", "-fill", "white", "-draw", f"roundrectangle 0,0 {w - 1},{w - 1} {r},{r}", tmp)
    im(src, "-filter", "Lanczos", "-resize", f"{w}x{w}", tmp, "-compose", "DstIn", "-composite", "-strip", dst)
    os.remove(tmp)


def compor(fundo, frente, dst):
    im(fundo, frente, "-compose", "over", "-composite", dst)


# ---------------------------------------------------------------- mestres
for n in ["icone-cliente-1024.svg", "icone-profissional-1024.svg",
          "android-fundo-cliente.svg", "android-fundo-profissional.svg",
          "android-frente-cliente.svg", "android-frente-profissional.svg", "android-monocromatico.svg"]:
    mestre(n, 1024)
for n in ["emblema.svg", "emblema-sem-slogan.svg"]:
    mestre(n, 2048)
for n in ["simbolo.svg", "simbolo-branco.svg", "simbolo-marinho.svg"]:
    mestre(n, 1024)
for n in ["logo-horizontal-fundo-escuro.svg", "logo-horizontal-fundo-claro.svg"]:
    mestre(n, 2000)
mestre("faixa-google-play-1024x500.svg", 1024)
rodar_fila()
M = lambda n, w=1024: mestres[(n, w)]

# ---------------------------------------------------------------- pasta marca/
MARCA = os.path.join(REPO, "marca")
for sub in ["svg", "png", "lojas"]:
    shutil.rmtree(os.path.join(MARCA, sub), ignore_errors=True)
os.makedirs(os.path.join(MARCA, "svg"))
for f in sorted(os.listdir(SVG)):
    if f.startswith("og-"):
        continue
    shutil.copy(os.path.join(SVG, f), os.path.join(MARCA, "svg", f))
P = lambda *a: os.path.join(MARCA, "png", *a)
reduzir(M("emblema.svg", 2048), P("emblema-1024.png"), 1024)
reduzir(M("emblema-sem-slogan.svg", 2048), P("emblema-sem-slogan-1024.png"), 1024)
reduzir(M("simbolo.svg"), P("simbolo-1024.png"), 1024)
reduzir(M("simbolo-branco.svg"), P("simbolo-branco-1024.png"), 1024)
reduzir(M("simbolo-marinho.svg"), P("simbolo-marinho-1024.png"), 1024)
reduzir(M("logo-horizontal-fundo-escuro.svg", 2000), P("logo-horizontal-fundo-escuro.png"), 2000)
reduzir(M("logo-horizontal-fundo-claro.svg", 2000), P("logo-horizontal-fundo-claro.png"), 2000)
L = lambda *a: os.path.join(MARCA, "lojas", *a)
for app in ["cliente", "profissional"]:
    reduzir(M(f"icone-{app}-1024.svg"), L(f"app-store-{app}-1024.png"), 1024, sem_alfa=True)
    reduzir(M(f"icone-{app}-1024.svg"), L(f"google-play-{app}-512.png"), 512)
reduzir(M("faixa-google-play-1024x500.svg"), L("faixa-google-play-1024x500.png"), 1024, 500, sem_alfa=True)

# ---------------------------------------------------------------- apps Flutter
DENS = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
ADAPTATIVO = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
"""
ABERTURA = """<?xml version="1.0" encoding="utf-8"?>
<!-- Abertura: fundo marinho da marca com o emblema iService no centro. -->
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@color/iservice_abertura" />
    <item>
        <bitmap
            android:gravity="center"
            android:src="@drawable/abertura_emblema" />
    </item>
</layer-list>
"""
CORES = f"""<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="iservice_abertura">{NAVY}</color>
</resources>
"""


def estilo_v31(parent):
    return f"""<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Android 12+: a abertura do sistema usa o ícone adaptativo sobre o marinho da marca. -->
    <style name="LaunchTheme" parent="{parent}">
        <item name="android:windowBackground">@drawable/launch_background</item>
        <item name="android:windowSplashScreenBackground">@color/iservice_abertura</item>
    </style>
    <style name="NormalTheme" parent="{parent}">
        <item name="android:windowBackground">?android:colorBackground</item>
    </style>
</resources>
"""


for app in ["cliente", "profissional"]:
    base = os.path.join(REPO, "apps", app)
    res = os.path.join(base, "android/app/src/main/res")
    icone = M(f"icone-{app}-1024.svg")
    for d, k in DENS.items():
        pasta = os.path.join(res, f"mipmap-{d}")
        os.makedirs(pasta, exist_ok=True)
        cantos(icone, os.path.join(pasta, "ic_launcher.png"), round(48 * k))
        reduzir(M(f"android-fundo-{app}.svg"), os.path.join(pasta, "ic_launcher_background.png"), round(108 * k))
        reduzir(M(f"android-frente-{app}.svg"), os.path.join(pasta, "ic_launcher_foreground.png"), round(108 * k))
        reduzir(M("android-monocromatico.svg"), os.path.join(pasta, "ic_launcher_monochrome.png"), round(108 * k))
        dpasta = os.path.join(res, f"drawable-{d}")
        os.makedirs(dpasta, exist_ok=True)
        reduzir(M("emblema.svg", 2048), os.path.join(dpasta, "abertura_emblema.png"), round(220 * k))
    os.makedirs(os.path.join(res, "mipmap-anydpi-v26"), exist_ok=True)
    open(os.path.join(res, "mipmap-anydpi-v26/ic_launcher.xml"), "w").write(ADAPTATIVO)
    for p in ["drawable", "drawable-v21"]:
        open(os.path.join(res, p, "launch_background.xml"), "w").write(ABERTURA)
    open(os.path.join(res, "values/cores_marca.xml"), "w").write(CORES)
    os.makedirs(os.path.join(res, "values-v31"), exist_ok=True)
    os.makedirs(os.path.join(res, "values-night-v31"), exist_ok=True)
    open(os.path.join(res, "values-v31/styles.xml"), "w").write(estilo_v31("@android:style/Theme.Light.NoTitleBar"))
    open(os.path.join(res, "values-night-v31/styles.xml"), "w").write(estilo_v31("@android:style/Theme.Black.NoTitleBar"))

    # iOS
    ai = os.path.join(base, "ios/Runner/Assets.xcassets/AppIcon.appiconset")
    for f in os.listdir(ai):
        m = re.match(r"Icon-App-([\d.]+)x[\d.]+@(\d)x\.png", f)
        if m:
            px = round(float(m.group(1)) * int(m.group(2)))
            reduzir(icone, os.path.join(ai, f), px, sem_alfa=True)
    li = os.path.join(base, "ios/Runner/Assets.xcassets/LaunchImage.imageset")
    for f, k in [("LaunchImage.png", 1), ("LaunchImage@2x.png", 2), ("LaunchImage@3x.png", 3)]:
        reduzir(M("emblema.svg", 2048), os.path.join(li, f), 220 * k)
    sb = os.path.join(base, "ios/Runner/Base.lproj/LaunchScreen.storyboard")
    s = open(sb).read()
    s = s.replace('<color key="backgroundColor" red="1" green="1" blue="1" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>',
                  '<color key="backgroundColor" red="0.0235" green="0.0706" blue="0.1686" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>')
    s = re.sub(r'<image name="LaunchImage" width="\d+" height="\d+"/>', '<image name="LaunchImage" width="220" height="220"/>', s)
    open(sb, "w").write(s)

    # Web (PWA)
    web = os.path.join(base, "web")
    reduzir(icone, os.path.join(web, "favicon.png"), 32)
    im(icone, "-define", "icon:auto-resize=48,32,16", os.path.join(web, "favicon.ico"))
    reduzir(icone, os.path.join(web, "icons/Icon-192.png"), 192)
    reduzir(icone, os.path.join(web, "icons/Icon-512.png"), 512)
    reduzir(icone, os.path.join(web, "icons/apple-touch-icon.png"), 180, sem_alfa=True)
    mask = os.path.join(TMP, f"mask-{app}.png")
    compor(M(f"android-fundo-{app}.svg"), M(f"android-frente-{app}.svg"), mask)
    reduzir(mask, os.path.join(web, "icons/Icon-maskable-192.png"), 192)
    reduzir(mask, os.path.join(web, "icons/Icon-maskable-512.png"), 512)

# pacote compartilhado (logo dentro dos apps)
core = os.path.join(REPO, "packages/iservice_core/assets/marca")
for f in os.listdir(core):
    os.remove(os.path.join(core, f))
reduzir(M("simbolo.svg"), os.path.join(core, "simbolo.png"), 256)
reduzir(M("simbolo.svg"), os.path.join(core, "2.0x/simbolo.png"), 512)
reduzir(M("simbolo.svg"), os.path.join(core, "3.0x/simbolo.png"), 768)
reduzir(M("emblema.svg", 2048), os.path.join(core, "emblema.png"), 360)
reduzir(M("emblema.svg", 2048), os.path.join(core, "2.0x/emblema.png"), 720)
reduzir(M("emblema.svg", 2048), os.path.join(core, "3.0x/emblema.png"), 1080)

# ---------------------------------------------------------------- site e painel
site = os.path.join(REPO, "site")
for dst in [os.path.join(site, "assets/img/simbolo.svg"), os.path.join(site, "favicon.svg"),
            os.path.join(REPO, "admin/public/simbolo.svg"), os.path.join(REPO, "admin/public/favicon.svg")]:
    shutil.copy(os.path.join(SVG, "simbolo.svg"), dst)
shutil.copy(os.path.join(SVG, "emblema.svg"), os.path.join(site, "assets/img/emblema.svg"))
icone = M("icone-cliente-1024.svg")
im(icone, "-define", "icon:auto-resize=48,32,16", os.path.join(site, "favicon.ico"))
reduzir(icone, os.path.join(site, "apple-touch-icon.png"), 180, sem_alfa=True)
reduzir(icone, os.path.join(site, "assets/img/icon-192.png"), 192)
reduzir(icone, os.path.join(site, "assets/img/icon-512.png"), 512)
print("ok")
