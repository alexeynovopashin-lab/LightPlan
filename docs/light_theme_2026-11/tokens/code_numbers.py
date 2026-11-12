#!/usr/bin/env python3
"""28к.3: числа светлых токенов (*из кода, не мерено*): было (main d468b34) и стало. Печатает markdown-таблицу.

    python3 code_numbers.py
"""
W = 0xFFFFFF


def lin(c):
    c /= 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rgb(h):
    return ((h >> 16) & 255, (h >> 8) & 255, h & 255) if isinstance(h, int) else h


def Y(h):
    r, g, b = rgb(h)
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def L(h):
    y = Y(h)
    f = y ** (1 / 3) if y > 0.008856 else 7.787 * y + 16 / 116
    return 116 * f - 16


def cr(a, b):
    ya, yb = Y(a), Y(b)
    return (max(ya, yb) + 0.05) / (min(ya, yb) + 0.05)


def over(fg, a, bg):
    return tuple(round(f * a + b * (1 - a)) for f, b in zip(rgb(fg), rgb(bg)))


def dl(a, b):
    return L(a) - L(b)


f2 = lambda x: f"{x:.2f}".replace(".", ",")
f1 = lambda x: f"{x:+.1f}".replace(".", ",")

WAS = dict(surface=0xFAF8F3, bg=0xEDE9E1, sheet=W, sheet2=0xF1EDE4, sheet4=(W, 1), segOn=0xDDD6C8, ink=0x17150F,
           ink5=0x857E70, ink6=0x8C8578, ink7=0x9A9385, brass=0xA9721F, ink_text=0xA9721F, onBrass=W, pressBrass=0xF7E9CF,
           trough=W, fillOn=0xA9721F)
NOW = dict(surface=0xEDEDF0, bg=0xE3E3E7, sheet=W, sheet2=0xF6F6F8, sheet4=(W, 0.72), segOn=W, ink=0x141416,
           ink5=0x69696E, ink6=0x69696E, ink7=0x86868B, brass=0xE4570B, ink_text=0xB83C00, onBrass=0x141416,
           pressBrass=0xFFE7D9, trough=0xE3E3E7, fillOn=0xE4570B)


def row(name, v):
    s = v["surface"]
    s4 = v["sheet4"]
    s4c = over(s4[0], s4[1], s) if s4[1] != 1 else rgb(s4[0])
    return [name, f"#{s:06X}", f"{f2(cr(v['sheet'], s))} / {f1(dl(v['sheet'], s))}", f"{f2(cr(s4c, s))} / {f1(dl(s4c, s))}",
            f"{f2(cr(v['sheet2'], s))} / {f1(dl(v['sheet2'], s))}", f2(cr(v["ink"], s)),
            f"{f2(cr(v['ink6'], v['sheet']))} / {f2(cr(v['ink6'], s))}", f2(cr(v["ink7"], s)),
            f"{f2(cr(v['ink_text'], v['sheet']))} / {f2(cr(v['ink_text'], s))} / {f2(cr(v['ink_text'], v['pressBrass']))}",
            f"{f2(cr(v['brass'], v['sheet']))} / {f2(cr(v['brass'], s))}",
            f"{f2(cr(W, v['fillOn']))} → {f2(cr(v['onBrass'], v['fillOn']))}",
            f"{f2(cr(v['segOn'], v['trough']))} / {f1(dl(v['segOn'], v['trough']))}"]


if __name__ == "__main__":
    head = ["", "фон страницы", "белая плашка / фон (отн. / ΔL*)", "плашка «Съёмок» / фон", "лист карточки / фон", "текст / фон",
            "пояснения на белом / на фоне", "подписи разделов / фон", "оранжевый ТЕКСТ: белое / фон / пилюля",
            "яркий оранжевый (знак): белое / фон", "надпись на оранжевой заливке: белое → чернила", "выбранный сегмент / жёлоб"]
    print("| " + " | ".join(head) + " |\n|" + "---|" * len(head))
    for n, v in (("было", WAS), ("стало", NOW)):
        print("| " + " | ".join(row(n, v)) + " |")
