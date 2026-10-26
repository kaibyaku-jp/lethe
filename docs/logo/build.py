"""Builds the lethe logo SVGs with the wordmark outlined from Kalam.

Usage: python -I build.py <fonts dir> <output dir>

The fonts dir must hold Kalam-Bold.ttf and Kalam-Regular.ttf; see README.md.
"""

import sys
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

FONTS = Path(sys.argv[1])
OUT = Path(sys.argv[2])
OUT.mkdir(parents=True, exist_ok=True)

THEMES = {
    "light": {"ink": "#1E1E1E", "muted": "#5F6368", "river": "#2B6F8F"},
    # A lighter river, so the fainter waves still show on a dark background.
    "dark": {"ink": "#F2F0EA", "muted": "#A9AFB8", "river": "#5BA4C4"},
}

# The capital lambda of ΛΗΘΗ, drawn as one stroke.
LAMBDA = "M50 160 C 66 118, 84 76, 100 34 C 116 76, 134 118, 150 160"
# The waves that wash its feet away, top to bottom.
WAVES = [
    "M18 128 C 40 114, 60 142, 82 128 S 124 114, 146 128 S 172 142, 184 126",
    "M30 160 C 50 147, 70 173, 92 160 S 132 147, 154 160",
    "M58 186 C 74 176, 90 194, 108 186 S 136 178, 146 186",
]


def text_path(font_file, text, size, x, baseline):
    """Returns (svg path data, advance width) for text set at size."""
    font = TTFont(FONTS / font_file)
    glyph_set = font.getGlyphSet()
    cmap = font.getBestCmap()
    scale = size / font["head"].unitsPerEm
    pen = SVGPathPen(glyph_set)
    cursor = 0.0
    for char in text:
        name = cmap[ord(char)]
        # Font units are y-up; SVG is y-down.
        transform = (scale, 0, 0, -scale, x + cursor * scale, baseline)
        glyph_set[name].draw(TransformPen(pen, transform))
        cursor += font["hmtx"][name][0]
    return pen.getCommands(), cursor * scale


def mark(theme, simple=False):
    """The mark in a 200x200 box: Λ with its feet washed away by the river.

    The waves cut the letter through a mask rather than painting the
    background over it, so the mark sits on any background.
    """
    ink, river = theme["ink"], theme["river"]
    if simple:
        # For 16 to 48 px: a heavier letter and two waves.
        letter_width, waves = 20, [(WAVES[0], 13, 30, 1), (WAVES[1], 12, 28, 0.55)]
    else:
        letter_width, waves = 15, [(WAVES[0], 10, 22, 1), (WAVES[1], 9, 20, 0.6), (WAVES[2], 8, 0, 0.3)]
    cuts = "".join(
        f'<path d="{d}" stroke="#000" stroke-width="{cut}" stroke-linecap="round"/>' for d, _, cut, _ in waves if cut
    )
    defs = (
        '<mask id="wash" maskUnits="userSpaceOnUse" x="0" y="0" width="200" height="200">'
        f'<rect width="200" height="200" fill="#fff"/><g fill="none">{cuts}</g></mask>'
    )
    strokes = "".join(
        f'\n    <path d="{d}" stroke="{river}" stroke-width="{width}" stroke-linecap="round"'
        + (f' opacity="{opacity}"' if opacity < 1 else "")
        + "/>"
        for d, width, _, opacity in waves
    )
    body = f"""
    <path d="{LAMBDA}" fill="none" stroke="{ink}" stroke-width="{letter_width}" stroke-linecap="round" stroke-linejoin="round" mask="url(#wash)"/>
    <g fill="none">{strokes}
    </g>"""
    return defs, body


def svg(width, height, title, defs, body):
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width:.0f} {height:.0f}" width="{width:.0f}" height="{height:.0f}" role="img" aria-labelledby="title">
  <title id="title">{title}</title>
  <defs>{defs}</defs>{body}
</svg>
"""


def write(name, content):
    (OUT / name).write_text(content)
    print(name)


TITLE = "lethe — a time to keep, and a time to cast away."

for theme_name, theme in THEMES.items():
    suffix = "" if theme_name == "light" else "-dark"
    defs, body = mark(theme)
    write(f"lethe-mark{suffix}.svg", svg(200, 200, "lethe", defs, body))

    simple_defs, simple_body = mark(theme, simple=True)
    write(f"lethe-icon{suffix}.svg", svg(200, 200, "lethe", simple_defs, simple_body))

    # Horizontal: mark, then the wordmark centred on the mark's height.
    word, word_width = text_path("Kalam-Bold.ttf", "lethe", 120, 0, 0)
    width = 200 + 24 + word_width + 8
    body_h = f"{body}\n  <g transform=\"translate(224 132)\"><path d=\"{word}\" fill=\"{theme['ink']}\"/></g>"
    write(f"lethe-logo{suffix}.svg", svg(width, 200, TITLE, defs, body_h))

    # Vertical: mark, wordmark and tagline, centred.
    word, word_width = text_path("Kalam-Bold.ttf", "lethe", 112, 0, 0)
    tag, tag_width = text_path("Kalam-Regular.ttf", "a time to keep, and a time to cast away.", 30, 0, 0)
    width = max(word_width, tag_width) + 40
    mark_x = (width - 200) / 2
    body_v = (
        f"\n  <g transform=\"translate({mark_x:.1f} 0)\">{body}\n  </g>"
        f"\n  <g transform=\"translate({(width - word_width) / 2:.1f} 300)\"><path d=\"{word}\" fill=\"{theme['ink']}\"/></g>"
        f"\n  <g transform=\"translate({(width - tag_width) / 2:.1f} 354)\"><path d=\"{tag}\" fill=\"{theme['muted']}\"/></g>"
    )
    write(f"lethe-logo-vertical{suffix}.svg", svg(width, 376, TITLE, defs, body_v))
