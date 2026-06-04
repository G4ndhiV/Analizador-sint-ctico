#ifndef TOKENS_H
#define TOKENS_H

/*
 * IDs documentados (reporte léxico). Deben coincidir con %token en parser.y.
 * No usar #define con el mismo nombre que los tokens de Bison.
 */
enum LexTokenDocId {
    DOC_IDENTIFIER = 100,
    DOC_KEYWORD    = 101,
    DOC_INTEGER    = 200,
    DOC_FLOAT      = 300,
    DOC_STRING     = 400,
    DOC_OPERATOR   = 500,
    DOC_DELIMITER  = 600,
    DOC_COMMENT    = 700,
    DOC_INDENT     = 910,
    DOC_DEDENT     = 911,
    DOC_WS_COUNT   = 900,
    DOC_WHITESPACE = 901,
    DOC_NEWLINE    = 950,
    DOC_ERROR      = 999
};

#define MAX_LEXEME_LEN 1500
#define MAX_SYMBOLS    5000

#endif
