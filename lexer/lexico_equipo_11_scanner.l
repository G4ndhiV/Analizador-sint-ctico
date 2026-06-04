%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "y.tab.h"
#include "tokens.h"

#ifndef TOKEN_ERROR
#define TOKEN_ERROR 999
#endif

#define MAX_SYMBOLS 5000

typedef struct {
    char lexeme[MAX_LEXEME_LEN];
} SymbolEntry;

static SymbolEntry id_table[MAX_SYMBOLS];
static SymbolEntry int_table[MAX_SYMBOLS];
static SymbolEntry float_table[MAX_SYMBOLS];
static SymbolEntry string_table[MAX_SYMBOLS];

static int id_count = 0;
static int int_count = 0;
static int float_count = 0;
static int string_count = 0;

int line_no = 1;
int lexer_debug_mode = 0;
int parser_mode = 0;
int lexical_error_seen = 0;

static int indent_stack[256];
static int indent_depth = 1;
static int pending_tokens[64];
static int pending_count = 0;
static int at_line_start = 1;
static char lexeme_buf[MAX_LEXEME_LEN];

static int is_keyword(const char *lex);
static int add_to_table(SymbolEntry *table, int *count, const char *lexeme);
static void emit_token_simple(int token_id, const char *token_name, const char *lexeme);
static void emit_token_ref(int token_id, const char *token_name, const char *lexeme, int index);
void print_symbol_tables(void);
static char *save_lexeme(const char *text);
static int push_pending(int tok);
static int pop_pending(void);
static int indent_width(const char *text, int len);
static int handle_indent(int width);
static int keyword_token(const char *lex);
static int return_token(int tok, const char *lexeme);

extern YYSTYPE yylval;

/* Flex genera yyflexlex; el wrapper yylex maneja INDENT/DEDENT pendientes. */
#define YY_DECL int yyflexlex(void)
int yylex(void);
%}

%option noyywrap
%option yylineno
%option nounput

LETTER          [a-zA-Z_]
DIGIT           [0-9]
ID              [a-zA-Z_][a-zA-Z0-9_]*
/* BAD_ID: misma politica que Analizador-lexico (G4ndhiV/Analizador-lexico) */
BAD_ID_CHAR     [$`\\?!]
BAD_ID          ([a-zA-Z0-9_]+{BAD_ID_CHAR}+([a-zA-Z0-9_]|{BAD_ID_CHAR})*|{BAD_ID_CHAR}+[a-zA-Z0-9_]([a-zA-Z0-9_]|{BAD_ID_CHAR})*)
INT             {DIGIT}+
FLOAT           ({DIGIT}*\.{DIGIT}+([eE][+-]?{DIGIT}+)?|{DIGIT}+[eE][+-]?{DIGIT}+)
STRING          \"[^\"\n]*\"|\'[^\'\n]*\'
STRING_UNCLOSED_LINE  \"[^\"\n]*\n|\'[^\'\n]*\n
STRING_UNCLOSED_EOF   \"[^\"\n]*|\'[^\'\n]*
COMMENT         \#[^)\n]*
WS_COUNT        ^[ \t]+
WHITESPACE      [ \t]+
NEWLINE         \n+
OPERATOR        "**"|"=="|"!="|"<="|">="|"//"|"<<"|">>"|"+="|"-="|"*="|"/="|"%="|[=+\-*/%&^<>|~]
DELIMITER       [()\[\]{}.,;:@]|"->"

%%

{COMMENT} {
    if (lexer_debug_mode) {
        emit_token_simple(TOKEN_COMMENT, "COMMENT", yytext);
    }
}

{FLOAT} {
    int idx = add_to_table(float_table, &float_count, yytext);
    at_line_start = 0;
    if (lexer_debug_mode) {
        emit_token_ref(TOKEN_FLOAT, "FLOAT", yytext, idx);
    } else if (parser_mode) {
        yylval.i = idx;
        return TOKEN_FLOAT;
    }
}

{INT} {
    int idx = add_to_table(int_table, &int_count, yytext);
    at_line_start = 0;
    if (lexer_debug_mode) {
        emit_token_ref(TOKEN_INTEGER, "INTEGER", yytext, idx);
    } else if (parser_mode) {
        yylval.i = idx;
        return TOKEN_INTEGER;
    }
}

{STRING} {
    int idx = add_to_table(string_table, &string_count, yytext);
    at_line_start = 0;
    if (lexer_debug_mode) {
        emit_token_ref(TOKEN_STRING, "STRING", yytext, idx);
    } else if (parser_mode) {
        yylval.i = idx;
        return TOKEN_STRING;
    }
}

{STRING_UNCLOSED_LINE} {
    fprintf(stderr,
            "LEXICAL_ERROR: token_id=<%d> line=%d lexeme=\"%s\" (cadena sin cerrar)\n",
            TOKEN_ERROR, line_no, yytext);
    lexical_error_seen = 1;
    line_no++;
    at_line_start = 1;
}

{STRING_UNCLOSED_EOF} {
    fprintf(stderr,
            "LEXICAL_ERROR: token_id=<%d> line=%d lexeme=\"%s\" (cadena sin cerrar al EOF)\n",
            TOKEN_ERROR, line_no, yytext);
    lexical_error_seen = 1;
}

{BAD_ID} {
    /* Un solo error lexico por lexema invalido (no se descompone en varios tokens). */
    fprintf(stderr,
            "LEXICAL_ERROR: token_id=<%d> line=%d lexeme=\"%s\" (identificador con caracteres invalidos)\n",
            TOKEN_ERROR, line_no, yytext);
    lexical_error_seen = 1;
    at_line_start = 0;
}

{ID} {
    at_line_start = 0;
    if (is_keyword(yytext)) {
        if (lexer_debug_mode) {
            emit_token_simple(TOKEN_KEYWORD, "KEYWORD", yytext);
        } else if (parser_mode) {
            return return_token(keyword_token(yytext), yytext);
        }
    } else {
        int idx = add_to_table(id_table, &id_count, yytext);
        if (lexer_debug_mode) {
            emit_token_ref(TOKEN_IDENTIFIER, "IDENTIFIER", yytext, idx);
        } else if (parser_mode) {
            yylval.i = idx;
            return TOKEN_IDENTIFIER;
        }
    }
}

{OPERATOR} {
    at_line_start = 0;
    if (lexer_debug_mode) {
        emit_token_simple(TOKEN_OPERATOR, "OPERATOR", yytext);
    } else if (parser_mode) {
        return return_token(TOKEN_OPERATOR, yytext);
    }
}

{DELIMITER} {
    at_line_start = 0;
    if (lexer_debug_mode) {
        emit_token_simple(TOKEN_DELIMITER, "DELIMITER", yytext);
    } else if (parser_mode) {
        if (strcmp(yytext, "->") == 0) {
            return return_token(TOKEN_DELIMITER, yytext);
        }
        if (strlen(yytext) == 1) {
            save_lexeme(yytext);
            return (unsigned char)yytext[0];
        }
        return return_token(TOKEN_DELIMITER, yytext);
    }
}

{WS_COUNT} {
    if (parser_mode) {
        int w = indent_width(yytext, yyleng);
        int tok = handle_indent(w);
        if (tok != 0) {
            return tok;
        }
    } else if (lexer_debug_mode && yyleng > 0) {
        emit_token_simple(900, "WS_COUNT", yytext);
    }
    at_line_start = 0;
}

{WHITESPACE} {
    /* descartado */
}

{NEWLINE} {
    line_no += (int)strlen(yytext);
    at_line_start = 1;
    if (lexer_debug_mode) {
        emit_token_simple(TOKEN_NEWLINE, "NEW_LINE", yytext);
    } else if (parser_mode) {
        return TOKEN_NEWLINE;
    }
}

. {
    fprintf(stderr,
            "LEXICAL_ERROR: token_id=<%d> line=%d lexeme=\"%s\"\n",
            TOKEN_ERROR, line_no, yytext);
    lexical_error_seen = 1;
    at_line_start = 0;
}

%%

static char *save_lexeme(const char *text) {
    strncpy(lexeme_buf, text ? text : "", MAX_LEXEME_LEN - 1);
    lexeme_buf[MAX_LEXEME_LEN - 1] = '\0';
    yylval.s = lexeme_buf;
    return lexeme_buf;
}

static int return_token(int tok, const char *lexeme) {
    save_lexeme(lexeme);
    return tok;
}

static int push_pending(int tok) {
    if (pending_count >= (int)(sizeof(pending_tokens) / sizeof(pending_tokens[0]))) {
        return -1;
    }
    pending_tokens[pending_count++] = tok;
    return 0;
}

static int pop_pending(void) {
    if (pending_count == 0) {
        return 0;
    }
    return pending_tokens[--pending_count];
}

static int indent_width(const char *text, int len) {
    int i;
    int w = 0;
    for (i = 0; i < len; ++i) {
        if (text[i] == ' ') {
            w++;
        } else if (text[i] == '\t') {
            w += 4;
        }
    }
    return w;
}

static int handle_indent(int width) {
    int top = indent_stack[indent_depth - 1];
    if (width > top) {
        if (indent_depth >= (int)(sizeof(indent_stack) / sizeof(indent_stack[0]))) {
            return TOKEN_ERROR;
        }
        indent_stack[indent_depth++] = width;
        return TOKEN_INDENT;
    }
    if (width < top) {
        while (indent_depth > 1 && indent_stack[indent_depth - 1] > width) {
            indent_depth--;
            push_pending(TOKEN_DEDENT);
        }
        if (indent_stack[indent_depth - 1] != width) {
            fprintf(stderr,
                    "SYNTAX_ERROR: line=%d near='indent' message='Indentacion inconsistente'\n",
                    line_no);
            return TOKEN_ERROR;
        }
        return pop_pending();
    }
    return 0;
}

static int keyword_token(const char *lex) {
    if (!strcmp(lex, "def")) return KW_DEF;
    if (!strcmp(lex, "return")) return KW_RETURN;
    if (!strcmp(lex, "if")) return KW_IF;
    if (!strcmp(lex, "elif")) return KW_ELIF;
    if (!strcmp(lex, "else")) return KW_ELSE;
    if (!strcmp(lex, "while")) return KW_WHILE;
    if (!strcmp(lex, "for")) return KW_FOR;
    if (!strcmp(lex, "in")) return KW_IN;
    if (!strcmp(lex, "import")) return KW_IMPORT;
    if (!strcmp(lex, "as")) return KW_AS;
    if (!strcmp(lex, "pass")) return KW_PASS;
    if (!strcmp(lex, "None")) return KW_NONE;
    if (!strcmp(lex, "True")) return KW_TRUE;
    if (!strcmp(lex, "False")) return KW_FALSE;
    if (!strcmp(lex, "break")) return KW_BREAK;
    if (!strcmp(lex, "continue")) return KW_CONTINUE;
    if (!strcmp(lex, "and")) return KW_AND;
    if (!strcmp(lex, "or")) return KW_OR;
    if (!strcmp(lex, "not")) return KW_NOT;
    return TOKEN_KEYWORD;
}

static int is_keyword(const char *lex) {
    static const char *keywords[] = {
        "import", "as", "None", "True", "def", "return", "if", "else", "while", "for", "in",
        "False", "elif", "switch", "and", "or", "not", "is", "break", "continue", "pass",
        "lambda", "class", "with", "try", "except", "finally", "raise", "yield", "del",
        "global", "nonlocal", "assert", "from"
    };
    int i;
    int n = (int)(sizeof(keywords) / sizeof(keywords[0]));
    for (i = 0; i < n; ++i) {
        if (strcmp(lex, keywords[i]) == 0) {
            return 1;
        }
    }
    return 0;
}

static int add_to_table(SymbolEntry *table, int *count, const char *lexeme) {
    int i;
    for (i = 0; i < *count; ++i) {
        if (strcmp(table[i].lexeme, lexeme) == 0) {
            return i + 1;
        }
    }
    if (*count >= MAX_SYMBOLS) {
        fprintf(stderr, "ERROR: symbol table overflow\n");
        exit(1);
    }
    strncpy(table[*count].lexeme, lexeme, MAX_LEXEME_LEN - 1);
    table[*count].lexeme[MAX_LEXEME_LEN - 1] = '\0';
    (*count)++;
    return *count;
}

static void emit_token_simple(int token_id, const char *token_name, const char *lexeme) {
    printf("<%d> %-12s %s\n", token_id, token_name, lexeme);
}

static void emit_token_ref(int token_id, const char *token_name, const char *lexeme, int index) {
    printf("<%d,%d> %-12s %s\n", token_id, index, token_name, lexeme);
}

void print_symbol_tables(void) {
    int i;
    printf("\n=== SYMBOL TABLE: IDENTIFIERS ===\n");
    for (i = 0; i < id_count; ++i) {
        printf("%d\t%s\n", i + 1, id_table[i].lexeme);
    }
    printf("\n=== SYMBOL TABLE: INTEGERS ===\n");
    for (i = 0; i < int_count; ++i) {
        printf("%d\t%s\n", i + 1, int_table[i].lexeme);
    }
    printf("\n=== SYMBOL TABLE: FLOATS ===\n");
    for (i = 0; i < float_count; ++i) {
        printf("%d\t%s\n", i + 1, float_table[i].lexeme);
    }
    printf("\n=== SYMBOL TABLE: STRINGS ===\n");
    for (i = 0; i < string_count; ++i) {
        printf("%d\t%s\n", i + 1, string_table[i].lexeme);
    }
}

const char *lexeme_by_id(int token, int index) {
    if (index <= 0) {
        return "";
    }
    if (token == 100 && index <= id_count) {
        return id_table[index - 1].lexeme;
    }
    if (token == 200 && index <= int_count) {
        return int_table[index - 1].lexeme;
    }
    if (token == 300 && index <= float_count) {
        return float_table[index - 1].lexeme;
    }
    if (token == 400 && index <= string_count) {
        return string_table[index - 1].lexeme;
    }
    return "";
}

void lexer_reset_for_parse(void) {
    indent_depth = 1;
    indent_stack[0] = 0;
    pending_count = 0;
    at_line_start = 1;
    lexical_error_seen = 0;
}

int yylex(void) {
    int tok;

    if (parser_mode) {
        tok = pop_pending();
        if (tok != 0) {
            return tok;
        }
    }

    tok = yyflexlex();

    if (parser_mode && tok == 0) {
        while (indent_depth > 1) {
            indent_depth--;
            push_pending(TOKEN_DEDENT);
        }
        tok = pop_pending();
        if (tok != 0) {
            return tok;
        }
    }
    return tok;
}
