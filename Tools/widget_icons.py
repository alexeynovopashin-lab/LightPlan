#!/usr/bin/env python3
"""Знаки точек для расширения виджета (30б.2в-2).

Расширение `LightPlanUI` не линкует (модуль огромный, память виджета мала), а знак точки ему нужен. Приложение подбирает знак
по названию (`PointSign.name`) и кладёт его имя в `widget.json`; здесь из библиотеки приложения вынимается ровно то, что
может прийти по этим именам, — каждый знак СТРОКА В СТРОКУ, как лежит в `IconLibrary.generated.swift`, — и пишется
`LightPlanWidget/Views/WidgetIcons.generated.swift`. Руками не править; разбор строк знака — `WidgetIcon.swift`, его
сверяет с `IconArt` тест `WidgetIconTests` (расхождение путей = красный).

  python3 Tools/widget_icons.py          записать
  python3 Tools/widget_icons.py --check  сравнить с лежащим (расхождение — код выхода 1)
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Packages/LightPlanUI/Sources/LightPlanUI/Icons/IconLibrary.generated.swift"
OUT = ROOT / "LightPlanWidget/Views/WidgetIcons.generated.swift"
# Кроме знаков точек виды рисуют солнце (рассвет, золотой час, закат, круг блокировки) и запасной «кружок».
EXTRA = ["dot", "studio", "sun", "sunrise", "sunset", "golden"]
# Знак оценки заката «закат с отражением» (30б.2в-5): есть на `wt/icons-golden`, в библиотеке главной ветки его ещё нет. Берётся, когда появится
# (виды спрашивают `WidgetIconTable.common["sunset_glow"]` и пока рисуют «закат»); нет в библиотеке — не ошибка.
EXTRA_IF_PRESENT = ["sunset_glow"]


def build() -> str:
    text = SRC.read_text()
    common = text[text.index("static let common"):text.index("static let genres")]
    lines = {m.group(1): m.group(0) for m in re.finditer(r'^        "([a-z0-9_]+)": .*$', common, re.M)}
    words = text[text.index("static let pointWords"):]
    signs = set(re.findall(r'", "([a-z0-9_]+)", \d+\),$', words, re.M)) | set(EXTRA) | {n for n in EXTRA_IF_PRESENT if n in lines}
    # Как `PointSign.pick`: правило, чей знак не нарисован, пропускается; здесь тоже берём только нарисованные.
    wanted = sorted(s for s in signs if s in lines)
    missing = sorted(s for s in EXTRA if s not in lines)
    if missing:
        sys.exit("нет знаков в библиотеке: " + ", ".join(missing))
    body = "\n".join(lines[n] for n in wanted)
    # Знаки жанров — шапка среднего и малого вида (30б.2в-4): все, что есть в библиотеке, как лежат.
    genres_text = text[text.index("static let genres"):text.index("static let wishes")]
    genres = [m.group(0) for m in re.finditer(r'^        "([a-z0-9_]+)": .*$', genres_text, re.M)]
    if not genres:
        sys.exit("нет знаков жанров в библиотеке")
    genre_body = "\n".join(genres)
    return (
        "// GENERATED — не править руками.\n"
        "// Собрано `Tools/widget_icons.py` из `Packages/LightPlanUI/Sources/LightPlanUI/Icons/IconLibrary.generated.swift`.\n"
        "// Пересобрать: `python3 Tools/widget_icons.py`. Строки знаков — те же, что в приложении (формат — там же).\n"
        f"// Знаков: {len(wanted)} из {len(lines)} (все, что может назвать `PointSign`, и знаки света); жанров: {len(genres)}.\n\n"
        "enum WidgetIconTable {\n"
        "    static let common: [String: String] = [\n"
        f"{body}\n"
        "    ]\n"
        "    /// Знаки жанров съёмки (`Icon(genre:)` приложения): знак в шапке рядом с именами клиентов.\n"
        "    static let genres: [String: String] = [\n"
        f"{genre_body}\n"
        "    ]\n"
        "}\n"
    )


if __name__ == "__main__":
    new = build()
    if "--check" in sys.argv:
        sys.exit(0 if OUT.exists() and OUT.read_text() == new else 1)
    OUT.write_text(new)
    print(f"{OUT.relative_to(ROOT)}: {len(new) // 1024} КБ")
