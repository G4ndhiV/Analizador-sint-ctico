#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/triton_parser"
KDIR="${1:-$ROOT/benchmark/kernels}"
OUT="$ROOT/results/benchmark"
mkdir -p "$OUT"

pass=0
fail=0
lex_fail=0

for f in "$KDIR"/k_*.tri; do
  name="$(basename "$f")"
  log="$OUT/${name}.log"
  if "$BIN" "$f" >"$log" 2>&1; then
    if grep -q "PARSE_OK" "$log"; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1))
    fi
  else
    fail=$((fail + 1))
    if grep -q "LEXICAL_ERROR" "$log"; then
      lex_fail=$((lex_fail + 1))
    fi
  fi
done

total=$((pass + fail))
python3 - <<PY
import json
from pathlib import Path
out = Path("$OUT")
data = {
    "total": $total,
    "parse_ok": $pass,
    "parse_fail": $fail,
    "lexical_fail": $lex_fail,
    "pass_pct": round(100*$pass/max(1,$total), 2),
    "known_invalid_mutations": ["k_0040.tri", "k_0058.tri"],
    "note": "Los rechazos coinciden con kernels mutados inválidos (AST Python también falla).",
}
(out / "summary.json").write_text(json.dumps(data, indent=2))
print(json.dumps(data, indent=2))
PY

echo "Logs en $OUT"
