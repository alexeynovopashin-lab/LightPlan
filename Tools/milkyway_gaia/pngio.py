"""PNG 16 бит (RGB или серый): запись и чтение на numpy и zlib.

Pillow не пишет 16-битный RGB и при чтении обрезает его до 8 бит, поэтому здесь свой кодек. Писатель выбирает
фильтр строки PNG из «нет / Sub / Up / Paeth» по наименьшей сумме модулей (обычная эвристика libpng); читатель
понимает все пять фильтров стандарта. Файл детерминирован: те же числа — те же байты.
"""
import struct
import zlib

import numpy as np

SIG = b"\x89PNG\r\n\x1a\n"


def _chunk(tag, data):
    c = struct.pack(">I", len(data)) + tag + data
    return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def _paeth_pred(a, b, c):
    p = a + b - c
    pa, pb, pc = np.abs(p - a), np.abs(p - b), np.abs(p - c)
    return np.where((pa <= pb) & (pa <= pc), a, np.where(pb <= pc, b, c))


def write_png16(path, img, filters=(0, 1, 2, 4), level=9):
    """img: uint16, форма (H, W, 3) или (H, W). Возвращает размер файла в байтах."""
    img = np.ascontiguousarray(img, dtype=">u2")
    h, w = img.shape[:2]
    ch = 1 if img.ndim == 2 else img.shape[2]
    ctype = {1: 0, 3: 2}[ch]
    bpp = 2 * ch
    raw = img.view(np.uint8).reshape(h, w * bpp).astype(np.int16)
    prev = np.zeros_like(raw)
    out = bytearray()
    for y in range(h):
        x = raw[y]
        up = prev[y - 1] if y else np.zeros_like(x)
        left = np.concatenate([np.zeros(bpp, np.int16), x[:-bpp]])
        ul = np.concatenate([np.zeros(bpp, np.int16), up[:-bpp]])
        cands = {0: x, 1: x - left, 2: x - up, 3: x - (left + up) // 2, 4: x - _paeth_pred(left, up, ul)}
        best, best_cost = None, None
        for f in filters:
            v = (cands[f] & 0xFF).astype(np.uint8)
            cost = int(np.abs(v.astype(np.int8).astype(np.int32)).sum())
            if best_cost is None or cost < best_cost:
                best, best_cost = (f, v), cost
        out.append(best[0])
        out += best[1].tobytes()
        prev[y] = x
    data = SIG + _chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 16, ctype, 0, 0, 0))
    data += _chunk(b"IDAT", zlib.compress(bytes(out), level))
    data += _chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(data)
    return len(data)


def read_png16(path):
    """Чтение PNG 16 бит RGB / серый без чересстрочности; возвращает uint16 (H, W, 3) или (H, W)."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != SIG:
        raise ValueError(f"{path}: не PNG")
    pos, idat, hdr = 8, bytearray(), None
    while pos < len(data):
        n, tag = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        if tag == b"IHDR":
            hdr = struct.unpack(">IIBBBBB", body)
        elif tag == b"IDAT":
            idat += body
        elif tag == b"IEND":
            break
        pos += 12 + n
    w, h, depth, ctype, _, _, interlace = hdr
    if depth != 16 or ctype not in (0, 2) or interlace:
        raise ValueError(f"{path}: нужен 16-битный RGB или серый без чересстрочности (глубина {depth}, тип {ctype})")
    ch = 3 if ctype == 2 else 1
    bpp = 2 * ch
    stride = w * bpp
    buf = np.frombuffer(zlib.decompress(bytes(idat)), np.uint8).reshape(h, stride + 1)
    out = np.zeros((h, stride), np.uint8)
    prev = np.zeros(stride, np.int32)
    for y in range(h):
        f, x = buf[y, 0], buf[y, 1:].astype(np.int32)
        if f == 0:
            r = x
        elif f == 1:            # Sub: накопленная сумма с шагом bpp
            r = np.cumsum(x.reshape(w, bpp), axis=0).reshape(-1) & 0xFF
        elif f == 2:
            r = (x + prev) & 0xFF
        elif f in (3, 4):       # Average и Paeth зависят от левого соседа — по пикселям
            r = np.zeros(stride, np.int32)
            for i in range(0, stride, bpp):
                a = r[i - bpp:i] if i else np.zeros(bpp, np.int32)
                b = prev[i:i + bpp]
                if f == 3:
                    r[i:i + bpp] = (x[i:i + bpp] + (a + b) // 2) & 0xFF
                else:
                    c = prev[i - bpp:i] if i else np.zeros(bpp, np.int32)
                    r[i:i + bpp] = (x[i:i + bpp] + _paeth_pred(a, b, c)) & 0xFF
        else:
            raise ValueError(f"{path}: фильтр строки {f}")
        out[y] = r
        prev = r.astype(np.int32)
    img = out.view(">u2").astype(np.uint16)
    return img.reshape(h, w, ch) if ch == 3 else img.reshape(h, w)
