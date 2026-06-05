#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lexer.h"
#include "symtab.h"
#include "tokens.h"

extern int yylex(void);
extern int yyparse(void);
extern int yydebug;
extern int lexical_error_seen;
extern int syntax_error_seen;

static void usage(const char *prog) {
    fprintf(stderr, "Uso: %s [-t] [-d] <archivo.tri>\n", prog);
    fprintf(stderr, "  -t  modo tokens (solo lexer, como fase lexica)\n");
    fprintf(stderr, "  -d  depuracion yacc\n");
}

int main(int argc, char **argv) {
    const char *input = NULL;
    int i;
    int rc;

    for (i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "-t") == 0) {
            lexer_debug_mode = 1;
        } else if (strcmp(argv[i], "-d") == 0) {
            yydebug = 1;
        } else if (argv[i][0] == '-') {
            usage(argv[0]);
            return 1;
        } else {
            input = argv[i];
        }
    }

    if (!input) {
        usage(argv[0]);
        return 1;
    }

    yyin = fopen(input, "r");
    if (!yyin) {
        perror("No se pudo abrir el archivo");
        return 1;
    }

    if (lexer_debug_mode) {
        while (yylex() != 0) {
            /* consumir todos los tokens */
        }
        print_symbol_tables();
        fclose(yyin);
        return lexical_error_seen ? 2 : 0;
    }

    parser_mode = 1;
    lexer_reset_for_parse();
    symtab_reset();

    syntax_error_seen = 0;
    rc = yyparse();

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

    if (lexical_error_seen) {
        return 2;
    }
    if (rc != 0 || syntax_error_seen) {
        return 1;
    }

    printf("PARSE_OK: archivo '%s' sintacticamente valido.\n", input);
    symtab_print();
    print_symbol_tables();
    return 0;
}
