"""Gera todos os SVGs da marca a partir de marca.py."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from marca import *  # noqa

from shapely.geometry import Polygon
from shapely.ops import unary_union

SVG = os.path.join(OUT, "svg")
SLOGAN = "SOLUÇÕES • PESSOAS • RESULTADOS"


def salvar(nome, w, h, corpo, defs=""):
    s = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {num(w)} {num(h)}" width="{num(w)}" height="{num(h)}" '
         f'role="img" aria-label="iService"><title>iService</title><defs>{defs}</defs>{corpo}</svg>\n')
    with open(os.path.join(SVG, nome), "w") as f:
        f.write(s)


def pin(px, x, y, escala, **kw):
    return f'<g transform="translate({num(x)} {num(y)}) scale({num(escala)})">{corpo_pin(px, **kw)}</g>'


# ------------------------------------------------------------ anel e fundo
def defs_anel(px, cx, cy, r):
    return f"""
    <radialGradient id="{px}fundo" cx="{num(cx)}" cy="{num(cy - r * .22)}" r="{num(r * 1.15)}" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#14449A"/><stop offset=".55" stop-color="{MARINHO}"/><stop offset="1" stop-color="{MARINHO_BORDA}"/></radialGradient>
    <linearGradient id="{px}anel" x1="{num(cx - r)}" y1="{num(cy - r)}" x2="{num(cx + r)}" y2="{num(cy + r)}" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#3FA9FF"/><stop offset=".42" stop-color="#1673F5"/><stop offset=".62" stop-color="#FF8A00"/><stop offset="1" stop-color="#FFC24A"/></linearGradient>
    <filter id="{px}brilho" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="{num(r * .03)}"/></filter>"""


def arco(cx, cy, r, a0, a1):
    p = lambda a: (cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a)))
    x0, y0 = p(a0)
    x1, y1 = p(a1)
    grande = 1 if (a1 - a0) % 360 > 180 else 0
    return f"M{num(x0)} {num(y0)}A{num(r)} {num(r)} 0 {grande} 1 {num(x1)} {num(y1)}"


def anel(px, cx, cy, r, esp, disco=True, arcos=True):
    s = ""
    if disco:
        s += f'<circle cx="{num(cx)}" cy="{num(cy)}" r="{num(r)}" fill="url(#{px}fundo)"/>'
    s += f'<circle cx="{num(cx)}" cy="{num(cy)}" r="{num(r)}" fill="none" stroke="url(#{px}anel)" stroke-width="{num(esp * 1.9)}" opacity=".75" filter="url(#{px}brilho)"/>'
    s += f'<circle cx="{num(cx)}" cy="{num(cy)}" r="{num(r)}" fill="none" stroke="url(#{px}anel)" stroke-width="{num(esp)}"/>'
    s += f'<circle cx="{num(cx)}" cy="{num(cy)}" r="{num(r - esp * .22)}" fill="none" stroke="#FFFFFF" stroke-opacity=".45" stroke-width="{num(esp * .18)}"/>'
    if arcos:
        ri = r - esp * 1.9
        s += f'<path d="{arco(cx, cy, ri, 196, 262)}" fill="none" stroke="#FF8A00" stroke-width="{num(esp * .42)}" stroke-linecap="round" opacity=".9"/>'
        s += f'<path d="{arco(cx, cy, ri, 16, 82)}" fill="none" stroke="#3FA9FF" stroke-width="{num(esp * .42)}" stroke-linecap="round" opacity=".9"/>'
    return s


# ------------------------------------------------------------ palavra e seta
def defs_palavra(px):
    return f"""
    <linearGradient id="{px}branco" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#D6E1F2"/></linearGradient>
    <linearGradient id="{px}ce" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{LARANJA_CLARO}"/><stop offset="1" stop-color="{LARANJA}"/></linearGradient>
    <linearGradient id="{px}seta" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="{LARANJA}"/><stop offset="1" stop-color="#FFC24A"/></linearGradient>
    <filter id="{px}sombra" x="-10%" y="-10%" width="120%" height="140%"><feGaussianBlur stdDeviation="4"/></filter>"""


def seta(x0, y0, x1, y1, curva, w0, w1, cabeca):
    """Seta curva: corpo afinando na cauda + ponta triangular."""
    c1 = (x0 + (x1 - x0) * .3, y0 + curva)
    c2 = (x0 + (x1 - x0) * .72, y1 + curva * .95)
    pts = bez((x0, y0), c1, c2, (x1, y1), 80)
    cima, baixo = [], []
    for i, (x, y) in enumerate(pts):
        j = min(i + 1, len(pts) - 1)
        k = max(i - 1, 0)
        dx, dy = pts[j][0] - pts[k][0], pts[j][1] - pts[k][1]
        n = math.hypot(dx, dy)
        nx, ny = -dy / n, dx / n
        t = i / (len(pts) - 1)
        w = (w0 + (w1 - w0) * t ** .6) / 2
        cima.append((x + nx * w, y + ny * w))
        baixo.append((x - nx * w, y - ny * w))
    corpo = Polygon(cima + baixo[::-1]).buffer(0)
    dx, dy = pts[-1][0] - pts[-4][0], pts[-1][1] - pts[-4][1]
    n = math.hypot(dx, dy)
    ux, uy = dx / n, dy / n
    nx, ny = -uy, ux
    bx, by = x1 - ux * cabeca * .25, y1 - uy * cabeca * .25
    ponta = Polygon([
        (bx + ux * cabeca, by + uy * cabeca),
        (bx + nx * cabeca * .55, by + ny * cabeca * .55),
        (bx - ux * cabeca * .12, by - uy * cabeca * .12),
        (bx - nx * cabeca * .55, by - ny * cabeca * .55),
    ])
    return unary_union([corpo, ponta]).buffer(1.2, join_style="round").buffer(-1.2, join_style="round")


def palavra(px, cx, base, tam, cor_iservi=None, sombra=True):
    """'iServi' + 'ce' em Montserrat Black Italic, centralizado em cx."""
    glifos, larg, x0 = texto("black-italic.ttf", "iService", tam, cx, base, -tam * .015, "middle")
    branco = "".join(d for c, d in glifos[:6])
    ce = "".join(d for c, d in glifos[6:])
    cor = cor_iservi or f"url(#{px}branco)"
    s = ""
    if sombra:
        s += f'<g filter="url(#{px}sombra)" opacity=".55" transform="translate({num(tam * .02)} {num(tam * .045)})" fill="#020A1F"><path d="{branco}{ce}"/></g>'
    s += f'<path fill="{cor}" d="{branco}"/><path fill="url(#{px}ce)" d="{ce}"/>'
    return s, larg, x0


def bloco_seta(px, x0, larg, base, tam, sombra=True):
    g = seta(x0 + larg * .1, base + tam * .19, x0 + larg * .86, base + tam * .14, tam * .34, tam * .025, tam * .13, tam * .24)
    s = ""
    if sombra:
        s += f'<path filter="url(#{px}sombra)" opacity=".5" fill="#020A1F" transform="translate(3 5)" d="{d_de(g)}"/>'
    return s + f'<path fill="url(#{px}seta)" d="{d_de(g)}"/>'


def slogan(cx, base, tam, cor="#FFFFFF", track=None):
    glifos, larg, _ = texto("bold.ttf", SLOGAN, tam, cx, base, track if track is not None else tam * .22, "middle")
    pontos = "".join(d for c, d in glifos if c == "•")
    letras = "".join(d for c, d in glifos if c != "•")
    return f'<path fill="{cor}" d="{letras}"/><path fill="{LARANJA}" d="{pontos}"/>', larg


# ============================================================ 1. emblema completo
def emblema(nome="emblema.svg", tam=1024, com_slogan=True):
    px = "e"
    c = tam / 2
    defs = defs_anel(px, c, c, tam * .462) + defs_pin(px) + defs_palavra(px)
    corpo = anel(px, c, c, tam * .462, tam * .018)
    corpo += pin(px, c - 175, 104, 3.5, sombra_icones=True)
    p, larg, x0 = palavra(px, c, 688, 166)
    corpo += p + bloco_seta(px, x0, larg, 688, 166)
    if com_slogan:
        s, _ = slogan(c, 818, 23)
        corpo += s
    salvar(nome, tam, tam, corpo, defs)


# ============================================================ 2. símbolo (pin)
def simbolo():
    m = 1  # margem
    corpo = f'<g transform="translate({m} {m})">{corpo_pin("s")}</g>'
    salvar("simbolo.svg", 100 + 2 * m, PIN_H + .5 + 2 * m, corpo, defs_pin("s"))
    salvar("simbolo-branco.svg", 100 + 2 * m, PIN_H + .5 + 2 * m, f'<g transform="translate({m} {m})">{corpo_pin_mono()}</g>')
    salvar("simbolo-marinho.svg", 100 + 2 * m, PIN_H + .5 + 2 * m, f'<g transform="translate({m} {m})">{corpo_pin_mono(MARINHO)}</g>')


# ============================================================ 3. logo horizontal
def horizontal(nome, claro_no_escuro):
    px = "h"
    h = 240
    pin_esc = 2.0
    corpo = pin(px, 10, (h - PIN_H * pin_esc) / 2, pin_esc, sombra_icones=False)
    tam = 128
    cor = None if claro_no_escuro else AZUL
    glifos, larg, x0 = texto("black-italic.ttf", "iService", tam, 0, 0, -tam * .015)
    x = 10 + 100 * pin_esc + 30
    base = 150
    p, larg, x0 = palavra(px, x + larg / 2, base, tam, cor_iservi=cor, sombra=False)
    corpo += p + bloco_seta(px, x0, larg, base, tam, sombra=False)
    w = x + larg + 20
    defs = defs_pin(px) + defs_palavra(px)
    if claro_no_escuro:
        corpo = corpo  # fundo transparente: para usar sobre fundo escuro
    salvar(nome, w, h, corpo, defs)


# ============================================================ 4. ícones de app
def icone(nome, pro=False, cantos=False):
    px = "i"
    t = 1024
    c = t / 2
    defs = defs_anel(px, c, c, 430) + defs_pin(px)
    corpo = f'<rect width="{t}" height="{t}" fill="url(#{px}fundo)"/>'
    # o fundo do disco já cobre tudo: usa o mesmo degradê em tela cheia
    corpo += anel(px, c, c, 418, 22, disco=False, arcos=False)
    esc = 5.0 if not pro else 4.6
    cy = c - (40 if pro else 4)
    corpo += pin(px, c - 50 * esc, cy - PIN_H / 2 * esc, esc, sombra_icones=True)
    if pro:
        corpo += selo_pro(c, 806)
    salvar(nome, t, t, corpo, defs)


def selo_pro(cx, cy):
    glifos, larg, _ = texto("xbold.ttf", "PRO", 92, cx, cy + 33, 6, "middle")
    w, h = larg + 88, 124
    return (f'<rect x="{num(cx - w / 2)}" y="{num(cy - h / 2)}" width="{num(w)}" height="{h}" rx="{h / 2}" fill="{LARANJA}" stroke="#FFFFFF" stroke-width="10"/>'
            f'<path fill="{MARINHO}" d="{"".join(d for _, d in glifos)}"/>')


# ---- Android adaptativo (camadas de 108dp desenhadas em 1024)
def adaptativo(pro=False):
    px = "a"
    t = 1024
    c = t / 2
    sufixo = "-profissional" if pro else "-cliente"
    salvar(f"android-fundo{sufixo}.svg", t, t, f'<rect width="{t}" height="{t}" fill="url(#{px}fundo)"/>', defs_anel(px, c, c, 330))
    # zona segura: círculo de 66dp em 108dp -> raio 313 em 1024
    corpo = anel(px, c, c, 292, 15, disco=False, arcos=False)
    esc = 3.35 if not pro else 3.05
    cy = c - (26 if pro else 3)
    corpo += pin(px, c - 50 * esc, cy - PIN_H / 2 * esc, esc, sombra_icones=True)
    if pro:
        g = selo_pro(0, 0)
        corpo += f'<g transform="translate({c} {c + 228}) scale(.62)">{g}</g>'
    salvar(f"android-frente{sufixo}.svg", t, t, corpo, defs_anel(px, c, c, 292) + defs_pin(px))
    esc = 3.4
    salvar("android-monocromatico.svg", t, t,
           f'<g transform="translate({num(c - 50 * esc)} {num(c - PIN_H / 2 * esc)}) scale({esc})">{corpo_pin_mono()}</g>')


# ---- Abertura (splash): emblema sobre marinho
def abertura():
    emblema("emblema-sem-slogan.svg", com_slogan=False)


# ---- Faixa da Google Play (1024x500)
def faixa_play():
    px = "f"
    w, h = 1024, 500
    defs = defs_anel(px, 300, 250, 560) + defs_pin(px) + defs_palavra(px)
    corpo = f'<rect width="{w}" height="{h}" fill="url(#{px}fundo)"/>'
    corpo += f'<circle cx="250" cy="250" r="205" fill="none" stroke="url(#{px}anel)" stroke-width="30" opacity=".7" filter="url(#{px}brilho)"/>'
    corpo += f'<circle cx="250" cy="250" r="205" fill="none" stroke="url(#{px}anel)" stroke-width="14"/>'
    corpo += pin(px, 250 - 117, 250 - 136, 2.35, sombra_icones=True)
    p, larg, x0 = palavra(px, 700, 250, 128)
    corpo += p + bloco_seta(px, x0, larg, 250, 128)
    s, _ = slogan(700, 365, 17)
    corpo += s
    salvar("faixa-google-play-1024x500.svg", w, h, corpo, defs)


# ---- Imagem de compartilhamento (og-image 1200x630)
def og():
    px = "o"
    w, h = 1200, 630
    defs = defs_anel(px, 340, 315, 700) + defs_pin(px) + defs_palavra(px)
    corpo = f'<rect width="{w}" height="{h}" fill="url(#{px}fundo)"/>'
    corpo += f'<circle cx="300" cy="315" r="235" fill="none" stroke="url(#{px}anel)" stroke-width="34" opacity=".7" filter="url(#{px}brilho)"/>'
    corpo += f'<circle cx="300" cy="315" r="235" fill="none" stroke="url(#{px}anel)" stroke-width="16"/>'
    corpo += pin(px, 300 - 135, 315 - 155, 2.7, sombra_icones=True)
    p, larg, x0 = palavra(px, 820, 300, 150)
    corpo += p + bloco_seta(px, x0, larg, 300, 150)
    s, _ = slogan(820, 430, 19)
    corpo += s
    g, _, _ = texto("bold.ttf", "Serviços perto de você, em Brasília e no Entorno", 26, 820, 500, 0, "middle")
    corpo += f'<path fill="#A6B3CC" d="{"".join(d for _, d in g)}"/>'
    salvar("og-image-1200x630.svg", w, h, corpo, defs)


if __name__ == "__main__":
    emblema()
    abertura()
    simbolo()
    horizontal("logo-horizontal-fundo-escuro.svg", True)
    horizontal("logo-horizontal-fundo-claro.svg", False)
    icone("icone-cliente-1024.svg")
    icone("icone-profissional-1024.svg", pro=True)
    adaptativo(False)
    adaptativo(True)
    faixa_play()
    og()
    for f in sorted(os.listdir(SVG)):
        print(f, os.path.getsize(os.path.join(SVG, f)))
