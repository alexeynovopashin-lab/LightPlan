"""PNG без сторонних библиотек: 16 бит (серый и RGB) и 8 бит, запись и чтение (только numpy и zlib).

Pillow не пишет 16-битный RGB, а карте свечения он нужен. Фильтр строки — None, Sub или Up, тот, у которого
меньше сумма модулей (эвристика libpng); Average и Paeth не берём, чтобы чтение оставалось векторным. Сжатие
zlib 9. Читатель понимает только то, что пишет писатель (фильтры 0–2, без чересстрочности).
"""
import struct
import zlib

import numpy as np

_SIG = b'\x89PNG\r\n\x1a\n'


def _chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)


def _filter(raw, bpp):
    """raw: (h, stride) uint8 → байты IDAT до сжатия, фильтр выбран на каждую строку."""
    h, stride = raw.shape
    up = np.vstack([np.zeros((1, stride), np.uint8), raw[:-1]])
    left = np.hstack([np.zeros((h, bpp), np.uint8), raw[:, :-bpp]])
    cands = [raw, raw - left, raw - up]
    cost = np.stack([np.abs(c.astype(np.int8).astype(np.int32)).sum(axis=1) for c in cands])
    best = cost.argmin(axis=0)
    out = np.empty((h, stride + 1), np.uint8)
    out[:, 0] = best
    for k, c in enumerate(cands):
        rows = best == k
        out[rows, 1:] = c[rows]
    return out.tobytes()


def write(path, img, bits=16):
    """img: (h, w) или (h, w, 3) uint16 (bits=16) / uint8 (bits=8)."""
    img = np.ascontiguousarray(img)
    h, w = img.shape[:2]
    ch = 1 if img.ndim == 2 else img.shape[2]
    color = {1: 0, 3: 2}[ch]
    if bits == 16:
        raw = img.astype('>u2').view(np.uint8).reshape(h, w * ch * 2)
    else:
        raw = img.astype(np.uint8).reshape(h, w * ch)
    bpp = ch * bits // 8
    ihdr = struct.pack('>IIBBBBB', w, h, bits, color, 0, 0, 0)
    data = _SIG + _chunk(b'IHDR', ihdr) + _chunk(b'IDAT', zlib.compress(_filter(raw, bpp), 9)) + _chunk(b'IEND', b'')
    with open(path, 'wb') as f:
        f.write(data)


def read(path):
    """→ (h, w[, 3]) uint16 или uint8 — как записано."""
    with open(path, 'rb') as f:
        data = f.read()
    assert data[:8] == _SIG, path
    pos, idat, hdr = 8, b'', None
    while pos < len(data):
        n, kind = struct.unpack('>I4s', data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        if kind == b'IHDR':
            hdr = struct.unpack('>IIBBBBB', body)
        elif kind == b'IDAT':
            idat += body
        pos += 12 + n
    w, h, bits, color, _, _, interlace = hdr
    assert interlace == 0 and color in (0, 2) and bits in (8, 16), hdr
    ch = 1 if color == 0 else 3
    bpp = ch * bits // 8
    stride = w * bpp
    buf = np.frombuffer(zlib.decompress(idat), np.uint8).reshape(h, stride + 1)
    out = np.zeros((h, stride), np.uint8)
    prev = np.zeros(stride, np.int64)
    for y in range(h):
        ft, line = buf[y, 0], buf[y, 1:].astype(np.int64)
        assert ft in (0, 1, 2), ft
        if ft == 1:                                # Sub: накопленная сумма по каждому байту пикселя
            line = np.cumsum(line.reshape(w, bpp), axis=0).ravel()
        elif ft == 2:
            line = line + prev
        cur = line & 255
        out[y] = cur
        prev = cur
    if bits == 16:
        img = out.view('>u2').astype(np.uint16)
    else:
        img = out
    return img.reshape(h, w, ch) if ch == 3 else img.reshape(h, w)
