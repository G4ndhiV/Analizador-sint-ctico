CC      = cc
CFLAGS  = -Wall -Wextra -g -Iinclude -Ibuild -Iparser -Ilexer
LEX     = flex
YACC    = bison
BISON   = /opt/homebrew/opt/bison/bin/bison
FLEX    = /opt/homebrew/opt/flex/bin/flex
LEX     = $(FLEX)
YACC    = $(BISON)

BUILD   = build
LEX_SRC = lexer/lexico_equipo_11_scanner.l
YACC_SRC = parser/parser.y

.PHONY: all build test benchmark figures pdf clean

all: build

build: $(BUILD)/triton_parser

$(BUILD)/y.tab.c $(BUILD)/y.tab.h: $(YACC_SRC)
	mkdir -p $(BUILD)
	$(BISON) -d -o $(BUILD)/y.tab.c $(YACC_SRC)
	@# yacc en macOS genera y.tab.h junto a y.tab.c

$(BUILD)/lex.yy.c: $(LEX_SRC) $(BUILD)/y.tab.h
	$(FLEX) -o $(BUILD)/lex.yy.c $(LEX_SRC)

$(BUILD)/triton_parser: $(BUILD)/y.tab.c $(BUILD)/lex.yy.c parser/symtab.c src/driver.c
	$(CC) $(CFLAGS) -o $@ $(BUILD)/y.tab.c $(BUILD)/lex.yy.c parser/symtab.c src/driver.c \
		-L/opt/homebrew/opt/flex/lib -lfl

test: build
	bash tests/run_tests.sh

benchmark: build
	chmod +x scripts/run_benchmark_kernels.sh
	./scripts/run_benchmark_kernels.sh

figures: benchmark
	@test -d .venv || python3 -m venv .venv
	@.venv/bin/pip install -q matplotlib
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
