#!/usr/bin/env python3
"""Set OverlayAppEnable 0 for app 730 in a Steam localconfig.vdf. Run with Steam stopped."""
import re
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
m = re.search(r'\n(\t+)"apps"\n\t+\{\n', text)
if not m:
    sys.exit(f"no apps section in {path}")
indent = m.group(1) + "\t"
block = re.compile(r'(\n' + indent + r'"730"\n' + indent + r'\{\n)')
entry = indent + '\t"OverlayAppEnable"\t\t"0"\n'
if re.search(r'"730"\n' + indent + r'\{\n(?:' + indent + r'\t[^\n]*\n)*?' + re.escape(entry), text):
    print("overlay already disabled")
elif block.search(text[m.end():]):
    start = m.end()
    text = text[:start] + block.sub(lambda b: b.group(1) + entry, text[start:], count=1)
    open(path, "w", encoding="utf-8").write(text)
    print("overlay disabled for CS2")
else:
    start = m.end()
    text = text[:start] + f'{indent}"730"\n{indent}{{\n{entry}{indent}}}\n' + text[start:]
    open(path, "w", encoding="utf-8").write(text)
    print("overlay disabled for CS2")
