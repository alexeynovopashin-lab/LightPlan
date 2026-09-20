# Стенд паритета JS ↔ Swift. Подробности — Tools/parity/README.md.
#
# Часовой пояс прибит к UTC намеренно: computeSun берёт номер дня через
# локальный new Date(y, 0, 0), и в поясе с переводом часов фикстуры зависели бы
# от машины, на которой их сгенерировали.

SHELL := /bin/bash
FIXTURES := Fixtures

.PHONY: help parity blocks

help:
	@echo "make parity   пересобрать фикстуры в $(FIXTURES)/ и доказать, что прогон повторяем"
	@echo "make blocks   показать, что вырезается из беты (дешёвая проверка якорей)"

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
