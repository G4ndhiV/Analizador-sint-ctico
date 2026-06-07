/*
 * Archivo : src/driver.c
 * Proposito: Punto de entrada del analizador sintactico triton_parser.
 *            Parsea los argumentos de linea de comandos, abre el archivo
 *            fuente .tri, ejecuta el scanner en modo depuracion (-t) o
 *            invoca el parser completo (modo por defecto), e imprime el
 *            resultado con el codigo de salida correspondiente.
 *
 * Modos de operacion:
 *   Sin -t : modo parser completo. Activa parser_mode, llama yyparse() y,
 *            si no hay errores, imprime PARSE_OK, la tabla del parser y las
 *            tablas lexicas.
 *   Con -t : modo solo-lexico. Recorre todos los tokens con yylex() e imprime
 *            cada uno junto con las tablas de simbolos al final. Compatible
 *            con la salida del reporte lexico (casos TC-01 a TC-04).
 *   Con -d : activa el modo de depuracion interna de yacc (yydebug=1).
 *
 * Codigos de salida:
 *   0 -- analisis exitoso (PARSE_OK o modo -t sin errores lexicos).
 *   1 -- error sintactico detectado por yyparse() o yyerror().
 *   2 -- error lexico detectado por el scanner (lexical_error_seen = 1).
 *
 * Relacion : Incluye lexer/lexer.h para controlar el scanner, parser/symtab.h
 *            para inicializar la tabla de simbolos e include/tokens.h para
 *            compartir constantes. El ejecutable resultante (build/triton_parser)
 *            es invocado por los scripts de prueba en tests/ y scripts/.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lexer.h"
#include "symtab.h"
#include "tokens.h"

/* Declaraciones externas generadas por Bison al compilar parser.y            */
extern int yylex(void);
extern int yyparse(void);
extern int yydebug;            /* Flag de depuracion de yacc (--debug)         */
extern int lexical_error_seen; /* 1 si el scanner encontro un token invalido   */
extern int syntax_error_seen;  /* 1 si yyerror() fue llamada durante el parse  */

/*
 * usage: imprime la sinopsis del programa en stderr.
 * Llamada cuando los argumentos son invalidos o no se provee archivo.
 */
static void usage(const char *prog) {
    fprintf(stderr, "Uso: %s [-t] [-d] <archivo.tri>\n", prog);
    fprintf(stderr, "  -t  modo tokens (solo lexer, como fase lexica)\n");
    fprintf(stderr, "  -d  depuracion yacc\n");
}

/*
 * main: flujo principal del driver.
 *
 *  1. Parseo de flags: -t activa lexer_debug_mode, -d activa yydebug.
 *  2. Apertura del archivo .tri.
 *  3. Si es modo -t: consume tokens con yylex() e imprime tablas lexicas.
 *  4. Si es modo parser: inicializa el estado (parser_mode, reset lexico y
 *     de symtab), invoca yyparse(), verifica tokens sobrantes, e imprime
 *     PARSE_OK + tablas si el analisis fue exitoso.
 */
int main(int argc, char **argv) {
    const char *input = NULL;
    int i;
    int rc;

    /* Parseo de argumentos de linea de comandos */
    for (i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "-t") == 0) {
            lexer_debug_mode = 1;          /* Modo solo-lexico */
        } else if (strcmp(argv[i], "-d") == 0) {
            yydebug = 1;                   /* Traza interna de yacc */
        } else if (argv[i][0] == '-') {
            usage(argv[0]);
            return 1;
        } else {
            input = argv[i];               /* Archivo fuente .tri */
        }
    }

    if (!input) {
        usage(argv[0]);
        return 1;
    }

    /* Abrir el archivo fuente; yyin es la variable global de Flex */
    yyin = fopen(input, "r");
    if (!yyin) {
        perror("No se pudo abrir el archivo");
        return 1;
    }

    /* -- Modo solo-lexico (-t) ---------------------------------------------  */
    if (lexer_debug_mode) {
        while (yylex() != 0) {
            /* Consumir todos los tokens; cada llamada imprime en emit_token_* */
        }
        print_symbol_tables();
        fclose(yyin);
        return lexical_error_seen ? 2 : 0;
    }

    /* -- Modo parser (por defecto) -----------------------------------------  */

    /* Activar modo parser y reiniciar estado del scanner y tabla de simbolos */
    parser_mode = 1;
    lexer_reset_for_parse();
    symtab_reset();

    syntax_error_seen = 0;
    rc = yyparse();  /* Invocar el parser generado por Bison */

    /* Verificar que no haya tokens sobrantes despues del programa completo    *
     * (p. ej. codigo despues de un dedent final inesperado).                  */
    if (rc == 0 && !syntax_error_seen) {
        int extra;
        while ((extra = yylex()) != 0) {
            syntax_error_seen = 1;
            fprintf(stderr,
                    "SYNTAX_ERROR: line=%d near='' message='tokens extra tras fin de programa'\n",
                    line_no);
            break;
        }
    }

    fclose(yyin);

    /* Prioridad: error lexico > error sintactico > exito */
    if (lexical_error_seen) {
        return 2;
    }
    if (rc != 0 || syntax_error_seen) {
        return 1;
    }

    /* Exito: imprimir PARSE_OK y volcar ambas tablas de simbolos */
    printf("PARSE_OK: archivo '%s' sintacticamente valido.\n", input);
    symtab_print();          /* Tabla del parser: funciones, params, vars      */
    print_symbol_tables();   /* Tablas lexicas: IDs, enteros, flotantes, cadenas*/
    return 0;
}
