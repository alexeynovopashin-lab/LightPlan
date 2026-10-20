# Стенд паритета JS ↔ Swift. Подробности — Tools/parity/README.md.
#
# Часовой пояс прибит к UTC намеренно: computeSun берёт номер дня через
# локальный new Date(y, 0, 0), и в поясе с переводом часов фикстуры зависели бы
# от машины, на которой их сгенерировали.

SHELL := /bin/bash
FIXTURES := Fixtures

.PHONY: phone checkstep help parity blocks lang icons brightstars milkywaygaia mwdata domain shots mapstyle mapref planner year tapspot pinch rotor sims glass lightfit

help:
	@echo "make parity   пересобрать фикстуры в $(FIXTURES)/ и доказать, что прогон повторяем"
	@echo "make blocks   показать, что вырезается из беты (дешёвая проверка якорей)"
	@echo "make lang     пересобрать каталог строк и фикстуры текста, доказать повторяемость"
	@echo "make icons    пересобрать знаки Swift из beta/icons.js, эталон Chromium и доказать, что прогон повторяем"
	@echo "make brightstars яркие звёзды AR (V ≤ 2,5): JSON из снимков каталогов, Swift из JSON, проверка числами; без сети (снимки — node Tools/bright_stars/fetch.js)"
	@echo "make milkywaygaia Млечный Путь из Gaia DR3: звёзды G ≤ 10 + карта свечения, картинки, проверка числами и повтор прогона; без сети, если есть сырой кэш (python3 Tools/milkyway_gaia/fetch.py, ~15 мин)"
	@echo "make mwdata   данные Gaia (звёзды, карта свечения, spec.json) в ресурсы приложения без правки, сверка побайтно (29.8в.19)"
	@echo "make domain   пересобрать эталон таблиц и правил съёмки (итерация 11) и доказать повторяемость"
	@echo "make mapstyle описание холста карты из beta/mapstyle.js (итерация 20а)"
	@echo "make mapref   эталон сцены прибора карты из живой беты и доказать повторяемость (итерация 20а, ~3 мин)"
	@echo "make planner  эталон колонок ленты дня и шкалы срочности из беты и доказать повторяемость (итерация 21)"
	@echo "make year     эталон прибыли года по валютам и основы слова поиска из беты (итерация 22)"
	@echo "make tapspot тап по булавке на живом холсте MapLibre и MapKit открывает полосу имени (20е, нужна сеть, ~1 мин)"
	@echo "make pinch    пять щипков на живом холсте MapLibre: уровень держится, центр не прыгает назад (21б, нужна сеть, ~1 мин)"
	@echo "make rotor    ротор «Карты» под подставным компасом: восемь углов, клина пустоты нет (21а, ~1 мин)"
	@echo "make sims     симулятор этой ветки; ARGS=--prune удаляет симуляторы веток, которых нет, ARGS=--help — справка (21а)"
	@echo "make glass    стекло без подделки: ни системного материала, ни нарисованного блика вне Timebar/ (20д; идёт и фазой сборки)"
	@echo "make phone    сборка на iPhone Алексея: ARGS=\"install\" | \"uninstall\" | \"list\"; ветка ставит «LP <ветка>» в один из четырёх слотов slotA…D (26т, пул 12.10)"
	@echo "make checkstep ветка шага против базы: пять строк да/нет, любое «нет» — код 1; ARGS=\"wt/26 [main] --type код [--tests] [--full]\" (26т)"
	@echo "make draftday  форма при черновике другого дня: окно вопроса, плашка, порядок блоков, числа (28о)"
	@echo "make shots    пары снимков веб / натив «Света», «Карты», «Съёмок» и «Настроек» и сверка числами (19б, 20а, 21)"

# Файлы, которые пишет сам generate.js. Другие цели (lang, domain, локация)
# кладут в Fixtures/ свои файлы рядом — их сюда не включаем, иначе diff -r
# всей папки сравнивает generate.js с чужими файлами и всегда «расходится».
PARITY_FILES := solar_day.json solar_sample.json light_state.json \
	sunset_score.json moon.json eclipse.json sky_windows.json \
	merge_pairs.json milkyway.json astro_night.json mock_weather.json \
	weather_day.json mwsky.json mw_dust.json glow.json window_light.json \
	constellations.json

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

# Яркие звёзды для слоя звёзд AR. Сеть нужна только fetch.js (снимки в
# Tools/bright_stars/sources/); здесь — сборка и проверка по снимкам.
brightstars:
	@node Tools/bright_stars/build.js
	@node Tools/bright_stars/gen_swift.js
	@node Tools/bright_stars/check.js

# Млечный Путь из каталога Gaia DR3 (Tools/milkyway_gaia/README.md): звёзды G ≤ 10 и карта свечения G 10…21.
# Сети не нужно, если сырой кэш лежит в Tools/milkyway_gaia/raw/ (его качает fetch.py; в .gitignore).
# Второй прогон build.py во временную папку доказывает, что файлы повторяются побайтно.
milkywaygaia:
	@python3 Tools/milkyway_gaia/build.py
	@python3 Tools/milkyway_gaia/preview.py
	@tmp=$$(mktemp -d); \
	python3 Tools/milkyway_gaia/build.py --out $$tmp > /dev/null; \
	python3 Tools/milkyway_gaia/validate.py --repeat $$tmp; s=$$?; rm -rf $$tmp; exit $$s


# Шаг 29.8в.19: данные Gaia в приложение — три файла из Tools/milkyway_gaia/ без правки в ресурсы пакета UI
# (`MilkyWayData/`, копируются как есть, без обработки PNG). Сверка побайтно. Лицензия CC BY-NC 3.0 IGO —
# Packages/LightPlanUI/Sources/LightPlanUI/MilkyWayData/README.md.
mwdata:
	@d=Packages/LightPlanUI/Sources/LightPlanUI/MilkyWayData; \
	for f in stars_gaia.bin milkyway_glow_gaia.png spec.json; do \
	  cp Tools/milkyway_gaia/$$f $$d/$$f && cmp -s Tools/milkyway_gaia/$$f $$d/$$f || { echo "mwdata: $$f не совпал"; exit 1; }; \
	done; echo "mwdata: 3 файла в $$d, побайтно как в Tools/milkyway_gaia"

# Итерация 11: домен. Таблицы и правила съёмки режутся из беты своим скриптом и
# своим отпечатком — общий стенд неба не трогается. TZ=UTC по той же причине,
# что у parity: дни записей — местные полуночи.
tel:
	@node Tools/parity/tel.js --out $(FIXTURES)

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

# Итерация 22: прибыль года по валютам и основа слова поиска — код веба над
# записями посева сезона и их копиями в разных валютах.
year:
	@node Tools/parity/year.js --out $(FIXTURES)
	@tmp=$$(mktemp -d); \
	node Tools/parity/year.js --out $$tmp --quiet; \
	if cmp -s $(FIXTURES)/year.json $$tmp/year.json; then \
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

# 28о: форма при черновике другого дня — окно вопроса, плашка с датой, порядок блоков (только натив, iPhone 17 Pro).
draftday:
	@node Tools/shots/draft_day.js $(ARGS)

mapstyle:
	@node Tools/mapstyle.js && node Tools/mapstyle.js --check

# Разметка #mapLight беты на входах пар снимков — эталон MapSceneParityTests.
mapref:
	@node Tools/map_ref.js && node Tools/map_ref.js --check

# Итерация 20е: тап по булавке на живой карте (сеть), оба холста. Другой
# симулятор — LP_SIM=<имя>.
tapspot:
	@node Tools/tap_spot.js $(ARGS)

# Итерация 21б: щипок на живом холсте MapLibre — уровень держится.
pinch:
	@node Tools/pinch.js $(ARGS)

# Итерация 21а: у каждой ветки свой симулятор (`LP <ветка>`, Tools/sim.js) —
# им пользуются shots, tapspot, rotor. Ротор под подставным компасом.
rotor:
	@node Tools/rotor.js $(ARGS)

# 29.2г, 29.2г-3: «Подробно» на «Свете» — зазор кнопка/панель (измерение) и место раскрытого списка под кнопкой, по моделям iPhone.
lightfit:
	@node Tools/light_fit.js $(ARGS)

sims:
	@node Tools/sim.js $(ARGS)

# Итерация 29.6: звуки беты — click.wav побайтно, gain и тон щелчка, затвор (Tools/sound_ref.js; без --check пересобирает эталон).
sound:
	@node Tools/sound_ref.js $(ARGS)

# Итерация 20д: там, где у веба имитация стекла, — только встроенное стекло.
glass:
	@Tools/check_glass.sh

# Итерация 26т: сборка на телефон одним скриптом (имя и идентификатор из ветки).
phone:
	@Tools/phone.sh $(ARGS)

# Итерация 26т: проверка шага — четыре строки да/нет.
checkstep:
	@Tools/check_step.sh $(ARGS)
