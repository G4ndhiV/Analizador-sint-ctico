#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RES="$ROOT/results/parser"
mkdir -p "$RES"

# Extraer métricas para LaTeX
if [[ -f "$RES/summary.json" ]]; then
  python3 - <<'PY' "$RES/summary.json" "$RES"
import json, sys
p = sys.argv[1]
with open(sys.argv[1]) as f:
    d = json.load(f)
for k, fn in [("total", "summary_total.tex"), ("pass", "summary_pass.tex"), ("fail", "summary_fail.tex")]:
    open(f"{sys.argv[2]}/{fn}", "w").write(str(d.get(k, 0)))
PY
fi

python3 "$ROOT/scripts/export_report_data.py" 2>/dev/null || true
echo "Capturas listas en $RES y report/data/"
