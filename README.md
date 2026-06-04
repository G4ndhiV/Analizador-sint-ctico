# Analizador Sintáctico — Triton GPU Kernel (Equipo 11)

Parser **yacc/Bison** + scanner **Flex** para archivos `.tri` (TC3002B, Fase II).

Repositorio: [G4ndhiV/Analizador-sint-ctico](https://github.com/G4ndhiV/Analizador-sint-ctico)

## Requisitos

- macOS o Linux con `cc`, **Flex** y **Bison**
- macOS (Homebrew): `brew install bison flex`
- Para gráficas: Python 3 + `matplotlib` (ver `requirements.txt`)
- Para PDF del informe: [Tectonic](https://tectonic-typesetting.github.io/) o `latexmk`

En Mac, el `Makefile` usa por defecto:

- `/opt/homebrew/opt/bison/bin/bison`
- `/opt/homebrew/opt/flex/bin/flex`

En Linux, edita las rutas en el `Makefile` o instala `bison`/`flex` en el PATH del sistema.

## Uso rápido

```bash
make build          # compila build/triton_parser
make test           # suite unitaria (12 pruebas)
make benchmark      # 70 kernels en benchmark/kernels/
make figures        # gráfica en figures/
make pdf            # informe PDF (requiere tectonic)
```

Probar un archivo:

```bash
./build/triton_parser tests/valid/triton_kernel_min.tri
./build/triton_parser -t tests/fixtures/lexico/ejemplo_1.tri   # modo tokens
```

## Resultados incluidos

| Artefacto | Descripción |
|-----------|-------------|
| `results/parser/summary.json` | Suite unitaria: **12/12 PASS** |
| `results/benchmark/summary.json` | Benchmark 70 kernels: **68 PARSE_OK (97.1%)** |
| `figures/benchmark_parse_results.pdf` | Gráfica de resultados |
| `deliverables/Informe_Analizador_Sintactico_Equipo11.pdf` | Informe IEEE-830 |

Los rechazos del benchmark (`k_0040`, `k_0058`) son mutaciones inválidas esperadas.

## Estructura

```
lexer/          Scanner Flex
parser/         Gramática yacc + symtab
src/            Driver
tests/          Casos válidos/inválidos + fixtures léxicos
benchmark/      70 kernels TRITONHEAL (k_*.tri)
scripts/        Benchmark, gráficas, export LaTeX
report/         Fuentes del informe
results/        Resúmenes JSON (logs se regeneran con make)
figures/        Gráfica del benchmark
deliverables/   PDF final
```

## Regenerar todo

```bash
make clean build test benchmark figures
# PDF completo:
make pdf
```

## Equipo

TC3002B — Compiladores — Tecnológico de Monterrey, campus Guadalajara.
