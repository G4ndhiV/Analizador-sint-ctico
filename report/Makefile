MAIN = main.tex
PDF = main.pdf
TECTONIC ?= $(shell command -v tectonic 2>/dev/null || echo /opt/homebrew/bin/tectonic)

.PHONY: pdf clean

pdf: $(PDF)

$(PDF): $(MAIN) preamble.tex sections/*.tex
	@if [ -f ../results/parser/summary.json ]; then \
		../scripts/capture_outputs.sh; \
	fi
	@if [ -x "$(TECTONIC)" ]; then \
		$(TECTONIC) -X compile $(MAIN); \
	else \
		latexmk -pdf -interaction=nonstopmode $(MAIN); \
	fi

clean:
	rm -f *.aux *.log *.out *.pdf *.fls *.fdb_latexmk
