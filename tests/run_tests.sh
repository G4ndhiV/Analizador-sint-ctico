#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/triton_parser"
RESULTS="$ROOT/results/parser"
PASS=0
FAIL=0
TOTAL=0

mkdir -p "$RESULTS"

if [[ ! -x "$BIN" ]]; then
  echo "ERROR: compilar primero con 'make build'"
  exit 1
fi

run_valid() {
  local f="$1"
  local name
  name="$(basename "$f")"
  TOTAL=$((TOTAL + 1))
  local log="$RESULTS/valid_${name}.log"
  if "$BIN" "$f" >"$log" 2>&1; then
    if grep -q "PARSE_OK" "$log"; then
      echo "PASS  valid  $name"
      PASS=$((PASS + 1))
    else
      echo "FAIL  valid  $name (sin PARSE_OK)"
      FAIL=$((FAIL + 1))
    fi
  else
    echo "FAIL  valid  $name (exit $?)"
    cat "$log" | tail -5
    FAIL=$((FAIL + 1))
  fi
}

run_invalid() {
  local f="$1"
  local name
  name="$(basename "$f")"
  TOTAL=$((TOTAL + 1))
  local log="$RESULTS/invalid_${name}.log"
  if "$BIN" "$f" >"$log" 2>&1; then
    echo "FAIL  invalid $name (debió fallar)"
    FAIL=$((FAIL + 1))
  else
    if grep -qE "SYNTAX_ERROR|LEXICAL_ERROR" "$log"; then
      echo "PASS  invalid $name"
      PASS=$((PASS + 1))
    else
      echo "FAIL  invalid $name (sin SYNTAX_ERROR ni LEXICAL_ERROR)"
      tail -5 "$log"
      FAIL=$((FAIL + 1))
    fi
  fi
}

echo "=== Analizador sintactico — suite de pruebas ==="

LEX_DIR="$ROOT/tests/fixtures/lexico"
if [[ ! -d "$LEX_DIR" ]]; then
  LEX_DIR="$ROOT/../Analizador-lexico-main"
fi
for f in "$LEX_DIR"/ejemplo_{1,2}.tri; do
  [[ -f "$f" ]] && run_valid "$f"
done

for f in "$ROOT/tests/valid"/*.tri; do
  [[ -f "$f" ]] && run_valid "$f"
done

for f in "$ROOT/tests/invalid"/*.tri; do
  [[ -f "$f" ]] && run_invalid "$f"
done

# Modo lexer (-t): ejemplo_1 y ejemplo_3 (ops compuestos, solo fase lexica)
for lex_f in ejemplo_1 ejemplo_3; do
  TOTAL=$((TOTAL + 1))
  if "$BIN" -t "$LEX_DIR/${lex_f}.tri" 2>"$RESULTS/lexer_${lex_f}.log" | grep -qE "KEYWORD|OPERATOR"; then
    echo "PASS  lexer -t ${lex_f}.tri"
    PASS=$((PASS + 1))
  else
    echo "FAIL  lexer -t ${lex_f}.tri"
    FAIL=$((FAIL + 1))
  fi
done

cat >"$RESULTS/summary.json" <<EOF
{
  "total": $TOTAL,
  "pass": $PASS,
  "fail": $FAIL,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo "---"
echo "Resumen: $PASS/$TOTAL PASS, $FAIL FAIL"
echo "Logs: $RESULTS/"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
