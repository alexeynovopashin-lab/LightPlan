# Стенд паритета JS ↔ Swift. Подробности — Tools/parity/README.md.
#
# Часовой пояс прибит к UTC намеренно: computeSun берёт номер дня через
# локальный new Date(y, 0, 0), и в поясе с переводом часов фикстуры зависели бы
# от машины, на которой их сгенерировали.

SHELL := /bin/bash
FIXTURES := Fixtures

.PHONY: help parity blocks lang icons

help:
	@echo "make parity   пересобрать фикстуры в $(FIXTURES)/ и доказать, что прогон повторяем"
	@echo "make blocks   показать, что вырезается из беты (дешёвая проверка якорей)"
	@echo "make lang     пересобрать каталог строк и фикстуры текста, доказать повторяемость"
	@echo "make icons    пересобрать знаки Swift из beta/icons.js, эталон Chromium и доказать, что прогон повторяем"

parity:
	@TZ=UTC node Tools/parity/generate.js --out $(FIXTURES)
	@tmp=$$(mktemp -d); \
	TZ=UTC node Tools/parity/generate.js --out $$tmp --quiet; \
	if diff -r $(FIXTURES) $$tmp > /dev/null; then \
		echo "  повторный прогон: побайтово то же"; \
		rm -rf $$tmp; \
	else \
		echo "  ПОВТОРНЫЙ ПРОГОН РАЗОШЁЛСЯ — стенду нельзя верить:"; \
		diff -rq $(FIXTURES) $$tmp; rm -rf $$tmp; exit 1; \
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
