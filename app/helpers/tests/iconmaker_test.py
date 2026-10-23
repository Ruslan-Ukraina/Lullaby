#!/usr/bin/env python3 -I
"""iconmaker: the look (body, rim, logo on a solid fill), the choice of the biggest input, the .icns, the time.

    python3 -I app/helpers/tests/iconmaker_test.py out/iconmaker
"""
import os, struct, subprocess, sys, tempfile, time, zlib

tool = sys.argv[1]
fails = 0


def check(cond, what):
    global fails
    if not cond:
        print("FAIL", what)
        fails += 1


def write_png(path, w, h, pixel):
    raw = b"".join(b"\x00" + b"".join(bytes(pixel(x, y)) for x in range(w)) for y in range(h))

    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d))
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def read_png(path):
    data = open(path, "rb").read()
    pos, idat, w, h, depth, ctype = 8, b"", 0, 0, 0, 0
    while pos < len(data):
        n, t = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        if t == b"IHDR":
            w, h, depth, ctype = struct.unpack(">IIBB", body[:10])
        elif t == b"IDAT":
            idat += body
        pos += 12 + n
    assert depth == 8 and ctype == 6, (depth, ctype)
    raw, bpp, stride, rows, prev = zlib.decompress(idat), 4, w * 4, [], bytearray(w * 4)
    i = 0
    for _ in range(h):
        f, line = raw[i], bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        for k in range(stride):
            a = line[k - bpp] if k >= bpp else 0
            b = prev[k]
            c = prev[k - bpp] if k >= bpp else 0
            if f == 1: line[k] = (line[k] + a) & 255
            elif f == 2: line[k] = (line[k] + b) & 255
            elif f == 3: line[k] = (line[k] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[k] = (line[k] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(line)
        prev = line
    return w, h, rows


def px(img, x, y):
    return tuple(img[2][y][x * 4:x * 4 + 4])


def run(args):
    t = time.time()
    r = subprocess.run([tool] + args, capture_output=True, text=True)
    return r, time.time() - t


with tempfile.TemporaryDirectory() as d:
    # A: art that fills its square (red, a white block in the middle).
    art = os.path.join(d, "art.png")
    write_png(art, 256, 256, lambda x, y: (255, 255, 255, 255) if 96 < x < 160 and 96 < y < 160 else (200, 30, 30, 255))
    # B: a logo on a transparent background (a green disc).
    logo = os.path.join(d, "logo.png")
    write_png(logo, 256, 256, lambda x, y: (30, 160, 60, 255) if (x - 128) ** 2 + (y - 128) ** 2 < 90 ** 2 else (0, 0, 0, 0))
    # C: 48 px blue, and D: 256 px orange, for the choice of the bigger.
    small = os.path.join(d, "small.png")
    write_png(small, 48, 48, lambda x, y: (20, 40, 220, 255))
    big = os.path.join(d, "big.png")
    write_png(big, 256, 256, lambda x, y: (240, 140, 20, 255))

    out, prev = os.path.join(d, "a.icns"), os.path.join(d, "a.png")
    r, secs = run([art, out, "--png", prev])
    check(r.returncode == 0, "art: runs: " + r.stderr)
    check(secs < 2.0, f"art: {secs:.2f} s is quick enough")
    img = read_png(prev)
    check(px(img, 5, 5)[3] < 40, "art: the corner of the canvas is clear (margin and shadow only)")
    check(px(img, 512, 512)[:3] == (255, 255, 255), "art: the middle is the art's own white block")
    r_, g_, b_, a_ = px(img, 200, 512)
    check(r_ > 150 and g_ < 80 and a_ == 255, f"art: the picture fills the body ({px(img, 200, 512)})")
    top = px(img, 512, 104)
    check(top[1] > 100 and top[2] > 100, f"art: a light specular rim along the top edge over the red ({top})")
    side = px(img, 104, 512)
    check(side[0] < 200 - 5, f"art: a darker thin edge on the sides ({side})")
    check(px(img, 101, 101)[3] < 255, "art: the body's corner is rounded off")

    out2, prev2 = os.path.join(d, "b.icns"), os.path.join(d, "b.png")
    r, secs = run([logo, out2, "--png", prev2])
    check(r.returncode == 0, "logo: runs: " + r.stderr)
    img = read_png(prev2)
    c = px(img, 512, 512)
    check(c[1] > c[0] and c[1] > c[2], f"logo: the logo stays in the middle ({c})")
    f = px(img, 200, 512)
    check(f[1] > f[0] and f[1] > f[2] and f[3] == 255, f"logo: the fill is the logo's main colour ({f})")
    check(abs(f[1] - c[1]) > 20 or abs(f[0] - c[0]) > 20, f"logo: the fill differs from the logo so it shows ({f} vs {c})")
    check(px(img, 150, 512)[:3] == f[:3], "logo: the fill is solid")

    out3, prev3 = os.path.join(d, "c.icns"), os.path.join(d, "c.png")
    r, _ = run([small, out3, "--alt", big, "--png", prev3])
    img = read_png(prev3)
    c = px(img, 512, 512)
    check(c[0] > 200 and c[2] < 80, f"alt: the bigger input is the one drawn ({c})")
    r, _ = run([big, out3, "--alt", small, "--png", prev3])
    c = px(read_png(prev3), 512, 512)
    check(c[0] > 200 and c[2] < 80, f"alt: still the bigger when it comes first ({c})")

    # The .icns: magic, length, and the system reads it back.
    blob = open(out, "rb").read()
    check(blob[:4] == b"icns" and struct.unpack(">I", blob[4:8])[0] == len(blob), "icns: header and length")
    iconset = os.path.join(d, "a.iconset")
    r = subprocess.run(["/usr/bin/iconutil", "-c", "iconset", out, "-o", iconset], capture_output=True, text=True)
    check(r.returncode == 0, "icns: iconutil reads it: " + r.stderr)
    names = sorted(os.listdir(iconset)) if os.path.isdir(iconset) else []
    check(len(names) >= 10, f"icns: all sizes present ({len(names)})")

    r, _ = run([os.path.join(d, "nothing.png"), os.path.join(d, "x.icns")])
    check(r.returncode != 0, "an unreadable input fails")

if fails:
    print(f"iconmaker_test: {fails} failed")
    sys.exit(1)
print("iconmaker_test: look, choice of the bigger input, .icns and time hold")
