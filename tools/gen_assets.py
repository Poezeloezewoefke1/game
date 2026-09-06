#!/usr/bin/env python3
"""Generates ORIGINAL placeholder art for UNSTABLE: LAST STAND.

- Placeholder Minecraft-layout skins for every character that has no developer-supplied skin.
  (Drop real skins as assets/skins/<id>.png or user://skins/<id>.png and they take priority.)
- A UV-test skin with labelled faces used by the automated skin-mapping tests.
- A 16x16 armor/metal pattern texture and a set of 16x16 block textures (original pixel art, not Minecraft's).

Every generated file is registered in data/asset_manifest.json as generated/placeholder.
"""
import json, os, random, math
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKINS = os.path.join(ROOT, "assets", "skins")
TEX = os.path.join(ROOT, "assets", "textures")
os.makedirs(SKINS, exist_ok=True)
os.makedirs(TEX, exist_ok=True)

KEEP_IMPORT = "[remap]\n\nimporter=\"keep\"\n"

def write_keep(path):
    with open(path + ".import", "w") as f:
        f.write(KEEP_IMPORT)

# ---------------------------------------------------------------- characters
# id, primary, secondary(hair/legs), accent, skin tone, slim?, extras
CHARACTERS = {
    # Protagonists (placeholder palettes only; real skins must be supplied by the developer)
    "wemmbu":      ((40, 40, 48), (25, 25, 30), (230, 60, 60), (232, 190, 160), False, {"hood": True}),
    "flamefrags":  ((190, 60, 30), (60, 30, 20), (255, 170, 40), (232, 190, 160), False, {"flame_hair": True}),
    "parrotx2":    ((50, 120, 210), (40, 60, 90), (240, 210, 70), (232, 190, 160), False, {"crown": True}),
    "spokeishere": ((70, 60, 110), (30, 25, 45), (140, 220, 120), (232, 190, 160), True, {"mask": True}),
    # Allies / towers
    "theobaldthebird": ((90, 70, 40), (50, 40, 25), (230, 230, 230), (232, 190, 160), False, {"bird": True}),
    "eggchan":         ((245, 240, 220), (240, 200, 90), (255, 255, 255), (245, 240, 220), False, {"egg": True}),
    "lomedy":          ((60, 110, 50), (90, 60, 30), (200, 170, 90), (232, 190, 160), False, {"hat": True}),
    "mapicc":          ((200, 40, 40), (30, 30, 30), (255, 255, 255), (232, 190, 160), False, {}),
    "leow0ok":         ((40, 40, 40), (20, 20, 20), (200, 40, 200), (232, 190, 160), True, {}),
    "minutetech":      ((80, 80, 90), (40, 40, 45), (90, 220, 255), (232, 190, 160), False, {"goggles": True}),
    "reinadrop":       ((230, 120, 170), (80, 40, 60), (255, 255, 200), (240, 200, 180), True, {"flower": True}),
    "reddoons":        ((190, 30, 30), (60, 20, 20), (240, 220, 160), (232, 190, 160), False, {}),
    "fymada":          ((210, 180, 90), (110, 80, 40), (60, 60, 200), (232, 190, 160), False, {}),
    "4cvit":           ((70, 130, 220), (40, 80, 150), (120, 240, 120), (110, 190, 240), False, {"slime": True}),
    "jaden_man":       ((40, 40, 60), (20, 20, 30), (220, 40, 40), (232, 190, 160), False, {"pirate": True}),
    "purpled":         ((150, 80, 220), (60, 30, 100), (255, 255, 255), (232, 190, 160), False, {}),
    "spepticle":       ((90, 60, 30), (50, 35, 20), (250, 240, 200), (232, 190, 160), False, {"owl": True}),
    "deputy_ace":      ((40, 60, 110), (30, 30, 40), (240, 200, 60), (232, 190, 160), False, {"badge": True}),
    "yungyx":          ((60, 30, 90), (20, 10, 30), (200, 60, 255), (232, 190, 160), False, {}),
    "zoe":             ((120, 200, 120), (60, 90, 60), (255, 255, 255), (240, 200, 180), True, {}),
    "princezam":       ((220, 200, 60), (90, 70, 20), (60, 60, 200), (232, 190, 160), False, {"crown": True}),
    # Villains / bosses
    "saparata":        ((110, 20, 20), (40, 10, 10), (255, 120, 30), (232, 190, 160), False, {"crown": True, "scar": True}),
    "shoebilly":       ((30, 30, 30), (15, 15, 15), (200, 200, 200), (232, 190, 160), False, {"mask": True}),
    "arachn1d":        ((30, 20, 40), (10, 5, 15), (200, 40, 40), (200, 190, 220), False, {"spider": True}),
    "ashswagg":        ((30, 30, 30), (10, 10, 10), (255, 255, 255), (232, 190, 160), False, {"invis": True}),
    "clownpierce":     ((200, 30, 30), (40, 20, 20), (255, 255, 255), (245, 245, 245), False, {"clown": True}),
    "lettucek":        ((80, 160, 60), (40, 80, 30), (240, 240, 240), (232, 190, 160), False, {}),
    "sargelaw":        ((40, 60, 120), (20, 30, 60), (255, 220, 60), (232, 190, 160), False, {"badge": True}),
    # Generic enemies
    "chungie":         ((120, 150, 200), (80, 90, 120), (255, 255, 255), (232, 190, 160), False, {}),
    "chungie_b":       ((200, 150, 100), (100, 80, 60), (255, 255, 255), (200, 160, 130), False, {}),
    "chungie_c":       ((110, 180, 110), (60, 90, 60), (255, 255, 255), (232, 190, 160), True, {}),
    "cindercrest_soldier": ((120, 30, 20), (40, 15, 10), (255, 140, 40), (232, 190, 160), False, {}),
    "royal_soldier":   ((50, 90, 190), (30, 40, 80), (240, 210, 70), (232, 190, 160), False, {}),
    "lawman":          ((40, 60, 120), (20, 30, 60), (255, 220, 60), (232, 190, 160), False, {"badge": True}),
    "mafia_invis":     ((60, 60, 60), (30, 30, 30), (120, 120, 120), (232, 190, 160), False, {"invis": True}),
    "pirate":          ((60, 40, 30), (30, 20, 15), (220, 40, 40), (232, 190, 160), False, {"pirate": True}),
}

def draw_skin(pid, primary, secondary, accent, tone, slim, extras):
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    def rect(x, y, w, h, c):
        d.rectangle([x, y, x + w - 1, y + h - 1], fill=c + (255,) if len(c) == 3 else c)
    def shade(c, f):
        return tuple(max(0, min(255, int(v * f))) for v in c)
    # HEAD 0,0 : top(8,0) bottom(16,0) right(0,8) front(8,8) left(16,8) back(24,8)
    rect(0, 8, 32, 8, tone)
    rect(8, 0, 8, 8, secondary)           # top = hair
    rect(16, 0, 8, 8, shade(tone, 0.85))  # bottom = chin
    rect(0, 8, 32, 3, secondary)          # hairline on all side faces
    rect(24, 8, 8, 8, secondary)          # back of head = hair
    rect(0, 8, 8, 5, secondary)           # sides of hair
    rect(16, 8, 8, 5, secondary)
    # face
    rect(9, 11, 2, 2, (255, 255, 255)); rect(13, 11, 2, 2, (255, 255, 255))
    rect(10, 12, 1, 1, (30, 30, 60)); rect(14, 12, 1, 1, (30, 30, 60))
    rect(11, 14, 2, 1, shade(tone, 0.6))
    if extras.get("mask"):
        rect(8, 12, 8, 4, shade(secondary, 0.8)); rect(9, 11, 2, 2, (255, 255, 255)); rect(13, 11, 2, 2, (255, 255, 255))
        rect(10, 12, 1, 1, (30, 30, 60)); rect(14, 12, 1, 1, (30, 30, 60))
    if extras.get("clown"):
        rect(11, 13, 2, 2, (255, 40, 40)); rect(9, 10, 1, 1, (60, 120, 255)); rect(14, 10, 1, 1, (60, 120, 255))
    if extras.get("scar"):
        rect(12, 9, 1, 4, (150, 60, 60))
    if extras.get("egg"):
        rect(0, 8, 32, 8, (245, 240, 220)); rect(8, 0, 16, 8, (245, 240, 220))
        rect(9, 11, 2, 2, (30, 30, 30)); rect(13, 11, 2, 2, (30, 30, 30)); rect(11, 14, 2, 1, (200, 120, 100))
    if extras.get("slime"):
        rect(0, 8, 32, 8, (110, 190, 240)); rect(8, 0, 16, 8, (110, 190, 240))
        rect(9, 11, 2, 2, (30, 30, 30)); rect(13, 11, 2, 2, (30, 30, 30))
    if extras.get("bird"):
        rect(11, 12, 2, 2, (240, 170, 50))   # beak
    if extras.get("owl"):
        rect(8, 10, 8, 4, (200, 180, 140)); rect(9, 11, 2, 2, (255, 230, 60)); rect(13, 11, 2, 2, (255, 230, 60))
        rect(10, 12, 1, 1, (0, 0, 0)); rect(14, 12, 1, 1, (0, 0, 0)); rect(11, 13, 2, 1, (240, 170, 50))
    if extras.get("spider"):
        rect(0, 8, 32, 8, (200, 190, 220)); rect(8, 0, 16, 8, (40, 20, 60))
        for (x, y) in [(9, 10), (11, 9), (13, 9), (15, 10), (10, 12), (14, 12)]:
            rect(x, y, 1, 1, (200, 40, 40))
    # HAT LAYER 32,0 : crowns / hoods / hats / goggles
    if extras.get("crown"):
        rect(32, 8, 32, 2, accent)
        for x in range(32, 64, 4):
            rect(x, 7, 2, 1, accent)
    if extras.get("hood"):
        rect(40, 0, 8, 8, secondary); rect(32, 8, 8, 8, secondary); rect(48, 8, 16, 8, secondary); rect(40, 8, 8, 2, secondary)
    if extras.get("hat"):
        rect(40, 0, 8, 8, (90, 60, 30)); rect(32, 8, 32, 3, (90, 60, 30))
    if extras.get("goggles"):
        rect(40, 10, 8, 3, (30, 30, 40)); rect(41, 11, 2, 1, accent); rect(45, 11, 2, 1, accent)
    if extras.get("pirate"):
        rect(40, 0, 8, 8, (30, 30, 30)); rect(32, 8, 32, 3, (30, 30, 30)); rect(41, 11, 2, 2, (20, 20, 20))
    if extras.get("flame_hair"):
        rect(40, 0, 8, 8, accent); rect(32, 8, 32, 2, accent)
    if extras.get("flower"):
        rect(50, 9, 2, 2, (255, 255, 255)); rect(50, 9, 1, 1, (250, 220, 60))
    # BODY 16,16 : top(20,16) bottom(28,16) right(16,20) front(20,20) left(28,20) back(32,20)
    rect(16, 16, 24, 16, primary)
    rect(20, 16, 8, 4, shade(primary, 0.9))
    rect(28, 16, 8, 4, shade(primary, 0.7))
    rect(21, 22, 6, 2, accent)           # chest stripe / emblem
    rect(20, 29, 8, 3, shade(primary, 0.75))  # belt
    if extras.get("badge"):
        rect(21, 21, 2, 2, (255, 220, 60))
    if extras.get("egg"):
        rect(16, 16, 24, 16, (240, 200, 90))
    # BODY OUTER 16,32 : small vest details (mostly transparent)
    if extras.get("invis"):
        pass
    else:
        rect(20, 36, 1, 8, shade(primary, 0.5)); rect(27, 36, 1, 8, shade(primary, 0.5))
    # RIGHT ARM 40,16 (w=4 or 3): top(44,16) bottom(48,16) right(40,20) front(44,20) left(48,20) back(52,20)
    aw = 3 if slim else 4
    rect(40, 16, 16, 16, primary)
    rect(40, 26, 16, 6, tone)             # hand/skin lower part
    rect(40, 20, 16, 1, shade(primary, 0.8))
    if slim:
        # clear unused columns for slim layout detection
        rect(50, 16, 2, 4, (0, 0, 0, 0)); rect(54, 20, 2, 12, (0, 0, 0, 0))
        # redraw faces at 3px width: right(40..44) front(44..47) left(47..51) back(51..54)
        rect(40, 16, 14, 16, primary); rect(40, 26, 14, 6, tone); rect(50, 16, 2, 4, (0, 0, 0, 0)); rect(54, 20, 2, 12, (0, 0, 0, 0))
        rect(43, 16, 3, 4, shade(primary, 0.9)); rect(46, 16, 3, 4, tone); rect(49, 16, 5, 4, (0, 0, 0, 0))
    # LEFT ARM 32,48
    rect(32, 48, 16, 16, primary)
    rect(32, 58, 16, 6, tone)
    rect(32, 52, 16, 1, shade(primary, 0.8))
    if slim:
        rect(42, 48, 2, 4, (0, 0, 0, 0)); rect(46, 52, 2, 12, (0, 0, 0, 0))
        rect(35, 48, 3, 4, shade(primary, 0.9)); rect(38, 48, 3, 4, tone); rect(41, 48, 5, 4, (0, 0, 0, 0))
    # RIGHT LEG 0,16 : top(4,16) bottom(8,16) right(0,20) front(4,20) left(8,20) back(12,20)
    rect(0, 16, 16, 16, secondary)
    rect(0, 28, 16, 4, (35, 25, 20))      # boots
    rect(4, 16, 4, 4, shade(secondary, 0.9)); rect(8, 16, 4, 4, (35, 25, 20))
    # LEFT LEG 16,48
    rect(16, 48, 16, 16, secondary)
    rect(16, 60, 16, 4, (35, 25, 20))
    rect(20, 48, 4, 4, shade(secondary, 0.9)); rect(24, 48, 4, 4, (35, 25, 20))
    # Sleeve/pants outer layers: cuffs
    rect(40, 32, 16, 2, shade(primary, 0.6)); rect(48, 48, 16, 2, shade(primary, 0.6))
    if extras.get("invis"):
        # semi-transparent look: thin out body pixels
        px = img.load()
        for y in range(16, 64):
            for x in range(0, 64):
                if px[x, y][3] > 0 and (x + y) % 2 == 0:
                    px[x, y] = (px[x, y][0], px[x, y][1], px[x, y][2], 110)
    return img

def uv_test_skin():
    """Each face of every part gets a distinct colour + an arrow (pointing to the face's top) so a
    rendered character can be visually checked, and tests can verify sampled UVs land in the right region."""
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    colors = {"top": (255, 0, 0), "bottom": (0, 0, 255), "right": (0, 200, 0), "front": (255, 255, 0), "left": (0, 255, 255), "back": (255, 0, 255)}
    def net(u, v, w, h, dd):
        faces = {
            "top": (u + dd, v, w, dd), "bottom": (u + dd + w, v, w, dd),
            "right": (u, v + dd, dd, h), "front": (u + dd, v + dd, w, h),
            "left": (u + dd + w, v + dd, dd, h), "back": (u + 2 * dd + w, v + dd, w, h),
        }
        for name, (x, y, fw, fh) in faces.items():
            d.rectangle([x, y, x + fw - 1, y + fh - 1], fill=colors[name] + (255,))
            # mark the top-left pixel dark and top row darker so orientation is testable
            d.rectangle([x, y, x + fw - 1, y], fill=tuple(int(c * 0.5) for c in colors[name]) + (255,))
            d.point((x, y), fill=(0, 0, 0, 255))
    net(0, 0, 8, 8, 8)      # head
    net(16, 16, 8, 12, 4)   # body
    net(40, 16, 4, 12, 4)   # right arm
    net(32, 48, 4, 12, 4)   # left arm
    net(0, 16, 4, 12, 4)    # right leg
    net(16, 48, 4, 12, 4)   # left leg
    # hat layer: only a thin band so the outer layer visibly exists
    d.rectangle([32 + 8, 0 + 8, 32 + 15, 0 + 9], fill=(255, 255, 255, 255))
    return img

def legacy_test_skin():
    img = uv_test_skin().crop((0, 0, 64, 32))
    return img

# ---------------------------------------------------------------- textures
def noise_tex(base, var=18, size=16, seed=1, stripes=None, speckle=None):
    rnd = random.Random(seed)
    img = Image.new("RGBA", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            n = rnd.randint(-var, var)
            c = tuple(max(0, min(255, b + n)) for b in base)
            px[x, y] = c + (255,)
    if stripes:
        for y in range(0, size, stripes[0]):
            for x in range(size):
                c = px[x, y]
                px[x, y] = tuple(max(0, int(v * stripes[1])) for v in c[:3]) + (255,)
    if speckle:
        for _ in range(speckle[0]):
            x, y = rnd.randrange(size), rnd.randrange(size)
            px[x, y] = speckle[1] + (255,)
    return img

def bricks(base, mortar, size=16, seed=2, bw=8, bh=4):
    img = noise_tex(base, 10, size, seed)
    px = img.load()
    for y in range(size):
        for x in range(size):
            row = y // bh
            off = (bw // 2) if row % 2 else 0
            if y % bh == 0 or (x + off) % bw == 0:
                px[x, y] = mortar + (255,)
    return img

def armor_pattern():
    img = Image.new("RGBA", (16, 16))
    px = img.load()
    rnd = random.Random(7)
    for y in range(16):
        for x in range(16):
            v = 235 + rnd.randint(-12, 8)
            # plate seams
            if x % 8 == 0 or y % 8 == 0:
                v -= 60
            # rivets
            if (x % 8 == 2 and y % 8 == 2) or (x % 8 == 6 and y % 8 == 6):
                v = 255
            # bevel highlight
            if x % 8 == 1 or y % 8 == 1:
                v += 12
            v = max(0, min(255, v))
            px[x, y] = (v, v, v, 255)
    return img

def planks(base, size=16, seed=3):
    img = noise_tex(base, 8, size, seed)
    px = img.load()
    for y in range(size):
        for x in range(size):
            if y % 4 == 0:
                c = px[x, y]; px[x, y] = tuple(int(v * 0.6) for v in c[:3]) + (255,)
            if (y // 4) % 2 == 0 and x == 3 or (y // 4) % 2 == 1 and x == 11:
                c = px[x, y]; px[x, y] = tuple(int(v * 0.7) for v in c[:3]) + (255,)
    return img

def log_side(base, size=16):
    img = noise_tex(base, 8, size, 4)
    px = img.load()
    for y in range(size):
        for x in range(size):
            if x % 3 == 0:
                c = px[x, y]; px[x, y] = tuple(int(v * 0.75) for v in c[:3]) + (255,)
    return img

def log_top(base, ring, size=16):
    img = noise_tex(base, 6, size, 5)
    px = img.load()
    for y in range(size):
        for x in range(size):
            r = max(abs(x - 7.5), abs(y - 7.5))
            if int(r) % 2 == 0:
                px[x, y] = ring + (255,)
    return img

def leaves(base, size=16):
    img = noise_tex(base, 22, size, 6)
    px = img.load()
    rnd = random.Random(9)
    for y in range(size):
        for x in range(size):
            if rnd.random() < 0.15:
                px[x, y] = (0, 0, 0, 0)
    return img

def lava(size=16):
    img = Image.new("RGBA", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            v = (math.sin(x * 0.9) + math.cos(y * 0.7) + math.sin((x + y) * 0.5)) / 3.0
            r = int(200 + 55 * v); g = int(90 + 80 * v); b = int(10 + 20 * v)
            px[x, y] = (max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)), 255)
    return img

def water(size=16):
    img = Image.new("RGBA", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            v = (math.sin(x * 0.8 + y * 0.3) + math.cos(y * 0.9)) / 2.0
            px[x, y] = (int(30 + 20 * v), int(80 + 30 * v), int(190 + 40 * v), 200)
    return img

def wool(base, size=16, seed=11):
    img = noise_tex(base, 10, size, seed)
    px = img.load()
    for y in range(size):
        for x in range(size):
            if (x + y) % 4 == 0:
                c = px[x, y]; px[x, y] = tuple(int(v * 0.9) for v in c[:3]) + (255,)
    return img

TEXTURES = {
    "grass_top": lambda: noise_tex((92, 150, 60), 20, seed=21, speckle=(10, (120, 180, 80))),
    "grass_side": lambda: None,  # built from dirt + grass overlay below
    "dirt": lambda: noise_tex((120, 85, 55), 16, seed=22),
    "stone": lambda: noise_tex((125, 125, 128), 14, seed=23),
    "stone_bricks": lambda: bricks((118, 118, 122), (80, 80, 84), seed=24),
    "cobble": lambda: bricks((110, 108, 112), (70, 68, 72), seed=25, bw=4, bh=4),
    "planks": lambda: planks((170, 130, 80)),
    "dark_planks": lambda: planks((95, 65, 40), seed=31),
    "log_side": lambda: log_side((95, 70, 40)),
    "log_top": lambda: log_top((170, 140, 90), (120, 95, 60)),
    "leaves": lambda: leaves((50, 120, 45)),
    "dead_leaves": lambda: leaves((110, 70, 35)),
    "netherrack": lambda: noise_tex((110, 40, 40), 22, seed=41, speckle=(14, (150, 60, 50))),
    "blackstone": lambda: bricks((45, 42, 48), (25, 23, 28), seed=42),
    "basalt": lambda: log_side((60, 58, 64)),
    "gravel": lambda: noise_tex((130, 125, 120), 25, seed=43),
    "path": lambda: noise_tex((150, 125, 85), 14, seed=44),
    "sand": lambda: noise_tex((215, 200, 150), 10, seed=45),
    "snow": lambda: noise_tex((240, 244, 250), 6, seed=46),
    "lava": lava,
    "water": water,
    "magma": lambda: noise_tex((70, 30, 25), 20, seed=47, speckle=(18, (230, 120, 30))),
    "wool_blue": lambda: wool((50, 90, 190)),
    "wool_red": lambda: wool((170, 35, 30), seed=12),
    "wool_gold": lambda: wool((230, 190, 70), seed=13),
    "wool_white": lambda: wool((235, 235, 230), seed=14),
    "wool_black": lambda: wool((30, 30, 34), seed=15),
    "iron_block": lambda: bricks((215, 215, 220), (160, 160, 168), seed=16, bw=8, bh=8),
    "gold_block": lambda: bricks((240, 200, 70), (180, 140, 40), seed=17, bw=8, bh=8),
    "obsidian": lambda: noise_tex((25, 15, 40), 10, seed=18),
    "glass": lambda: None,
    "crying": lambda: noise_tex((40, 25, 70), 12, seed=19, speckle=(12, (120, 90, 220))),
    "tnt_side": lambda: None,
    "tnt_top": lambda: None,
}

def build_textures():
    out = {}
    for name, fn in TEXTURES.items():
        img = fn()
        if img is not None:
            out[name] = img
    dirt = out["dirt"]
    gs = dirt.copy(); px = gs.load(); gt = out["grass_top"].load()
    rnd = random.Random(51)
    for y in range(16):
        for x in range(16):
            if y < 3 or (y < 5 and rnd.random() < 0.5):
                px[x, y] = gt[x, y]
    out["grass_side"] = gs
    glass = Image.new("RGBA", (16, 16), (200, 230, 255, 70))
    d = ImageDraw.Draw(glass); d.rectangle([0, 0, 15, 15], outline=(230, 245, 255, 200))
    out["glass"] = glass
    tnt = Image.new("RGBA", (16, 16), (200, 40, 30, 255))
    d = ImageDraw.Draw(tnt); d.rectangle([0, 6, 15, 9], fill=(240, 240, 235, 255)); d.text((3, 5), "TNT", fill=(20, 20, 20, 255))
    out["tnt_side"] = tnt
    tt = Image.new("RGBA", (16, 16), (200, 40, 30, 255)); d = ImageDraw.Draw(tt)
    for i in range(0, 16, 4):
        for j in range(0, 16, 4):
            d.rectangle([i + 1, j + 1, i + 2, j + 2], fill=(240, 240, 235, 255))
    out["tnt_top"] = tt
    return out

def main():
    manifest_path = os.path.join(ROOT, "data", "asset_manifest.json")
    manifest = {"assets": []}
    if os.path.exists(manifest_path):
        with open(manifest_path) as f:
            try:
                manifest = json.load(f)
            except Exception:
                manifest = {"assets": []}
    existing = {a["id"]: a for a in manifest.get("assets", []) if "id" in a}
    generated = []
    for pid, (primary, secondary, accent, tone, slim, extras) in CHARACTERS.items():
        path = os.path.join(SKINS, pid + ".png")
        rec = existing.get(pid)
        if os.path.exists(path) and rec and rec.get("source") != "generated_placeholder":
            print("keeping supplied skin", pid)
            continue
        draw_skin(pid, primary, secondary, accent, tone, slim, extras).save(path)
        write_keep(path)
        existing[pid] = {
            "id": pid, "asset": "assets/skins/%s.png" % pid, "type": "skin",
            "source": "generated_placeholder", "creator": "UNSTABLE: LAST STAND build tools (procedural)",
            "license": "Project-original placeholder. Replace with a developer-licensed skin of the real character.",
            "usage": "Character 3D model texture", "model": "slim" if slim else "classic",
            "placeholder": True,
        }
        generated.append(pid)
    for name, img in [("uv_test", uv_test_skin()), ("uv_test_legacy", legacy_test_skin())]:
        path = os.path.join(SKINS, name + ".png")
        img.save(path); write_keep(path)
        existing[name] = {"id": name, "asset": "assets/skins/%s.png" % name, "type": "skin",
                          "source": "generated_test", "creator": "build tools", "license": "Project-original",
                          "usage": "Automated UV-mapping test", "placeholder": True}
    ap = os.path.join(TEX, "armor_pattern.png"); armor_pattern().save(ap); write_keep(ap)
    existing["armor_pattern"] = {"id": "armor_pattern", "asset": "assets/textures/armor_pattern.png", "type": "texture",
                                 "source": "generated", "creator": "build tools", "license": "Project-original",
                                 "usage": "Armor/weapon surface detail", "placeholder": False}
    for name, img in build_textures().items():
        p = os.path.join(TEX, "block_%s.png" % name); img.save(p); write_keep(p)
        existing["block_" + name] = {"id": "block_" + name, "asset": "assets/textures/block_%s.png" % name, "type": "texture",
                                     "source": "generated", "creator": "build tools", "license": "Project-original pixel art",
                                     "usage": "Map block texture", "placeholder": False}
    manifest["assets"] = sorted(existing.values(), key=lambda a: a["id"])
    manifest["notes"] = [
        "Placeholder skins are procedurally generated and are NOT the real creators' skins.",
        "To use a real skin: place a Minecraft-compatible 64x64 (or 64x32 / HD) PNG at assets/skins/<id>.png "
        "(or user://skins/<id>.png at runtime) and set source/license here. Supplied files are never overwritten.",
        "No Mojang/Minecraft game assets are included. All block textures are original pixel art.",
    ]
    os.makedirs(os.path.dirname(manifest_path), exist_ok=True)
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)
    print("generated placeholder skins:", len(generated), "| total assets:", len(existing))

if __name__ == "__main__":
    main()
