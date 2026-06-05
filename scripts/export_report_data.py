#!/usr/bin/env python3
"""Exporta métricas a fragmentos .tex para el reporte."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPORT_DATA = ROOT / "report" / "data"


def write(name: str, value: str) -> None:
    (REPORT_DATA / name).write_text(value.strip() + "\n", encoding="utf-8")


def main() -> None:
    REPORT_DATA.mkdir(parents=True, exist_ok=True)

    parser_sum = ROOT / "results" / "parser" / "summary.json"
    if parser_sum.exists():
        d = json.loads(parser_sum.read_text())
        for k in ("total", "pass", "fail"):
            if k in d:
                write(f"parser_{k}.tex", str(d[k]))

    bench_sum = ROOT / "results" / "benchmark" / "summary.json"
    if bench_sum.exists():
        d = json.loads(bench_sum.read_text())
        write("bench_total.tex", str(d.get("total", 70)))
        write("bench_ok.tex", str(d.get("parse_ok", 0)))
        write("bench_fail.tex", str(d.get("parse_fail", 0)))
        write("bench_pct.tex", str(d.get("pass_pct", 0)))
        write("bench_lex_fail.tex", str(d.get("lexical_fail", 0)))

    jsonl_sum = ROOT / "results" / "jsonl" / "summary.json"
    if jsonl_sum.exists():
        d = json.loads(jsonl_sum.read_text())
        curated = d.get("curated", {})
        adv = d.get("adversarial", {})
        write("jsonl_curated_pass.tex", str(curated.get("pass", 100)))
        write("jsonl_adv_pass.tex", str(adv.get("pass", 100)))
        write("jsonl_total_pass.tex", str(curated.get("pass", 0) + adv.get("pass", 0)))

    print(f"Datos LaTeX en {REPORT_DATA}")


if __name__ == "__main__":
    main()
