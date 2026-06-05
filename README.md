# Analizador Sintáctico — Triton GPU Kernel (Equipo 11)

Parser **yacc/Bison** + scanner **Flex** para archivos `.tri` (TC3002B, Fase II).

**Repositorio:** [https://github.com/G4ndhiV/Analizador-sint-ctico](https://github.com/G4ndhiV/Analizador-sint-ctico)

El proyecto es **autocontenido**: incluye kernels de benchmark (`benchmark/kernels/`), fixtures léxicos (`tests/fixtures/lexico/`), resultados de referencia (`results/`), informe PDF (`deliverables/`) y gramática completa (`report/cfg/triton_cfg.bnf`). No hace falta clonar TRITONHEAL ni el analizador léxico para compilar o probar.

---

## Reproducir desde una PC nueva (guía completa)

### 1. Prerrequisitos

| Herramienta | Uso | macOS (Homebrew) | Linux (Debian/Ubuntu) |
|-------------|-----|------------------|------------------------|
| `git` | Clonar el repo | `xcode-select` o `brew install git` | `sudo apt install git` |
| `cc` | Compilar el parser | Xcode Command Line Tools | `sudo apt install build-essential` |
| **Bison** | Gramática yacc | `brew install bison` | `sudo apt install bison` |
| **Flex** | Scanner | `brew install flex` | `sudo apt install flex` |
| `python3` | Gráficas + export LaTeX | (suele venir instalado) | `sudo apt install python3 python3-venv` |
| **Tectonic** (opcional) | PDF del informe | `brew install tectonic` | ver [tectonic-typesetting.github.io](https://tectonic-typesetting.github.io/) |

Comprobar dependencias:

```bash
make check-deps
```

En **macOS**, el `Makefile` usa por defecto `/opt/homebrew/opt/bison/bin/bison` y `/opt/homebrew/opt/flex/bin/flex`. En **Linux**, usa `bison` y `flex` del `PATH`.

### 2. Clonar e instalar

```bash
git clone https://github.com/G4ndhiV/Analizador-sint-ctico.git
cd Analizador-sint-ctico
make check-deps    # opcional: verificar herramientas
```

### 3. Compilar y ejecutar pruebas

```bash
make build                    # genera build/triton_parser
make test                     # suite unitaria: 12/12 PASS
make jsonl-test               # curated_100.jsonl + adversarial_100.jsonl (kernels Triton reales)
make benchmark                # 70 kernels en benchmark/kernels/
make figures                  # figures/benchmark_parse_results.pdf
```

Probar un archivo manualmente:

```bash
./build/triton_parser tests/valid/triton_kernel_min.tri
./build/triton_parser -t tests/fixtures/lexico/ejemplo_1.tri   # solo tokens (fase léxica)
./build/triton_parser tests/invalid/identificador_caracter_invalido.tri   # LEXICAL_ERROR (BAD_ID)
```

### 4. Regenerar el informe PDF (opcional)

Requiere **Tectonic** o `latexmk`:

```bash
make pdf
```

Salida: `deliverables/Informe_Analizador_Sintactico_Equipo11.pdf`

### 5. Regenerar todo en un solo comando

```bash
make clean build test benchmark figures pdf
```

### 6. Salidas esperadas

| Ruta | Contenido |
|------|-----------|
| `build/triton_parser` | Ejecutable del analizador |
| `results/parser/summary.json` | Resumen suite (12 pruebas) |
| `results/jsonl/report.txt` | Informe legible: los 100 PASS y FAIL de cada suite |
| `results/jsonl/curated_pass.txt` / `curated_fail.txt` | Listas curated que pasan / fallan |
| `results/jsonl/adversarial_pass.txt` / `adversarial_fail.txt` | Listas adversarial correctas / incorrectas |
| `results/jsonl/details.json` | Detalle JSON de los 200 casos |
| `results/jsonl/summary.json` | Resumen numerico JSON |
| `results/benchmark/summary.json` | Resumen benchmark (68/70 PARSE_OK) |
| `figures/benchmark_parse_results.pdf` | Gráfica de resultados |
| `deliverables/Informe_Analizador_Sintactico_Equipo11.pdf` | Informe IEEE-830 |
| `report/cfg/triton_cfg.bnf` | CFG completa (91 producciones, P-001…P-091) |

### 7. Solo consultar resultados (sin compilar)

Si solo necesitas el informe y los JSON ya versionados:

```bash
git clone https://github.com/G4ndhiV/Analizador-sint-ctico.git
# Abrir deliverables/Informe_Analizador_Sintactico_Equipo11.pdf
# Revisar results/parser/summary.json y results/benchmark/summary.json
```

---

## Uso rápido (resumen)

```bash
make build
make test
make benchmark
make figures
make pdf    # requiere tectonic o latexmk
```

## Resultados de referencia

| Artefacto | Descripción |
|-----------|-------------|
| `results/parser/summary.json` | Suite unitaria: **12/12 PASS** |
| `results/benchmark/summary.json` | Benchmark 70 kernels: **68 PARSE_OK (97.1%)** |
| `figures/benchmark_parse_results.pdf` | Gráfica de resultados |
| `deliverables/Informe_Analizador_Sintactico_Equipo11.pdf` | Informe con Apéndice CFG completo |

Los rechazos del benchmark (`k_0040`, `k_0058`) son mutaciones inválidas esperadas.

## Estructura del repositorio

```
lexer/              Scanner Flex (BAD_ID alineado con Analizador-lexico)
parser/             Gramática yacc + symtab
src/                Driver
tests/              Válidos, inválidos, fixtures léxicos
benchmark/kernels/  70 archivos k_*.tri
scripts/            Benchmark, gráficas, export LaTeX
report/             LaTeX + cfg/triton_cfg.bnf (gramática completa)
results/            summary.json (logs se regeneran con make)
figures/            Gráfica del benchmark
deliverables/       PDF final del informe
```

## Enlaces relacionados

- Analizador léxico (reglas `BAD_ID`): [G4ndhiV/Analizador-lexico](https://github.com/G4ndhiV/Analizador-lexico)

## Equipo

TC3002B — Compiladores — Tecnológico de Monterrey, campus Guadalajara.
