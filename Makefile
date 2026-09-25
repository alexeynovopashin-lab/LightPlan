# Стенд паритета JS ↔ Swift. Подробности — Tools/parity/README.md.
#
# Часовой пояс прибит к UTC намеренно: computeSun берёт номер дня через
# локальный new Date(y, 0, 0), и в поясе с переводом часов фикстуры зависели бы
# от машины, на которой их сгенерировали.

SHELL := /bin/bash
FIXTURES := Fixtures

.PHONY: help parity blocks lang icons domain shots mapstyle mapref planner tapspot rotor sims glass

help:
	@echo "make parity   пересобрать фикстуры в $(FIXTURES)/ и доказать, что прогон повторяем"
	@echo "make blocks   показать, что вырезается из беты (дешёвая проверка якорей)"
	@echo "make lang     пересобрать каталог строк и фикстуры текста, доказать повторяемость"
	@echo "make icons    пересобрать знаки Swift из beta/icons.js, эталон Chromium и доказать, что прогон повторяем"
	@echo "make domain   пересобрать эталон таблиц и правил съёмки (итерация 11) и доказать повторяемость"
	@echo "make mapstyle описание холста карты из beta/mapstyle.js (итерация 20а)"
	@echo "make mapref   эталон сцены прибора карты из живой беты и доказать повторяемость (итерация 20а, ~3 мин)"
	@echo "make planner  эталон колонок ленты дня и шкалы срочности из беты и доказать повторяемость (итерация 21)"
	@echo "make tapspot тап по булавке на живом холсте MapLibre и MapKit открывает полосу имени (20е, нужна сеть, ~1 мин)"
	@echo "make rotor    ротор «Карты» под подставным компасом: восемь углов, клина пустоты нет (21а, ~1 мин)"
	@echo "make sims     симулятор этой ветки; ARGS=--prune удаляет симуляторы веток, которых нет (21а)"
	@echo "make glass    стекло без подделки: ни системного материала, ни нарисованного блика вне Timebar/ (20д; идёт и фазой сборки)"
	@echo "make shots    пары снимков веб / натив «Света», «Карты», «Съёмок» и «Настроек» и сверка числами (19б, 20а, 21)"

# Файлы, которые пишет сам generate.js. Другие цели (lang, domain, локация)
# кладут в Fixtures/ свои файлы рядом — их сюда не включаем, иначе diff -r
# всей папки сравнивает generate.js с чужими файлами и всегда «расходится».
PARITY_FILES := solar_day.json solar_sample.json light_state.json \
	sunset_score.json moon.json eclipse.json sky_windows.json \
	merge_pairs.json milkyway.json astro_night.json mock_weather.json \
	weather_day.json mwsky.json mw_dust.json glow.json

parity:
	@TZ=UTC node Tools/parity/generate.js --out $(FIXTURES)
	@tmp=$$(mktemp -d); \
	TZ=UTC node Tools/parity/generate.js --out $$tmp --quiet; \
	fail=0; \
	for f in $(PARITY_FILES); do \
		cmp -s $(FIXTURES)/$$f $$tmp/$$f || { echo "  РАСХОДИТСЯ: $$f"; fail=1; }; \
	done; \
	if [ $$fail -eq 0 ]; then \
		echo "  повторный прогон: побайтово то же"; \
		rm -rf $$tmp; \
	else \
		echo "  ПОВТОРНЫЙ ПРОГОН РАЗОШЁЛСЯ — стенду нельзя верить"; \
		rm -rf $$tmp; exit 1; \
	fi

blocks:
	@node Tools/parity/extract.js

# Итерация 14: словарь и форматы. Каталог — из lang.js, фикстуры — из lang.js и
# слоя дат беты. TZ=UTC по той же причине, что у parity: даты берутся местными.
lang:
	@node Tools/lang2xcstrings.js
	@TZ=UTC node Tools/parity/lang.js --out $(FIXTURES)
	@tmp=$$(mktemp -d); \
	TZ=UTC node Tools/parity/lang.js --out $$tmp --quiet; \
	if cmp -s $(FIXTURES)/lang.json $$tmp/lang.json && cmp -s $(FIXTURES)/format.json $$tmp/format.json; then \
		echo "  повторный прогон: побайтово то же"; rm -rf $$tmp; \
	else \
		echo "  ПОВТОРНЫЙ ПРОГОН РАЗОШЁЛСЯ — эталону нельзя верить"; rm -rf $$tmp; exit 1; \
	fi
	@node Tools/lang2xcstrings.js --check

# Знаки: генератор пишет Swift и корпус подбора, отдельный скрипт — эталонный лист
# Chromium. Из worktree: LIGHT_PLAN_WEB=<путь к Light_Plan>, если папка не рядом.
icons:
	@node Tools/icons2assets.js
	@node Tools/icons_ref.js
	@node Tools/icons2assets.js --check

# Итерация 11: домен. Таблицы и правила съёмки режутся из беты своим скриптом и
# своим отпечатком — общий стенд неба не трогается. TZ=UTC по той же причине,
# что у parity: дни записей — местные полуночи.
domain:
	@TZ=UTC node Tools/parity/domain.js --out $(FIXTURES)
	@tmp=$$(mktemp -d); \
	TZ=UTC node Tools/parity/domain.js --out $$tmp --quiet; \
	if cmp -s $(FIXTURES)/domain.json $$tmp/domain.json; then \
		echo "  повторный прогон: побайтово то же"; rm -rf $$tmp; \
	else \
		echo "  ПОВТОРНЫЙ ПРОГОН РАЗОШЁЛСЯ — эталону нельзя верить"; rm -rf $$tmp; exit 1; \
	fi

# Итерация 21: колонки ленты дня и шкала срочности сдачи — из беты.
planner:
	@node Tools/parity/planner.js --out $(FIXTURES)
	@tmp=$$(mktemp -d); \
	node Tools/parity/planner.js --out $$tmp --quiet; \
	if cmp -s $(FIXTURES)/planner.json $$tmp/planner.json; then \
		echo "  повторный прогон: побайтово то же"; rm -rf $$tmp; \
	else \
		echo "  ПОВТОРНЫЙ ПРОГОН РАЗОШЁЛСЯ — эталону нельзя верить"; rm -rf $$tmp; exit 1; \
	fi

# Итерация 19б: пары снимков веб / натив на симуляторе iPhone 17 Pro Max
# (с 21а — на своём симуляторе ветки той же модели).
# Параметры сверх умолчаний — прямо скрипту: node Tools/shots/pair.js --help
# в шапке файла. Из worktree: LIGHT_PLAN_WEB=<путь к Light_Plan>.
shots:
	@node Tools/shots/pair.js $(ARGS)

mapstyle:
	@node Tools/mapstyle.js && node Tools/mapstyle.js --check

# Разметка #mapLight беты на входах пар снимков — эталон MapSceneParityTests.
mapref:
	@node Tools/map_ref.js && node Tools/map_ref.js --check

# Итерация 20е: тап по булавке на живой карте (сеть), оба холста. Другой
# симулятор — LP_SIM=<имя>.
tapspot:
	@node Tools/tap_spot.js $(ARGS)

# Итерация 21а: у каждой ветки свой симулятор (`LP <ветка>`, Tools/sim.js) —
# им пользуются shots, tapspot, rotor. Ротор под подставным компасом.
rotor:
	@node Tools/rotor.js $(ARGS)

sims:
	@node Tools/sim.js $(ARGS)

# Итерация 20д: там, где у веба имитация стекла, — только встроенное стекло.
glass:
	@Tools/check_glass.sh
