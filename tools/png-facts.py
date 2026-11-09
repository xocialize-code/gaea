#!/usr/bin/env python3
"""Checks a PNG without any image library: its size, its text (tEXt/iTXt chunks, or the XMP ImageIO writes:
exif:UserComment as the comment, dc:rights as the copyright), and its alpha at the corners and the centre (8-bit RGBA,
every PNG filter). Exits non-zero, printing why, when a check fails.

  png-facts.py <png> [--size N] [--comment TEXT] [--copyright TEXT] [--transparent-corners] [--opaque-centre]
"""
import re, struct, sys, zlib

args = sys.argv[1:]
path = args.pop(0)
def opt(name):
    if name in args:
        i = args.index(name); v = args[i + 1]; del args[i:i + 2]; return v
def flag(name):
    if name in args: args.remove(name); return True
    return False
size, comment, copyright = opt('--size'), opt('--comment'), opt('--copyright')
corners, centre = flag('--transparent-corners'), flag('--opaque-centre')

d = open(path, 'rb').read()
assert d[:8] == b'\x89PNG\r\n\x1a\n', 'not a PNG'
i, texts, idat, ihdr = 8, {}, b'', None
while i < len(d):
    n, t = struct.unpack('>I4s', d[i:i + 8]); body = d[i + 8:i + 8 + n]; i += 12 + n
    if t == b'IHDR': ihdr = struct.unpack('>IIBBBBB', body)
    elif t == b'IDAT': idat += body
    elif t == b'tEXt':
        k, _, v = body.partition(b'\0'); texts[k.decode()] = v.decode('latin-1')
    elif t == b'iTXt':
        k, _, rest = body.partition(b'\0'); flag_, method = rest[0], rest[1]; rest = rest[2:]
        _, _, rest = rest.partition(b'\0'); _, _, v = rest.partition(b'\0')
        texts[k.decode()] = (zlib.decompress(v) if flag_ else v).decode('utf-8')
w, h, depth, ctype = ihdr[0], ihdr[1], ihdr[2], ihdr[3]
xmp = texts.get('XML:com.adobe.xmp', '')
def xmp_field(tag):
    m = re.search(r'<%s>.*?<rdf:li[^>]*>(.*?)</rdf:li>' % tag, xmp, re.S); return m.group(1) if m else ''
found_comment = texts.get('Comment', '') + ' ' + xmp_field('exif:UserComment')
found_copyright = texts.get('Copyright', '') + ' ' + xmp_field('dc:rights')
print(f'{w}x{h} depth {depth} colour type {ctype}; comment {found_comment.strip()!r}; copyright {found_copyright.strip()!r}')
ok = True
if size and (w, h) != (int(size), int(size)): print(f'size {w}x{h}, want {size}'); ok = False
if comment and comment not in found_comment: print('comment missing'); ok = False
if copyright and copyright not in found_copyright: print('copyright missing'); ok = False
if corners or centre:
    assert depth == 8 and ctype == 6, 'alpha checks need 8-bit RGBA'
    raw, bpp, stride = zlib.decompress(idat), 4, w * 4
    rows, prev, p = [], bytearray(stride), 0
    for _ in range(h):
        f = raw[p]; line = bytearray(raw[p + 1:p + 1 + stride]); p += 1 + stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0; b = prev[x]; c = prev[x - bpp] if x >= bpp else 0
            if f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + b) & 255
            elif f == 3: line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(line); prev = line
    alpha = lambda x, y: rows[y][x * 4 + 3]
    cs = [alpha(1, 1), alpha(w - 2, 1), alpha(1, h - 2), alpha(w - 2, h - 2)]
    print('corner alpha', cs, 'centre alpha', alpha(w // 2, h // 2))
    if corners and any(cs): print('a corner isn\'t transparent'); ok = False
    if centre and alpha(w // 2, h // 2) < 200: print('the centre isn\'t opaque'); ok = False
sys.exit(0 if ok else 1)
