/*
 * Archivo : include/tokens.h
 * Proposito: Constantes numericas de tokens compartidas por el scanner (Flex)
 *            y el parser (yacc/Bison). Define los IDs documentados en el
 *            reporte lexico del Equipo 11 y los limites globales de las tablas
 *            de simbolos.
 * Relacion : Incluido por lexer/lexico_equipo_11_scanner.l y parser/parser.y
 *            para garantizar coherencia en los identificadores de token.
 */

#ifndef TOKENS_H
#define TOKENS_H

/*
 * LexTokenDocId: enumeracion con los identificadores numericos de cada clase
 * de token, tal como se documentan en el Cuadro 1 del reporte lexico.
 * Estos valores deben coincidir con los declarados con %token en parser.y.
 * Se usa el prefijo DOC_ para evitar colisiones con los simbolos que genera
 * Bison al procesar parser.y.
 */
enum LexTokenDocId {
    DOC_IDENTIFIER = 100,   /* Identificadores validos [a-zA-Z_][a-zA-Z0-9_]* */
    DOC_KEYWORD    = 101,   /* Palabras reservadas (def, if, return, ...)        */
    DOC_INTEGER    = 200,   /* Literales enteros: decimal, hex, octal, binario  */
    DOC_FLOAT      = 300,   /* Literales de punto flotante con exponente op.    */
    DOC_STRING     = 400,   /* Cadenas delimitadas por ' o " en una sola linea  */
    DOC_OPERATOR   = 500,   /* Operadores aritmeticos, relacionales y logicos   */
    DOC_DELIMITER  = 600,   /* Delimitadores: parentesis, corchetes, coma, ...   */
    DOC_COMMENT    = 700,   /* Comentarios Python (#...); ignorados en modo parser*/
    DOC_WS_COUNT   = 900,   /* Espacios iniciales de linea; generan INDENT/DEDENT*/
    DOC_WHITESPACE = 901,   /* Espacio/tabulador interno de linea; descartado   */
    DOC_INDENT     = 910,   /* Token sintetico: apertura de bloque indentado    */
    DOC_DEDENT     = 911,   /* Token sintetico: cierre de bloque indentado      */
    DOC_NEWLINE    = 950,   /* Salto de linea \n; delimitador de sentencias     */
    DOC_ERROR      = 999    /* Error lexico: caracter o secuencia invalida      */
};

/* MAX_LEXEME_LEN: longitud maxima de un lexema (cubre cadenas largas en .tri) */
#define MAX_LEXEME_LEN 1500

/* MAX_SYMBOLS: capacidad de cada tabla de simbolos lexica (IDs, ints, ...) */
#define MAX_SYMBOLS    5000

#endif /* TOKENS_H */
