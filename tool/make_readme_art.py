"""Le immagini del README: banner, galleria e finestra desktop.

Parte dalle foto che l'app fa di se stessa in debug (lib/dev/readme_shots.dart:
`flutter run -d macos --dart-define=README_SHOTS=1
--dart-define=README_SHOTS_SET=phone|wide`, finestra larga 430 o 1440 punti; le
foto finiscono in ~/Library/Containers/com.personal.demusLike/Data/tmp/
readme_shots) e le compone sul fondo di Macchia: nero, con i bagliori e i
puntini del marchio nel colore d'accento, che come nell'app viene dal brano
(qui: da quello che suonava nelle foto).

Uso:  python3 tool/make_readme_art.py <cartella-catture>

La cartella deve contenere: player, lyrics, queue, home, search, stats,
settings, eq, wide (.png). L'uscita va in docs/readme/.
"""

import math
import random
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "readme"
FONTS = ROOT / "assets" / "fonts"
ICON = ROOT / "assets" / "icon" / "crocuta.png"

# I colori del tema (lib/design/tokens.dart): Macchia e' nero, e l'unico
# colore e' l'accento del brano.
NIGHT_TOP = (16, 13, 12)
NIGHT_BOTTOM = (4, 4, 5)
CREAM = (244, 240, 236)
TEXT2 = (170, 166, 162)
# Rimpiazzato in main() con quello della foto del player.
ACCENT = (214, 122, 84)


def accent_of(player_png):
    """L'accento come lo disegna l'app: il colore pieno piu' frequente fra
    quelli vivi nel fondo della foto del player (tasto play, barre)."""
    im = Image.open(player_png).convert("RGB")
    im = im.crop((0, int(im.height * 0.75), im.width, im.height)).resize((120, 60))
    buckets = {}
    for r, g, b in im.get_flattened_data():
        hi, lo = max(r, g, b), min(r, g, b)
        if hi < 120 or (hi - lo) / hi < 0.35:
            continue
        key = (r // 16, g // 16, b // 16)
        n, sr, sg, sb = buckets.get(key, (0, 0, 0, 0))
        buckets[key] = (n + 1, sr + r, sg + g, sb + b)
    if not buckets:
        return ACCENT
    n, sr, sg, sb = max(buckets.values())
    return (sr // n, sg // n, sb // n)


def font(name, size, weight):
    f = ImageFont.truetype(str(FONTS / name), size)
    try:
        f.set_variation_by_axes([weight])
    except OSError:
        pass
    return f


def backdrop(w, h, seed=7):
    """Il fondo: gradiente notte, due bagliori e i puntini dell'icona."""
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        t = y / (h - 1)
        c = tuple(round(a + (b - a) * t) for a, b in zip(NIGHT_TOP, NIGHT_BOTTOM))
        for x in range(w):
            px[x, y] = c
    img = img.convert("RGBA")

    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    g = ImageDraw.Draw(glow)
    r = int(max(w, h) * 0.38)
    g.ellipse((w * 0.62 - r, h * 0.35 - r, w * 0.62 + r, h * 0.35 + r), fill=ACCENT + (46,))
    r2 = int(r * 0.6)
    g.ellipse((w * 0.08 - r2, h * 0.95 - r2, w * 0.08 + r2, h * 0.95 + r2), fill=ACCENT + (22,))
    glow = glow.filter(ImageFilter.GaussianBlur(r * 0.45))
    img = Image.alpha_composite(img, glow)

    # I puntini: una C sgranata che si disperde, come nell'icona, appena
    # accennata nell'angolo in alto a sinistra.
    dots = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(dots)
    rnd = random.Random(seed)
    cx, cy = -w * 0.02, h * 0.18
    for ring in range(9):
        radius = h * 0.10 + ring * h * 0.045
        n = 10 + ring * 4
        for i in range(n):
            a = -math.pi / 2 + math.pi * i / (n - 1)
            x = cx + math.cos(a) * radius
            y = cy + math.sin(a) * radius
            size = max(1.5, h * 0.011 * (1 - ring / 10) * (0.8 + rnd.random() * 0.4))
            alpha = int(38 * (1 - ring / 9))
            d.ellipse((x - size, y - size, x + size, y + size), fill=ACCENT + (alpha,))
    return Image.alpha_composite(img, dots)


def rounded(im, radius):
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, im.width - 1, im.height - 1), radius, fill=255)
    out = im.convert("RGBA")
    # Si tiene anche la trasparenza che c'era gia' (gli angoli della
    # finestra): vince il piu' trasparente dei due.
    out.putalpha(ImageChops.darker(out.getchannel("A"), mask))
    return out


def phone(path, width, crop_top=64):
    """Una cattura della finestra stretta, senza la fascia dei semafori,
    con gli angoli arrotondati come uno schermo."""
    im = Image.open(path).convert("RGBA")
    im = im.crop((0, crop_top, im.width, im.height))
    h = round(im.height * width / im.width)
    im = im.resize((width, h), Image.LANCZOS)
    im = rounded(im, int(width * 0.085))
    # Un filo chiaro sul bordo, come il vetro dell'app.
    ring = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ImageDraw.Draw(ring).rounded_rectangle(
        (0, 0, im.width - 1, im.height - 1), int(width * 0.085), outline=(255, 255, 255, 38), width=2
    )
    return Image.alpha_composite(im, ring)


def shadow_paste(canvas, im, xy, blur=40, offset=24, strength=150):
    sh = Image.new("RGBA", (im.width + blur * 4, im.height + blur * 4), (0, 0, 0, 0))
    mask = im.getchannel("A").point(lambda v: strength if v else 0)
    sh.paste((0, 0, 0, 255), (blur * 2, blur * 2), mask)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(sh, (xy[0] - blur * 2, xy[1] - blur * 2 + offset))
    canvas.alpha_composite(im, xy)


def hero(shots):
    W, H = 2400, 1200
    c = backdrop(W, H)

    # A destra i tre schermi: il player davanti, testi e coda dietro.
    back_w, front_w, overlap = 470, 590, 130
    lyr = phone(shots / "lyrics.png", back_w)
    que = phone(shots / "queue.png", back_w)
    ply = phone(shots / "player.png", front_w)
    mid = 1745
    shadow_paste(c, lyr, (mid - front_w // 2 - back_w + overlap, 250))
    shadow_paste(c, que, (mid + front_w // 2 - overlap, 250))
    shadow_paste(c, ply, (mid - front_w // 2, 130), blur=60, offset=36, strength=190)

    # A sinistra icona, nome e promessa.
    icon = Image.open(ICON).convert("RGBA").resize((220, 220), Image.LANCZOS)
    icon = rounded(icon, 50)
    shadow_paste(c, icon, (140, 250), blur=30, offset=18)

    d = ImageDraw.Draw(c)
    d.text((130, 500), "Crocuta", font=font("Outfit-Variable.ttf", 170, 700), fill=CREAM)
    head = font("Outfit-Variable.ttf", 60, 600)
    d.text((140, 710), "All the music you want.", font=head, fill=CREAM)
    d.text((140, 782), "Mixed like a DJ.", font=head, fill=ACCENT)
    d.text((142, 872), "No subscription. No ads.", font=font("Inter-Variable.ttf", 36, 500), fill=TEXT2)

    # Le piattaforme, in pillole di vetro: su un livello a parte, perche'
    # disegnare direttamente sostituirebbe l'alfa invece di fonderlo.
    pills = Image.new("RGBA", c.size, (0, 0, 0, 0))
    pd = ImageDraw.Draw(pills)
    x = 140
    f = font("Inter-Variable.ttf", 32, 600)
    for label in ["macOS", "Windows", "iPhone", "Android"]:
        tw = pd.textlength(label, font=f)
        pd.rounded_rectangle((x, 970, x + tw + 56, 1032), 31, fill=(255, 255, 255, 24), outline=(255, 255, 255, 60), width=2)
        pd.text((x + 28, 982), label, font=f, fill=(244, 244, 247, 255))
        x += tw + 56 + 16
    c.alpha_composite(pills)
    return c


def gallery(shots, names, captions):
    pw, gap, pad = 500, 70, 110
    phones = [phone(shots / f"{n}.png", pw) for n in names]
    ph = max(p.height for p in phones)
    W = pad * 2 + pw * len(phones) + gap * (len(phones) - 1)
    H = pad + ph + 170
    c = backdrop(W, H, seed=3)
    d = ImageDraw.Draw(c)
    f = font("Outfit-Variable.ttf", 46, 650)
    for i, (p, cap) in enumerate(zip(phones, captions)):
        x = pad + i * (pw + gap)
        shadow_paste(c, p, (x, pad - 20))
        tw = d.textlength(cap, font=f)
        d.text((x + (pw - tw) / 2, pad + ph + 40), cap, font=f, fill=CREAM)
    return c


def desktop(shots):
    win = Image.open(shots / "wide.png").convert("RGBA")
    win = win.resize((2000, round(win.height * 2000 / win.width)), Image.LANCZOS)
    # Le foto fatte dall'app (lib/dev/readme_shots.dart) sono rettangoli
    # pieni: gli angoli della finestra si arrotondano qui.
    win = rounded(win, 22)
    ring = Image.new("RGBA", win.size, (0, 0, 0, 0))
    ImageDraw.Draw(ring).rounded_rectangle(
        (0, 0, win.width - 1, win.height - 1), 22, outline=(255, 255, 255, 40), width=2
    )
    win = Image.alpha_composite(win, ring)
    pad = 120
    c = backdrop(win.width + pad * 2, win.height + pad * 2, seed=11)
    shadow_paste(c, win, (pad, pad - 20), blur=60, offset=36, strength=200)
    return c


def save(im, name, width):
    im = im.convert("RGB")
    if im.width > width:
        im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    path = OUT / name
    # JPEG di qualita': sono foto con gradienti, e un PNG pesava dieci
    # volte tanto senza differenze visibili.
    im.save(path, "JPEG", quality=88, optimize=True, progressive=True)
    print(f"{path.relative_to(ROOT)}  {im.width}x{im.height}  {path.stat().st_size // 1024} KB")


def main():
    global ACCENT
    shots = Path(sys.argv[1])
    ACCENT = accent_of(shots / "player.png")
    OUT.mkdir(parents=True, exist_ok=True)
    save(hero(shots), "hero.jpg", 2000)
    save(
        gallery(shots, ["home", "search", "stats", "settings"], ["Home", "Search", "Stats", "Settings"]),
        "gallery.jpg",
        2000,
    )
    save(gallery(shots, ["lyrics", "eq", "queue"], ["Lyrics", "Equalizer", "Queue"]), "sound.jpg", 1600)
    save(desktop(shots), "desktop.jpg", 2000)


if __name__ == "__main__":
    main()
