CC      = cc
CFLAGS  = -Wall -Wextra -g -Iinclude -Ibuild -Iparser -Ilexer
BUILD   = build
LEX_SRC = lexer/lexico_equipo_11_scanner.l
YACC_SRC = parser/parser.y

UNAME_S := $(shell uname -s 2>/dev/null)
ifeq ($(UNAME_S),Darwin)
  BISON ?= /opt/homebrew/opt/bison/bin/bison
  FLEX  ?= /opt/homebrew/opt/flex/bin/flex
  FLEX_LIBS ?= -L/opt/homebrew/opt/flex/lib -lfl
else
  BISON ?= $(shell command -v bison 2>/dev/null || echo bison)
  FLEX  ?= $(shell command -v flex 2>/dev/null || echo flex)
  FLEX_LIBS ?= -lfl
endif
YACC = $(BISON)
LEX  = $(FLEX)

.PHONY: all build test jsonl-test benchmark figures pdf clean check-deps

all: build

check-deps:
	@echo "=== Dependencias ==="
	@command -v $(CC) >/dev/null && echo "OK  $(CC)" || echo "FALTA $(CC) (Xcode CLT o gcc)"
	@command -v $(BISON) >/dev/null && $(BISON) --version | head -1 || echo "FALTA bison"
	@command -v $(FLEX) >/dev/null && $(FLEX) --version | head -1 || echo "FALTA flex"
	@command -v python3 >/dev/null && echo "OK  python3" || echo "FALTA python3"
	@command -v tectonic >/dev/null && echo "OK  tectonic" || echo "AVISO tectonic (opcional para make pdf; usar latexmk)"

build: $(BUILD)/triton_parser

$(BUILD)/y.tab.c $(BUILD)/y.tab.h: $(YACC_SRC)
	mkdir -p $(BUILD)
	$(BISON) -d -o $(BUILD)/y.tab.c $(YACC_SRC)

$(BUILD)/lex.yy.c: $(LEX_SRC) $(BUILD)/y.tab.h
	$(FLEX) -o $(BUILD)/lex.yy.c $(LEX_SRC)

$(BUILD)/triton_parser: $(BUILD)/y.tab.c $(BUILD)/lex.yy.c parser/symtab.c src/driver.c
	$(CC) $(CFLAGS) -o $@ $(BUILD)/y.tab.c $(BUILD)/lex.yy.c parser/symtab.c src/driver.c $(FLEX_LIBS)

test: build
	bash tests/run_tests.sh

jsonl-test: build
	chmod +x scripts/run_jsonl_tests.sh
	./scripts/run_jsonl_tests.sh

benchmark: build
	chmod +x scripts/run_benchmark_kernels.sh
	./scripts/run_benchmark_kernels.sh

figures: benchmark
	@test -d .venv || python3 -m venv .venv
	@.venv/bin/pip install -q -r requirements.txt
	@.venv/bin/python scripts/plot_benchmark_results.py

pdf: test figures
	chmod +x scripts/capture_outputs.sh scripts/export_report_data.py
	./scripts/capture_outputs.sh
	python3 scripts/export_report_data.py
	$(MAKE) -C report pdf
	mkdir -p deliverables
	cp -f report/main.pdf deliverables/Informe_Analizador_Sintactico_Equipo11.pdf

clean:
	rm -rf $(BUILD)
	$(MAKE) -C report clean 2>/dev/null || true
	rm -rf results/parser deliverables/*.pdf
