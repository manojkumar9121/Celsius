#!/usr/bin/env python3
"""Build all launcher/splash/notification icon assets from a master icon image.

Master: icon_concepts/Pasted image.png (user's design: red rounded square + white note)
"""
import os
from PIL import Image, ImageOps

HERE = os.path.dirname(os.path.abspath(__file__))
MASTER = os.path.join(os.path.dirname(HERE), 'icon_concepts', 'Pasted image.png')
RES = os.path.join(HERE, 'android', 'app', 'src', 'main', 'res')

master = Image.open(MASTER).convert('RGBA')
px = master.load()
W, H = master.size

# --- locate the opaque rounded square --------------------------------
def opaque(x, y):
    return px[x, y][3] > 128

xs = [x for x in range(W) for y in range(H) if opaque(x, y)]
x0, x1 = min(xs), max(xs)
ys = [y for x in range(W) for y in range(H) if opaque(x, y)]
y0, y1 = min(ys), max(ys)
SX, SY, SL = x0, y0, x1 - x0 + 1  # square top-left + size
print(f'square bbox: ({x0},{y0})-({x1},{y1}) size={SL}')

# --- note silhouette (color-keyed from green channel) ---------------
def note_mask():
    img = Image.new('L', (W, H), 0)
    mp = img.load()
    for y in range(H):
        for x in range(W):
            r, g, b, a = px[x, y]
            if a < 128 or g < 140:
                continue
            mp[x, y] = min(255, (g - 140) * 2)
    return img

def extract_note():
    mask = note_mask()
    bbox = mask.getbbox()
    print(f'note bbox: {bbox}')
    note = Image.new('RGBA', (W, H), (255, 255, 255, 0))
    note.putalpha(mask)
    # crop to bbox with tiny pad
    l, t, r, b = bbox
    pad = 2
    l = max(0, l - pad); t = max(0, t - pad); r = min(W, r + pad); b = min(H, b + pad)
    return note.crop((l, t, r, b))

note = extract_note()

# --- average top/bottom background colors (note excluded) -----------
def stripe_color(frac, y0, y1):
    rsum = gsum = bsum = n = 0
    ylo = y0 + int((y1 - y0) * frac[0]); yhi = y0 + int((y1 - y0) * frac[1])
    for y in range(ylo, yhi):
        for x in range(SX, SX + SL):
            r, g, b, a = px[x, y]
            if a < 128 or g > 140:
                continue
            rsum += r; gsum += g; bsum += b; n += 1
    return (rsum // n, gsum // n, bsum // n)

top = stripe_color((0.02, 0.22), y0, y1)
bot = stripe_color((0.82, 0.98), y0, y1)
mid = tuple((top[i] + bot[i]) // 2 for i in range(3))
print(f'gradient: top={top} mid={mid} bot={bot}')

def vertical_gradient(size, t, m, b):
    img = Image.new('RGB', (size, size))
    p = img.load()
    t1 = tuple(t[i] + ((m[i] - t[i]) // 4) for i in range(3))
    b1 = tuple(m[i] + ((b[i] - m[i]) // 4) for i in range(3))
    stops = [t, t1, m, b1, b]
    seg = len(stops) - 1
    for y in range(size):
        f = y * seg / (size - 1)
        i = min(int(f), seg - 1)
        f = f - i
        c = tuple(int(stops[i][k] + (stops[i + 1][k] - stops[i][k]) * f) for k in range(3))
        for x in range(size):
            p[x, y] = c
    return img

# --- compositors -----------------------------------------------------
def scale_to(image, size, solid_bg=None):
    img = image.resize((size, size), Image.LANCZOS)
    if solid_bg is None:
        return img
    out = Image.new('RGBA', (size, size), solid_bg + (255,))
    out.alpha_composite(img)
    return out

def design_at(size):
    """The user's full design (rounded square + note), scaled to `size`."""
    return master.resize((size, size), Image.LANCZOS)

def ios_at(size, note_frac=0.53):
    """Opaque full-bleed square: gradient bg + note centered, Apple-friendly."""
    nw = int(size * note_frac)
    nh = int(note.height / note.width * nw)
    n = note.resize((nw, nh), Image.LANCZOS)
    out = vertical_gradient(size, top, mid, bot).convert('RGBA')
    out.alpha_composite(n, ( (size - nw) // 2, (size - nh) // 2 ))
    return out

def adaptive_foreground(size, weight=0.54):
    """Note only, centered within adaptive safe zone."""
    nw = int(size * weight)
    nh = int(note.height / note.width * nw)
    n = note.resize((nw, nh), Image.LANCZOS)
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    out.alpha_composite(n, ( (size - nw) // 2, (size - nh) // 2 ))
    return out

def save(img, rel, base=RES):
    path = os.path.join(base, *rel.split('/'))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out = img.convert('RGBA')
    out.save(path)
    print(f'  wrote {rel} ({out.size[0]}x{out.size[1]})')

# --- Android legacy launcher -----------------------------------------
LEGACY = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
for dpi, size in LEGACY.items():
    for name in ('ic_launcher.png', 'ic_launcher_round.png'):
        save(design_at(size), f'mipmap-{dpi}/{name}')

# --- Android adaptive -------------------------------------------------
ADAPTIVE = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}
for dpi, size in ADAPTIVE.items():
    save(adaptive_foreground(size), f'drawable-{dpi}/ic_launcher_foreground.png')
    save(vertical_gradient(size, top, mid, bot).convert('RGBA'),
         f'drawable-{dpi}/ic_launcher_background.png')

# Android 13 themed (monochrome) icon — note silhouette in safe zone
MONO = 432
_nw = int(MONO * 0.54)
_nh = int(note.height / note.width * _nw)
_n = note.resize((_nw, _nh), Image.LANCZOS)
mono = Image.new('RGBA', (MONO, MONO), (0, 0, 0, 0))
mono.alpha_composite(_n, ((MONO - _n.width) // 2, (MONO - _n.height) // 2))
save(mono, 'drawable/ic_launcher_monochrome.png')

# adaptive XML: point background to gradient, add monochrome
xml = os.path.join(RES, 'mipmap-anydpi-v26', 'ic_launcher.xml')
with open(xml) as f:
    content = f.read()
for variant in ('ic_launcher.xml', 'ic_launcher_round.xml'):
    p = os.path.join(RES, 'mipmap-anydpi-v26', variant)
    with open(p) as f:
        c = f.read()
    c = c.replace('<background android:drawable="@drawable/ic_launcher_background"/>',
                  '<background android:drawable="@drawable/ic_launcher_background"/>')
    if '<monochrome' not in c:
        c = c.replace('</adaptive-icon>',
                      '    <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>\n</adaptive-icon>')
    with open(p, 'w') as f:
        f.write(c)
    print(f'  updated mipmap-anydpi-v26/{variant} (+monochrome)')

# --- Android notification icons (white note) -------------------------
NOTIF = {'mdpi': 24, 'hdpi': 36, 'xhdpi': 48, 'xxhdpi': 72, 'xxxhdpi': 96}
for dpi, size in NOTIF.items():
    save(adaptive_foreground(size, weight=0.9), f'drawable-{dpi}/ic_notification.png')
save(adaptive_foreground(48, weight=0.9), 'drawable/ic_notification_monochrome.png')

# --- iOS AppIcon set (opaque full-bleed) -----------------------------
IOS = os.path.join(HERE, 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset')
IOS_SIZES = {
    'Icon-App-20x20@1x.png': 20, 'Icon-App-20x20@2x.png': 40, 'Icon-App-20x20@3x.png': 60,
    'Icon-App-29x29@1x.png': 29, 'Icon-App-29x29@2x.png': 58, 'Icon-App-29x29@3x.png': 87,
    'Icon-App-40x40@1x.png': 40, 'Icon-App-40x40@2x.png': 80, 'Icon-App-40x40@3x.png': 120,
    'Icon-App-60x60@2x.png': 120, 'Icon-App-60x60@3x.png': 180,
    'Icon-App-76x76@1x.png': 76, 'Icon-App-76x76@2x.png': 152,
    'Icon-App-83.5x83.5@2x.png': 167,
    'Icon-App-1024x1024@1x.png': 1024,
}
for name, size in IOS_SIZES.items():
    img = ios_at(size).convert('RGB')
    img.save(os.path.join(IOS, name))
    print(f'  wrote iOS/{name} ({size}x{size})')

# --- in-app asset sizes ----------------------------------------------
AICONS = os.path.join(HERE, 'assets', 'icons')
for size in (1024, 512, 256, 180, 128, 96, 72, 64, 48, 32):
    save(design_at(size), f'icon_{size}.png', base=AICONS)
print('done.')