"""Gera a marca iService em vetor limpo (redesenho do emblema enviado).

Saídas em OUT/svg. Tudo em curvas: nenhum texto depende de fonte instalada.
"""
import math
import os
import sys

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from shapely import affinity
from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import unary_union

AQUI = os.path.dirname(os.path.abspath(__file__))
FONTES = os.path.join(AQUI, "fontes")
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(AQUI, "out")
os.makedirs(os.path.join(OUT, "svg"), exist_ok=True)

# Cores da marca (guia de identidade) com tons de apoio para os degradês.
AZUL, AZUL_CLARO = "#0052CC", "#2E8BFF"
LARANJA, LARANJA_CLARO = "#FF7A00", "#FFB23F"
VERDE, VERDE_CLARO = "#00A443", "#2FCB62"
MARINHO, MARINHO_FUNDO, MARINHO_BORDA = "#0A1F44", "#0D3A8C", "#04102A"


# ---------------------------------------------------------------- geometria
def bez(p0, p1, p2, p3, n=48):
    pts = []
    for i in range(n + 1):
        t = i / n
        a = (1 - t) ** 3
        b = 3 * (1 - t) ** 2 * t
        c = 3 * (1 - t) * t ** 2
        d = t ** 3
        pts.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
    return pts


def caminho(curvas):
    pts = []
    for c in curvas:
        seg = bez(*c)
        pts.extend(seg if not pts else seg[1:])
    return Polygon(pts)


def d_de(geom, nd=2):
    """Polígono(s) shapely -> atributo d (use fill-rule evenodd)."""
    geoms = getattr(geom, "geoms", [geom])
    partes = []
    for g in geoms:
        if g.is_empty:
            continue
        for anel in [g.exterior, *g.interiors]:
            cs = list(anel.coords)[:-1]
            f = lambda v: (f"{v:.{nd}f}").rstrip("0").rstrip(".")
            partes.append("M" + " ".join(f"{f(x)} {f(y)}" for x, y in cs) + "Z")
    return "".join(partes)


def arredondar(g, r):
    return g.buffer(-r, join_style="round", quad_segs=12).buffer(r, join_style="round", quad_segs=12)


# ---------------------------------------------------------------- símbolo (pin)
# Caixa 0..100 de largura, ponta em y=PIN_H.
PIN_H = 113
PIN = caminho([
    ((50, PIN_H), (40, 99), (2, 74), (1, 45)),
    ((1, 45), (0, 17), (23, 0), (50, 0)),
    ((50, 0), (77, 0), (100, 17), (99, 45)),
    ((99, 45), (98, 74), (60, 99), (50, PIN_H)),
])
J = (50, 47)          # encontro das três partes
GAP = 4.6             # vão entre as partes
RAIO = 5.0            # cantos arredondados


def _fatia(pts):
    return Polygon(pts).intersection(PIN)


_azul = _fatia([J, (50, -20), (-20, -20), (-20, 68)])
_laranja = _fatia([J, (120, 68), (120, -20), (50, -20)])
_verde = _fatia([J, (-20, 68), (-20, 130), (120, 130), (120, 68)])


def _parte(g):
    return arredondar(g.buffer(-GAP / 2, join_style="mitre"), RAIO)


SEG_AZUL, SEG_LARANJA, SEG_VERDE = _parte(_azul), _parte(_laranja), _parte(_verde)


def chave():
    """Chave inglesa: cabo arredondado + cabeça com boca aberta, a 45°."""
    cabo = LineString([(0, 0), (0, 22)]).buffer(3.3, cap_style="round")
    cabeca = Point(0, -4).buffer(8.6, quad_segs=24)
    boca = box(-3.5, -16, 3.5, -4.5)
    boca = boca.union(Point(0, -4.5).buffer(3.5, quad_segs=16))
    g = unary_union([cabo, cabeca]).difference(boca)
    g = arredondar(g, 0.6)
    g = affinity.rotate(g, 45, origin=(0, 0))
    return affinity.translate(g, 27.5, 31)


def casa():
    tel = Polygon([(-15.5, 0.5), (0, -13.5), (15.5, 0.5)]).buffer(1.6, join_style="round")
    corpo = box(-10.5, -1, 10.5, 15)
    porta = box(-3.6, 5.5, 3.6, 15.5)
    g = unary_union([tel, corpo]).difference(porta)
    g = arredondar(g, 0.5)
    return affinity.translate(g, 72.5, 30)


def pessoa():
    cab = Point(0, -7).buffer(7.2, quad_segs=24)
    corpo = LineString([(-8.5, 9.5), (8.5, 9.5)]).buffer(5.6, cap_style="round")
    return affinity.translate(unary_union([cab, corpo]), 50, 74)


ICONES = unary_union([chave(), casa(), pessoa()])


def defs_pin(px):
    return f"""
    <linearGradient id="{px}gA" x1="0" y1="0" x2="0.35" y2="1"><stop offset="0" stop-color="{AZUL_CLARO}"/><stop offset="1" stop-color="{AZUL}"/></linearGradient>
    <linearGradient id="{px}gL" x1="0.7" y1="0" x2="0.4" y2="1"><stop offset="0" stop-color="{LARANJA_CLARO}"/><stop offset="1" stop-color="{LARANJA}"/></linearGradient>
    <linearGradient id="{px}gV" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{VERDE_CLARO}"/><stop offset="1" stop-color="{VERDE}"/></linearGradient>"""


def corpo_pin(px, icones="#FFFFFF", sombra_icones=False):
    s = ""
    if sombra_icones:
        s = f'<path fill="#00163D" fill-opacity=".22" fill-rule="evenodd" transform="translate(0.6 1.2)" d="{d_de(ICONES)}"/>'
    return (
        f'<path fill="url(#{px}gA)" d="{d_de(SEG_AZUL)}"/>'
        f'<path fill="url(#{px}gL)" d="{d_de(SEG_LARANJA)}"/>'
        f'<path fill="url(#{px}gV)" d="{d_de(SEG_VERDE)}"/>'
        f'{s}<path fill="{icones}" fill-rule="evenodd" d="{d_de(ICONES)}"/>'
    )


def corpo_pin_mono(cor="#FFFFFF"):
    """Silhueta de uma cor: partes cheias com os ícones vazados."""
    g = unary_union([SEG_AZUL, SEG_LARANJA, SEG_VERDE]).difference(ICONES.buffer(0.01))
    return f'<path fill="{cor}" fill-rule="evenodd" d="{d_de(g)}"/>'


# ---------------------------------------------------------------- texto em curvas
_fontes = {}


def fonte(nome):
    if nome not in _fontes:
        _fontes[nome] = TTFont(os.path.join(FONTES, nome))
    return _fontes[nome]


def texto(nome, s, tam, x, y, track=0, ancora="start"):
    """Retorna (lista de (char, d), largura). Coordenadas finais (y = linha de base)."""
    f = fonte(nome)
    gs = f.getGlyphSet()
    cmap = f.getBestCmap()
    upm = f["head"].unitsPerEm
    k = tam / upm
    larg = 0
    nomes = [cmap[ord(c)] for c in s]
    for n in nomes:
        larg += gs[n].width * k + track
    larg -= track
    x0 = x - (larg if ancora == "end" else larg / 2 if ancora == "middle" else 0)
    saida = []
    cx = x0
    for c, n in zip(s, nomes):
        pen = SVGPathPen(gs)
        tp = TransformPen(pen, (k, 0, 0, -k, cx, y))
        gs[n].draw(tp)
        d = pen.getCommands()
        if d:
            saida.append((c, d))
        cx += gs[n].width * k + track
    return saida, larg, x0


def num(v):
    return (f"{v:.2f}").rstrip("0").rstrip(".")
