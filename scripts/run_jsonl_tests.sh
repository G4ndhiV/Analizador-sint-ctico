#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/triton_parser"
OUT="$ROOT/results/jsonl"
CURATED="$ROOT/curated_100.jsonl"
ADV="$ROOT/adversarial_100.jsonl"

mkdir -p "$OUT"

if [[ ! -x "$BIN" ]]; then
  echo "ERROR: compilar primero con 'make build'"
  exit 1
fi

python3 - "$BIN" "$CURATED" "$ADV" "$OUT" <<'PY'
import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

bin_path, curated_path, adv_path, out_dir = sys.argv[1:5]

SUMMARY_PATH = os.path.join(out_dir, "summary.json")
DETAILS_PATH = os.path.join(out_dir, "details.json")
REPORT_PATH = os.path.join(out_dir, "report.txt")
CURATED_PASS_PATH = os.path.join(out_dir, "curated_pass.txt")
CURATED_FAIL_PATH = os.path.join(out_dir, "curated_fail.txt")
ADV_PASS_PATH = os.path.join(out_dir, "adversarial_pass.txt")
ADV_FAIL_PATH = os.path.join(out_dir, "adversarial_fail.txt")


def run_kernel(code: str) -> dict:
    with tempfile.NamedTemporaryFile(mode="w", suffix=".tri", delete=False, encoding="utf-8") as f:
        f.write(code)
        path = f.name
    try:
        r = subprocess.run([bin_path, path], capture_output=True)
        out = (r.stdout + r.stderr).decode("utf-8", errors="replace")
        parse_ok = r.returncode == 0 and "PARSE_OK" in out
        err_lines = [
            ln.strip()
            for ln in out.splitlines()
            if "SYNTAX_ERROR" in ln or "LEXICAL_ERROR" in ln
        ]
        return {
            "exit_code": r.returncode,
            "parse_ok": parse_ok,
            "error": err_lines[0] if err_lines else "",
            "errors": err_lines,
        }
    finally:
        os.unlink(path)


def write_lines(path: str, lines: list[str]) -> None:
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
        f.write("\n")


# --- curated_100: todos deben dar PARSE_OK ---
curated_results = []
with open(curated_path, encoding="utf-8") as f:
    for i, line in enumerate(f):
        row = json.loads(line)
        run = run_kernel(row["kernel_code"])
        ok = run["parse_ok"]
        curated_results.append({
            "index": i,
            "function_name": row.get("function_name", ""),
            "source_id": row.get("source_id", ""),
            "num_lines": row.get("num_lines", 0),
            "expected": "PARSE_OK",
            "got_parse_ok": run["parse_ok"],
            "pass": ok,
            "exit_code": run["exit_code"],
            "error": run["error"],
        })

curated_pass = [r for r in curated_results if r["pass"]]
curated_fail = [r for r in curated_results if not r["pass"]]

# --- adversarial_100: clasificar según should_parse ---
adv_results = []
with open(adv_path, encoding="utf-8") as f:
    for line in f:
        row = json.loads(line)
        should = bool(row.get("should_parse", False))
        run = run_kernel(row["kernel_code"])
        got = run["parse_ok"]
        ok = got == should
        adv_results.append({
            "id": row.get("id", ""),
            "category": row.get("category", ""),
            "subcategory": row.get("subcategory", ""),
            "expected_parse": should,
            "got_parse_ok": got,
            "pass": ok,
            "exit_code": run["exit_code"],
            "error": run["error"],
            "error_description": row.get("error_description", ""),
        })

adv_pass = [r for r in adv_results if r["pass"]]
adv_fail = [r for r in adv_results if not r["pass"]]

timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

summary = {
    "curated": {
        "total": len(curated_results),
        "pass": len(curated_pass),
        "fail": len(curated_fail),
        "pass_rate": round(100.0 * len(curated_pass) / max(1, len(curated_results)), 1),
        "failures": [
            {"index": r["index"], "function_name": r["function_name"], "error": r["error"]}
            for r in curated_fail
        ],
    },
    "adversarial": {
        "total": len(adv_results),
        "pass": len(adv_pass),
        "fail": len(adv_fail),
        "pass_rate": round(100.0 * len(adv_pass) / max(1, len(adv_results)), 1),
        "failures": [
            {
                "id": r["id"],
                "expected_parse": r["expected_parse"],
                "got_parse_ok": r["got_parse_ok"],
                "error": r["error"],
            }
            for r in adv_fail
        ],
    },
    "timestamp": timestamp,
    "artifacts": {
        "report": REPORT_PATH,
        "details": DETAILS_PATH,
        "curated_pass_list": CURATED_PASS_PATH,
        "curated_fail_list": CURATED_FAIL_PATH,
        "adversarial_pass_list": ADV_PASS_PATH,
        "adversarial_fail_list": ADV_FAIL_PATH,
    },
}

details = {
    "timestamp": timestamp,
    "curated": curated_results,
    "adversarial": adv_results,
}

with open(SUMMARY_PATH, "w", encoding="utf-8") as f:
    json.dump(summary, f, indent=2, ensure_ascii=False)
    f.write("\n")

with open(DETAILS_PATH, "w", encoding="utf-8") as f:
    json.dump(details, f, indent=2, ensure_ascii=False)
    f.write("\n")

# Listas legibles por suite
cur_pass_lines = [
    f"PASS  idx={r['index']:3d}  {r['function_name']}"
    for r in curated_pass
]
cur_fail_lines = [
    f"FAIL  idx={r['index']:3d}  {r['function_name']}"
    + (f"  |  {r['error']}" if r["error"] else "")
    for r in curated_fail
]

adv_pass_lines = []
for r in adv_pass:
    exp = "PARSE_OK" if r["expected_parse"] else "REJECT"
    adv_pass_lines.append(
        f"PASS  {r['id']}  [{r['category']}]  esperado={exp}  obtenido={'PARSE_OK' if r['got_parse_ok'] else 'REJECT'}"
    )

adv_fail_lines = []
for r in adv_fail:
    exp = "PARSE_OK" if r["expected_parse"] else "REJECT"
    got = "PARSE_OK" if r["got_parse_ok"] else "REJECT"
    line = f"FAIL  {r['id']}  [{r['category']}]  esperado={exp}  obtenido={got}"
    if r["error"]:
        line += f"  |  {r['error']}"
    adv_fail_lines.append(line)

write_lines(CURATED_PASS_PATH, cur_pass_lines)
write_lines(CURATED_FAIL_PATH, cur_fail_lines)
write_lines(ADV_PASS_PATH, adv_pass_lines)
write_lines(ADV_FAIL_PATH, adv_fail_lines)

# Informe completo en texto
report = []
report.append("=" * 72)
report.append("INFORME JSONL — curated_100 + adversarial_100")
report.append(f"Generado: {timestamp}")
report.append(f"Parser:   {bin_path}")
report.append("=" * 72)
report.append("")
report.append("RESUMEN")
report.append("-" * 72)
report.append(
    f"  curated_100     : {len(curated_pass):3d} PASS / {len(curated_fail):3d} FAIL  "
    f"({summary['curated']['pass_rate']}% PARSE_OK)"
)
report.append(
    f"  adversarial_100 : {len(adv_pass):3d} PASS / {len(adv_fail):3d} FAIL  "
    f"({summary['adversarial']['pass_rate']}% clasificacion correcta)"
)
report.append(
    f"  TOTAL           : {len(curated_pass) + len(adv_pass):3d} PASS / "
    f"{len(curated_fail) + len(adv_fail):3d} FAIL  (de 200 casos)"
)
report.append("")
report.append("ARCHIVOS GENERADOS")
report.append("-" * 72)
report.append(f"  {REPORT_PATH}")
report.append(f"  {SUMMARY_PATH}")
report.append(f"  {DETAILS_PATH}")
report.append(f"  {CURATED_PASS_PATH}  ({len(curated_pass)} lineas)")
report.append(f"  {CURATED_FAIL_PATH}  ({len(curated_fail)} lineas)")
report.append(f"  {ADV_PASS_PATH}  ({len(adv_pass)} lineas)")
report.append(f"  {ADV_FAIL_PATH}  ({len(adv_fail)} lineas)")
report.append("")
report.append("=" * 72)
report.append("CURATED_100 — kernels validos (deben dar PARSE_OK)")
report.append("=" * 72)
report.append("")
report.append(f"--- PASS ({len(curated_pass)}) ---")
report.extend(cur_pass_lines if cur_pass_lines else ["(ninguno)"])
report.append("")
report.append(f"--- FAIL ({len(curated_fail)}) ---")
report.extend(cur_fail_lines if cur_fail_lines else ["(ninguno)"])
report.append("")
report.append("=" * 72)
report.append("ADVERSARIAL_100 — clasificacion lexer/sintaxis/indentacion")
report.append("=" * 72)
report.append("")
report.append(f"--- PASS ({len(adv_pass)}) ---")
report.extend(adv_pass_lines if adv_pass_lines else ["(ninguno)"])
report.append("")
report.append(f"--- FAIL ({len(adv_fail)}) ---")
report.extend(adv_fail_lines if adv_fail_lines else ["(ninguno)"])
report.append("")

write_lines(REPORT_PATH, report)

# Salida en terminal (resumen + rutas)
print()
print("=" * 72)
print("JSONL TEST RUN — curated_100 + adversarial_100")
print("=" * 72)
print(f"  curated_100     : {len(curated_pass):3d}/100 PASS  |  {len(curated_fail):3d}/100 FAIL")
print(f"  adversarial_100 : {len(adv_pass):3d}/100 PASS  |  {len(adv_fail):3d}/100 FAIL")
print(f"  TOTAL           : {len(curated_pass) + len(adv_pass):3d}/200 PASS  |  "
      f"{len(curated_fail) + len(adv_fail):3d}/200 FAIL")
print()
print("Informe completo:")
print(f"  {REPORT_PATH}")
print()
if curated_fail:
    print("Curated FAIL:")
    for line in cur_fail_lines:
        print(f"  {line}")
    print()
if adv_fail:
    print("Adversarial FAIL:")
    for line in adv_fail_lines:
        print(f"  {line}")
    print()

if curated_fail or adv_fail:
    sys.exit(1)
PY
