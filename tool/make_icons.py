#!/usr/bin/env python3
"""Genera l'icona dell'app per iOS e macOS.

Il segno e' una C fatta di macchie, come una stampa a retino: Crocuta e'
il genere della iena macchiata, e le macchie bastano a dirlo senza
disegnare l'animale. Tre anelli di macchie lungo gli stessi raggi, grandi
sul dorso della C e sempre piu' piccole verso le punte.

E' disegnato qui, in codice, e non importato da un'immagine: cosi' e'
esatto a ogni misura e si ritocca cambiando un numero.

Le due piattaforme vogliono cose diverse dallo stesso disegno, ed e' una
differenza che si dimentica:

  - iOS vuole un quadrato pieno fino al bordo e applica la propria maschera.
  - macOS vuole lo squircle gia' ritagliato, dentro un margine trasparente.
  - Windows un .ico con piu' misure, con la stessa forma del Mac.

  - Android vuole due cose: le PNG di una volta (mipmap-*/ic_launcher) e
    l'icona adattiva, fondo e macchie su due strati separati: il launcher
    la ritaglia a cerchio, goccia o quadrato e la muove col dito. Le
    macchie stanno nei 72dp centrali dei 108 del livello, che e' la parte
    che nessuna maschera taglia; e c'e' lo strato monocromo, per le icone
    a tema di Android 13.

  - iOS 26 e macOS 26 vogliono un documento di Icon Composer (.icon): il
    disegno a strati, a cui il sistema aggiunge il Liquid Glass — riflessi,
    rifrazione, le varianti scura, colorata e trasparente. Le PNG restano
    per i sistemi precedenti.

    python3 tool/make_icons.py
"""

import json
import math
import os
import shutil

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SS = 4  # supersampling, ridotto alla fine per bordi puliti

# Fondo: il bruno-fulvo scuro del manto della iena, piu' chiaro in alto,
# come la luce che viene dall'alto sulle icone di sistema; in basso scende
# quasi al nero, come l'app. Le macchie color avorio e non bianche: il
# bianco puro su quel fondo vibra, l'avorio si posa.
TOP = (96, 50, 20)
BOTTOM = (28, 14, 8)
SPOT = (244, 232, 210)

# Raggi dei tre anelli, in frazioni del lato.
RINGS = (0.335, 0.255, 0.175)
# Quante macchie per anello, tutte sugli stessi raggi: e' l'allineamento
# a far leggere il retino invece di una nuvola di pallini.
RAYS = 13
# Mezza apertura della C, verso destra.
GAP = math.radians(58)
# La C pesa tutta a sinistra: il centro geometrico sembrerebbe scentrato,
# quindi si sposta il disegno a destra fino al centro ottico.
SHIFT = 0.055
# Raggio delle macchie: sul dorso e alle punte, in frazioni del lato. Le
# piu' piccole non scendono sotto una misura che a 29px si veda ancora.
SPOT_MAX = 0.038
SPOT_MIN = 0.013


def spots(n=1.0):
    """Le macchie della C, come (x, y, raggio), su un lato lungo [n]."""
    out = []
    cx, cy = n * (0.5 + SHIFT), n * 0.5
    for ring, r in enumerate(RINGS):
        radius = r * n
        # Gli anelli interni hanno macchie piu' piccole: il retino si
        # schiarisce verso l'interno della C.
        weight = 1 - ring / len(RINGS) * 0.55
        for k in range(RAYS):
            a = GAP + (2 * math.pi - 2 * GAP) * k / (RAYS - 1)
            # 1 sul dorso della C, 0 alle punte.
            back = math.cos((a - math.pi) / (math.pi - GAP) * math.pi / 2)
            s = (SPOT_MIN + (SPOT_MAX - SPOT_MIN) * back**1.1 * weight) * n
            out.append((cx + radius * math.cos(a), cy - radius * math.sin(a), s))
    return out


def _lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def build(size):
    """Il disegno come quadrato pieno, fino al bordo."""
    n = size * SS
    img = Image.new("RGB", (n, n))
    d = ImageDraw.Draw(img)
    for y in range(n):
        d.line([(0, y), (n, y)], fill=_lerp(TOP, BOTTOM, y / n))

    for x, y, s in spots(n):
        d.ellipse([x - s, y - s, x + s, y + s], fill=SPOT)

    return img.resize((size, size), Image.LANCZOS).convert("RGBA")


def rounded(img, radius_ratio=0.2237):
    """macOS vuole lo squircle gia' ritagliato; iOS lo fa da se'."""
    size = img.size[0]
    mask = Image.new("L", (size * SS, size * SS), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size * SS - 1, size * SS - 1],
        radius=size * SS * radius_ratio,
        fill=255,
    )
    out = img.copy()
    out.putalpha(mask.resize((size, size), Image.LANCZOS))
    return out


def macos_icon(size):
    """La griglia di macOS: la forma sta dentro l'~82% della tela."""
    content = round(size * 0.82)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    art = rounded(build(content))
    off = (size - content) // 2
    canvas.paste(art, (off, off), art)
    return canvas


# Il secondo strato delle macchie, sotto l'avorio: piu' grande, spostato in
# basso a destra e di un ambra caldo. Col vetro sopra, ogni macchia diventa
# una lente avorio posata su un'ombra colorata — la profondita' che il
# disegno piatto non aveva.
UNDER = (232, 146, 84)
UNDER_SCALE = 1.16
UNDER_OFFSET = 0.013  # in frazioni del lato, verso il basso a destra


def _svg(circles, color, scale=1.0, offset=0.0):
    n = 1024
    body = "".join(
        f'<circle cx="{(x + offset) * n:.2f}" cy="{(y + offset) * n:.2f}" '
        f'r="{r * scale * n:.2f}"/>'
        for x, y, r in circles
    )
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{n}" height="{n}" '
        f'viewBox="0 0 {n} {n}"><g fill="rgb{color}">{body}</g></svg>'
    )


def _color(rgb):
    return "srgb:" + ",".join(f"{c / 255:.5f}" for c in rgb) + ",1.00000"


def icon_document(path):
    """Il documento di Icon Composer: sfondo e due strati di macchie.

    Il vetro lo mette il sistema, strato per strato: qui si dice solo cosa
    sta sopra cosa. Le macchie in SVG, cosi' restano esatte a ogni misura.
    """
    if os.path.exists(path):
        shutil.rmtree(path)
    assets = os.path.join(path, "Assets")
    os.makedirs(assets)
    circles = spots()
    with open(os.path.join(assets, "under.svg"), "w") as f:
        f.write(_svg(circles, UNDER, UNDER_SCALE, UNDER_OFFSET))
    with open(os.path.join(assets, "spots.svg"), "w") as f:
        f.write(_svg(circles, SPOT))
    doc = {
        "fill": {"linear-gradient": [_color(TOP), _color(BOTTOM)]},
        "groups": [
            {
                "name": "Spots",
                "layers": [
                    {"name": "spots", "image-name": "spots.svg", "glass": True},
                ],
                "shadow": {"kind": "layer-color", "opacity": 0.5},
                "translucency": {"enabled": True, "value": 0.25},
                "specular": True,
            },
            {
                "name": "Under",
                "layers": [
                    {"name": "under", "image-name": "under.svg", "glass": True},
                ],
                "shadow": {"kind": "neutral", "opacity": 0.35},
                "translucency": {"enabled": True, "value": 0.45},
            },
        ],
        "supported-platforms": {"squares": "shared"},
    }
    with open(os.path.join(path, "icon.json"), "w") as f:
        json.dump(doc, f, indent=2)


ANDROID_DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def android_foreground(size, color):
    """Le macchie da sole, su fondo trasparente, nei 72/108 centrali."""
    n = size * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    inner = n * 72 / 108
    off = (n - inner) / 2
    for x, y, r in spots(inner):
        d.ellipse([off + x - r, off + y - r, off + x + r, off + y + r], fill=color)
    return img.resize((size, size), Image.LANCZOS)


def android_icons():
    res = os.path.join(ROOT, "android/app/src/main/res")
    for name, k in ANDROID_DENSITIES.items():
        folder = os.path.join(res, f"mipmap-{name}")
        os.makedirs(folder, exist_ok=True)
        # Le PNG di una volta, per i launcher senza icone adattive: la
        # stessa forma arrotondata del Mac.
        macos_icon(round(48 * k)).save(os.path.join(folder, "ic_launcher.png"))
        android_foreground(round(108 * k), SPOT + (255,)).save(
            os.path.join(folder, "ic_launcher_foreground.png")
        )
        android_foreground(round(108 * k), (255, 255, 255, 255)).save(
            os.path.join(folder, "ic_launcher_monochrome.png")
        )
        print("android", name)

    hexc = lambda c: "#FF%02X%02X%02X" % c
    drawable = os.path.join(res, "drawable")
    os.makedirs(drawable, exist_ok=True)
    with open(os.path.join(drawable, "ic_launcher_background.xml"), "w") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            "<!-- Il fondo dell'icona: lo stesso gradiente di tools/make_icons.py. -->\n"
            '<shape xmlns:android="http://schemas.android.com/apk/res/android">\n'
            f'    <gradient android:angle="270" android:startColor="{hexc(TOP)}"\n'
            f'        android:endColor="{hexc(BOTTOM)}" />\n'
            "</shape>\n"
        )
    anydpi = os.path.join(res, "mipmap-anydpi-v26")
    os.makedirs(anydpi, exist_ok=True)
    with open(os.path.join(anydpi, "ic_launcher.xml"), "w") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@drawable/ic_launcher_background" />\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
            '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />\n'
            "</adaptive-icon>\n"
        )
    print("android adaptive")


def main():
    master = build(1024)
    os.makedirs(os.path.join(ROOT, "assets/icon"), exist_ok=True)
    master.convert("RGB").save(os.path.join(ROOT, "assets/icon/crocuta.png"))

    ios_dir = os.path.join(ROOT, "ios/Runner/Assets.xcassets/AppIcon.appiconset")
    for name in sorted(os.listdir(ios_dir)):
        if not name.endswith(".png"):
            continue
        path = os.path.join(ios_dir, name)
        with Image.open(path) as existing:
            w = existing.size[0]
        # Opache e piene fino al bordo: la maschera la mette il sistema.
        master.resize((w, w), Image.LANCZOS).convert("RGB").save(path)
        print("ios ", name, w)

    mac_dir = os.path.join(ROOT, "macos/Runner/Assets.xcassets/AppIcon.appiconset")
    for name in sorted(os.listdir(mac_dir)):
        if not name.endswith(".png"):
            continue
        path = os.path.join(mac_dir, name)
        with Image.open(path) as existing:
            w = existing.size[0]
        # Disegnata a ogni misura, non ridotta dalla grande: a 16px le
        # macchie restano tonde invece di impastarsi.
        macos_icon(w).save(path)
        print("macos", name, w)

    # Windows: un .ico con dentro tutte le misure che Esplora risorse e la
    # barra delle applicazioni chiedono. Stessa forma arrotondata del Mac:
    # Windows non applica maschere, e un quadrato pieno spiccherebbe fra le
    # icone di sistema.
    ico = os.path.join(ROOT, "windows/runner/resources/app_icon.ico")
    big = macos_icon(256)
    big.save(ico, sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)])
    print("windows app_icon.ico")

    android_icons()

    # Il documento a strati, per iOS 26 e macOS 26: uno per progetto, con
    # lo stesso nome del set di PNG, cosi' Xcode li tratta come la stessa
    # icona — il vetro dove c'e', le PNG dove no.
    doc = os.path.join(ROOT, "assets/icon/Crocuta.icon")
    icon_document(doc)
    for target in ("ios/Runner/AppIcon.icon", "macos/Runner/AppIcon.icon"):
        dest = os.path.join(ROOT, target)
        if os.path.exists(dest):
            shutil.rmtree(dest)
        shutil.copytree(doc, dest)
        print("icon ", target)


if __name__ == "__main__":
    main()
