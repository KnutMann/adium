#!/usr/bin/env python3
"""Draw the three message field buttons (Resources/entry_*.png) in the style of the old smiley: a 16 pt glyph in one
grey (153,153,153), anti-aliased, no triangle. Each shape is described once in a 16 unit space
and rendered at 1x and 2x through 8x supersampling, so both files come from one drawing.

Needs Pillow (pip install pillow), which a plain Xcode installation does not have.

  Utilities/draw-entry-icons.py Resources
"""
from PIL import Image, ImageDraw
import math, sys, os

GREY = (153, 153, 153)
OUT = sys.argv[1]
SS = 8  # supersampling

def canvas(scale):
    n = 16 * scale * SS
    return Image.new("RGBA", (n, n), GREY + (0,)), scale * SS

def finish(img, scale, name):
    small = img.resize((16 * scale, 16 * scale), Image.LANCZOS)
    small.save(os.path.join(OUT, name))
    return small

def stroke_arc(d, box, start, end, width, k):
    x0, y0, x1, y1 = [v * k for v in box]
    d.arc([x0, y0, x1, y1], start, end, fill=GREY + (255,), width=int(round(width * k)))

def line(d, pts, width, k):
    d.line([(x * k, y * k) for x, y in pts], fill=GREY + (255,), width=int(round(width * k)), joint="curve")

def dot(d, cx, cy, r, k):
    d.ellipse([(cx - r) * k, (cy - r) * k, (cx + r) * k, (cy + r) * k], fill=GREY + (255,))

def round_cap(d, x, y, width, k):
    dot(d, x, y, width / 2, k)

# The smiley, exactly the old one without the triangle: a ring, two eyes, a smile.
def smiley(scale):
    img, k = canvas(scale); d = ImageDraw.Draw(img)
    stroke_arc(d, (0.75, 0.75, 15.25, 15.25), 0, 360, 1.5, k)
    dot(d, 5.5, 6.0, 1.05, k)
    dot(d, 10.5, 6.0, 1.05, k)
    stroke_arc(d, (3.6, 3.4, 12.4, 12.2), 30, 150, 1.4, k)
    return finish(img, scale, "entry_emoticons%s.png" % ("@2x" if scale == 2 else ""))

# The microphone: a capsule, the cradle around its foot, the stem and the base.
def microphone(scale):
    img, k = canvas(scale); d = ImageDraw.Draw(img)
    d.rounded_rectangle([5.5 * k, 1.0 * k, 10.5 * k, 9.5 * k], radius=2.5 * k, fill=GREY + (255,))
    stroke_arc(d, (2.9, 1.9, 13.1, 12.1), 0, 180, 1.4, k)  # cradle: lower half of a circle
    line(d, [(8.0, 12.1), (8.0, 14.0)], 1.4, k)
    line(d, [(5.2, 14.3), (10.8, 14.3)], 1.4, k)
    round_cap(d, 5.2, 14.3, 1.4, k); round_cap(d, 10.8, 14.3, 1.4, k)
    return finish(img, scale, "entry_voice%s.png" % ("@2x" if scale == 2 else ""))

# The formula: a sigma, the one glyph that says mathematics at sixteen points.
def formula(scale):
    img, k = canvas(scale); d = ImageDraw.Draw(img)
    pts = [(12.3, 2.4), (3.9, 2.4), (8.6, 8.0), (3.9, 13.6), (12.3, 13.6)]
    line(d, pts, 1.6, k)
    for p in (pts[0], pts[-1]):
        round_cap(d, p[0], p[1], 1.6, k)
    # A small tick at both ends, as the serifs a printed sigma carries
    line(d, [(12.3, 2.4), (12.3, 4.0)], 1.6, k); round_cap(d, 12.3, 4.0, 1.6, k)
    line(d, [(12.3, 13.6), (12.3, 12.0)], 1.6, k); round_cap(d, 12.3, 12.0, 1.6, k)
    return finish(img, scale, "entry_formula%s.png" % ("@2x" if scale == 2 else ""))

ramp = " .:-=+*#%@"
for fn in (smiley, microphone, formula):
    for scale in (1, 2):
        im = fn(scale)
        if scale == 1:
            px = im.load()
            print(fn.__name__)
            for y in range(16):
                print("   " + "".join(ramp[min(9, px[x, y][3] * 10 // 256)] for x in range(16)))
