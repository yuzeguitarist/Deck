#!/usr/bin/env python3
"""Extract ASCII art from HTML and generate a raw ANSI text file for include_str!.

Quantizes similar colors to reduce escape code overhead.
"""

import re
import sys
from pathlib import Path

html_path = Path(__file__).parent.parent / "ascii-art.html"
out_path = Path(__file__).parent.parent / "deckclip" / "src" / "logo.ans"

html = html_path.read_text()

pre_match = re.search(r'<pre>(.*?)</pre>', html, re.DOTALL)
if not pre_match:
    print("No <pre> found", file=sys.stderr)
    sys.exit(1)

pre_content = pre_match.group(1)
lines_raw = pre_content.split('\n')

STEP = 16

def quantize(r, g, b):
    return (min(255, round(r / STEP) * STEP),
            min(255, round(g / STEP) * STEP),
            min(255, round(b / STEP) * STEP))

output_lines = []

for line_html in lines_raw:
    if not line_html.strip():
        continue
    spans = re.findall(
        r'<span\s+style="color:rgb\((\d+),(\d+),(\d+)\)">(.*?)</span>',
        line_html
    )
    if not spans:
        continue
    
    prev_rgb = None
    buf = ""
    parts = []
    
    for r_str, g_str, b_str, char_html in spans:
        r, g, b = int(r_str), int(g_str), int(b_str)
        ch = char_html.replace('&nbsp;', ' ').replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>')
        qrgb = quantize(r, g, b)
        
        if qrgb == prev_rgb:
            buf += ch
        else:
            if buf and prev_rgb is not None:
                pr, pg, pb = prev_rgb
                parts.append(f"\033[38;2;{pr};{pg};{pb}m{buf}")
            buf = ch
            prev_rgb = qrgb
    
    if buf and prev_rgb is not None:
        pr, pg, pb = prev_rgb
        parts.append(f"\033[38;2;{pr};{pg};{pb}m{buf}")
    
    output_lines.append("".join(parts) + "\033[0m")

result = "\n".join(output_lines) + "\n"
out_path.write_text(result)
print(f"Written {len(result)} bytes to {out_path}")
print(f"Lines: {len(output_lines)}")
