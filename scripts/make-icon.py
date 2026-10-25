#!/usr/bin/env python3
"""Dibuja el icono de Orbit (1024 px) y genera el AppIcon.iconset.

Uso: python3 scripts/make-icon.py Resources/AppIcon.iconset
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 1024


def squircle_mask(size, inset):
    """Máscara con la forma redondeada de los iconos de macOS."""
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    n = 5.0
    a = (size - 2 * inset) / 2
    cx = cy = size / 2
    pts = []
    for i in range(720):
        t = 2 * math.pi * i / 720
        ct, st = math.cos(t), math.sin(t)
        x = cx + a * math.copysign(abs(ct) ** (2 / n), ct)
        y = cy + a * math.copysign(abs(st) ** (2 / n), st)
        pts.append((x, y))
    d.polygon(pts, fill=255)
    return mask


def gradient(size, top, bottom):
    img = Image.new("RGB", (size, size))
    d = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        d.line([(0, y), (size, y)], fill=c)
    return img


def radial(size, center, radius, color, alpha):
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = center
    steps = 60
    for i in range(steps, 0, -1):
        r = radius * i / steps
        a = int(alpha * (1 - i / steps) ** 1.6)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color + (a,))
    return layer


def draw_icon():
    inset = 100
    base = gradient(S, (24, 20, 58), (6, 6, 14)).convert("RGBA")
    base.alpha_composite(radial(S, (S * 0.78, S * 0.88), S * 0.62, (236, 96, 120), 120))
    base.alpha_composite(radial(S, (S * 0.2, S * 0.25), S * 0.55, (90, 120, 255), 110))

    # Brillo superior sutil
    gloss = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(gloss).ellipse([-200, -760, S + 200, 360], fill=(255, 255, 255, 26))
    base.alpha_composite(gloss.filter(ImageFilter.GaussianBlur(60)))

    # Isla (notch) arriba al centro
    island = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(island)
    w, h = 470, 150
    x0 = (S - w) / 2
    y0 = 232
    d.rounded_rectangle([x0, y0, x0 + w, y0 + h], radius=h / 2, fill=(0, 0, 0, 255))
    shadow = island.filter(ImageFilter.GaussianBlur(28))
    shadow = Image.eval(shadow, lambda v: v)
    tinted = Image.new("RGBA", (S, S), (160, 110, 255, 0))
    tinted.putalpha(shadow.getchannel("A").point(lambda v: int(v * 0.7)))
    base.alpha_composite(tinted, (0, 26))
    base.alpha_composite(island)

    # Contenido de la isla: portada + onda
    d = ImageDraw.Draw(base)
    art = 92
    ax, ay = x0 + 30, y0 + (h - art) / 2
    art_img = gradient(art, (255, 70, 140), (120, 60, 230)).convert("RGBA")
    art_mask = Image.new("L", (art, art), 0)
    ImageDraw.Draw(art_mask).rounded_rectangle([0, 0, art - 1, art - 1], radius=24, fill=255)
    base.paste(art_img, (int(ax), int(ay)), art_mask)
    bars = [0.45, 0.95, 0.62, 0.82]
    bw, gap = 16, 12
    bx = x0 + w - 34 - (len(bars) * bw + (len(bars) - 1) * gap)
    for i, v in enumerate(bars):
        bh = 80 * v
        cx = bx + i * (bw + gap)
        cy = y0 + h / 2
        d.rounded_rectangle([cx, cy - bh / 2, cx + bw, cy + bh / 2], radius=bw / 2, fill=(255, 120, 170, 255))

    # Órbita con estela: el anillo se ilumina hacia el cometa
    cxr, cyr = S / 2, 600
    box = [150, 360, S - 150, 840]
    rx, ry = (box[2] - box[0]) / 2, (box[3] - box[1]) / 2
    rot = math.radians(-14)
    head = math.radians(28)

    def orbit_point(t):
        px = cxr + rx * math.cos(t)
        py = cyr + ry * math.sin(t)
        return (cxr + (px - cxr) * math.cos(rot) - (py - cyr) * math.sin(rot),
                cyr + (px - cxr) * math.sin(rot) + (py - cyr) * math.cos(rot))

    # Se dibuja a 3x y se reduce para que el borde quede suave.
    F = 3
    big = Image.new("RGBA", (S * F, S * F), (0, 0, 0, 0))
    rd = ImageDraw.Draw(big)
    steps = 900
    for i in range(steps):
        t0 = head - 2 * math.pi * i / steps
        t1 = head - 2 * math.pi * (i + 1.5) / steps
        k = 1 - i / steps
        alpha = int(70 + 185 * (k ** 3))
        width = int((10 + 10 * (k ** 4)) * F)
        p0 = orbit_point(t0)
        p1 = orbit_point(t1)
        rd.line([(p0[0] * F, p0[1] * F), (p1[0] * F, p1[1] * F)], fill=(255, 235, 255, alpha), width=width)
        r = width / 2
        rd.ellipse([p0[0] * F - r, p0[1] * F - r, p0[0] * F + r, p0[1] * F + r], fill=(255, 235, 255, alpha))
    ring = big.resize((S, S), Image.LANCZOS)
    glow = ring.filter(ImageFilter.GaussianBlur(10))
    cut = Image.new("L", (S, S), 255)
    ImageDraw.Draw(cut).rounded_rectangle([x0 - 12, y0 - 12, x0 + w + 12, y0 + h + 12], radius=h / 2 + 12, fill=0)
    for layer in (glow, ring):
        layer.putalpha(ImageChops.multiply(layer.getchannel("A"), cut))
        base.alpha_composite(layer)

    qx, qy = orbit_point(head)
    base.alpha_composite(radial(S, (qx, qy), 170, (255, 170, 240), 210))
    d = ImageDraw.Draw(base)
    d.ellipse([qx - 34, qy - 34, qx + 34, qy + 34], fill=(255, 255, 255, 255))

    mask = squircle_mask(S, inset)
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    out.paste(base, (0, 0), mask)

    # Sombra del icono
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sh.putalpha(mask.filter(ImageFilter.GaussianBlur(18)).point(lambda v: int(v * 0.35)))
    final = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    final.alpha_composite(sh, (0, 14))
    final.alpha_composite(out)
    return final


def main():
    out_dir = Path(sys.argv[1] if len(sys.argv) > 1 else "Resources/AppIcon.iconset")
    out_dir.mkdir(parents=True, exist_ok=True)
    icon = draw_icon()
    icon.save(out_dir.parent / "AppIcon-1024.png")
    for size in (16, 32, 128, 256, 512):
        icon.resize((size, size), Image.LANCZOS).save(out_dir / f"icon_{size}x{size}.png")
        icon.resize((size * 2, size * 2), Image.LANCZOS).save(out_dir / f"icon_{size}x{size}@2x.png")
    print("Icono generado en", out_dir)


if __name__ == "__main__":
    main()
