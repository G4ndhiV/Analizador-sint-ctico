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
static int fresh_line = 0;
static int line_has_ws = 0;
static int paren_depth = 0;
static int bracket_depth = 0;
static int indent_kind[256];
static int peek_token = 0;
static int peek_valid = 0;
static int peek_fresh_line = 0;
static int token_is_fresh = 0;
static YYSTYPE peek_yylval;
static char lexeme_buf[MAX_LEXEME_LEN];
static int deferred_tok = 0;
static YYSTYPE deferred_yylval;
static int lex_prev = 0;
static int lex_prev2 = 0;
static int lex_prev_line = 0;
static int saw_assign_this_line = 0;

#define INDENT_KIND_UNKNOWN (-1)
#define INDENT_KIND_SPACES 0
#define INDENT_KIND_TABS 1

static void track_delim_char(char ch) {
    if (ch == '(') {
        paren_depth++;
    } else if (ch == ')' && paren_depth > 0) {
        paren_depth--;
    } else if (ch == '[') {
        bracket_depth++;
    } else if (ch == ']' && bracket_depth > 0) {
        bracket_depth--;
    }
}

static int is_keyword(const char *lex);
static int add_to_table(SymbolEntry *table, int *count, const char *lexeme);
static void emit_token_simple(int token_id, const char *token_name, const char *lexeme);
static void emit_token_ref(int token_id, const char *token_name, const char *lexeme, int index);
void print_symbol_tables(void);
static char *save_lexeme(const char *text);
static int push_pending(int tok);
static int pop_pending(void);
static int indent_width(const char *text, int len);
static int indent_line_kind(const char *text, int len);
static int handle_indent(int width, int kind);
static int keyword_token(const char *lex);
static int return_token(int tok, const char *lexeme);
static int bol_dedent_token(void);
static void defer_token(int tok);
static void lexer_note_token(int tok);
static int lexer_multistmt_error(int tok);

extern YYSTYPE yylval;
extern int syntax_error_seen;

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
HEXINT          0[xX][0-9a-fA-F]+
INCOMPLETE_HEX  0[xX]
BADHEX          0[xX][0-9a-fA-F]*[^0-9a-fA-F \t\n]
OCTINT          0[oO][0-7]+
BADOCT          0[oO][0-9]+
BININT          0[bB][01]+
BADBIN          0[bB][01]*[2-9a-zA-Z_]+|0[bB][^01 \t\n]
INT             {DIGIT}+
FLOAT           ({DIGIT}*\.{DIGIT}+([eE][+-]?{DIGIT}+)?|{DIGIT}+[eE][+-]?{DIGIT}+)
BADFLOAT        {DIGIT}+\.{DIGIT}+\.|{DIGIT}+\.$|{DIGIT}+\.[eE][^0-9+\-]|{DIGIT}+[eE][^0-9+\-]
SPACESHIP       "<=>"
STRICT_EQ       "==="
STRICT_NE       "!=="
STRING          \"[^\"\n]*\"|\'[^\'\n]*\'
STRING_UNCLOSED_LINE  \"[^\"\n]*\n|\'[^\'\n]*\n
STRING_UNCLOSED_EOF   \"[^\"\n]*|\'[^\'\n]*
COMMENT         \#[^)\n]*
WS_COUNT        ^[ \t]+
WHITESPACE      [ \t]+
NEWLINE         \n+
OPERATOR        "**"|"=="|"!="|"<="|">="|"//"|"<<"|">>"|"+="|"-="|"*="|"/="|"%="|[+\-*/%&^<>|~]
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

{HEXINT} {
    int idx = add_to_table(int_table, &int_count, yytext);
    at_line_start = 0;
    if (lexer_debug_mode) {
        emit_token_ref(TOKEN_INTEGER, "INTEGER", yytext, idx);
    } else if (parser_mode) {
        yylval.i = idx;
        return TOKEN_INTEGER;
    }
}

{OCTINT} {
    int idx = add_to_table(int_table, &int_count, yytext);
    at_line_start = 0;
    if (lexer_debug_mode) {
        emit_token_ref(TOKEN_INTEGER, "INTEGER", yytext, idx);
    } else if (parser_mode) {
        yylval.i = idx;
        return TOKEN_INTEGER;
    }
}

{BININT} {
    int idx = add_to_table(int_table, &int_count, yytext);
    at_line_start = 0;
    if (lexer_debug_mode) {
        emit_token_ref(TOKEN_INTEGER, "INTEGER", yytext, idx);
    } else if (parser_mode) {
        yylval.i = idx;
        return TOKEN_INTEGER;
    }
}

{INCOMPLETE_HEX}|{BADHEX}|{BADOCT}|{BADBIN}|{BADFLOAT}|{SPACESHIP}|{STRICT_EQ}|{STRICT_NE} {
    fprintf(stderr,
            "LEXICAL_ERROR: token_id=<%d> line=%d lexeme=\"%s\" (literal u operador invalido)\n",
            TOKEN_ERROR, line_no, yytext);
    lexical_error_seen = 1;
    at_line_start = 0;
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
    if (parser_mode) {
        int ded = bol_dedent_token();
        if (ded != 0) {
            if (is_keyword(yytext)) {
                defer_token(return_token(keyword_token(yytext), yytext));
            } else {
                yylval.i = add_to_table(id_table, &id_count, yytext);
                defer_token(TOKEN_IDENTIFIER);
            }
            return ded;
        }
    }
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

"=" {
    at_line_start = 0;
    if (lexer_debug_mode) {
        emit_token_simple(TOKEN_ASSIGN, "ASSIGN", yytext);
    } else if (parser_mode) {
        saw_assign_this_line = 1;
        return return_token(TOKEN_ASSIGN, yytext);
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
            if (parser_mode) {
                track_delim_char(yytext[0]);
            }
            return (unsigned char)yytext[0];
        }
        return return_token(TOKEN_DELIMITER, yytext);
    }
}

{WS_COUNT} {
    line_has_ws = 1;
    if (parser_mode && at_line_start) {
        fresh_line = 1;
    }
    if (parser_mode && (paren_depth > 0 || bracket_depth > 0)) {
        /* Dentro de () o []: sangria es espacio, no bloque Python. */
        at_line_start = 0;
    } else if (parser_mode) {
        int w = indent_width(yytext, yyleng);
        int kind = indent_line_kind(yytext, yyleng);
        int tok = handle_indent(w, kind);
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
    fresh_line = 1;
    line_has_ws = 0;
    saw_assign_this_line = 0;
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

static void defer_token(int tok) {
    deferred_tok = tok;
    deferred_yylval = yylval;
}

static int lexer_multistmt_error(int tok) {
    if (!parser_mode || line_no != lex_prev_line) {
        return 0;
    }
    if (tok == KW_PASS && lex_prev == KW_PASS) {
        return 1;
    }
    if (tok == TOKEN_INTEGER && lex_prev == KW_PASS) {
        return 1;
    }
    if (tok == TOKEN_INTEGER && lex_prev == TOKEN_INTEGER && lex_prev2 == KW_RETURN) {
        return 1;
    }
    if (tok == TOKEN_IDENTIFIER && lex_prev == TOKEN_INTEGER && saw_assign_this_line) {
        return 1;
    }
    return 0;
}

static void lexer_note_token(int tok) {
    if (!parser_mode || tok == 0 || tok == TOKEN_NEWLINE || tok == TOKEN_COMMENT ||
        tok == TOKEN_INDENT || tok == TOKEN_DEDENT) {
        return;
    }
    lex_prev2 = lex_prev;
    lex_prev = tok;
    lex_prev_line = line_no;
}

static int bol_dedent_token(void) {
    if (!parser_mode || !at_line_start || line_has_ws || indent_depth <= 1) {
        return 0;
    }
    if (paren_depth > 0 || bracket_depth > 0) {
        return 0;
    }
    return handle_indent(0, INDENT_KIND_UNKNOWN);
}

int lexer_peek_fresh_line(void) {
    if (peek_valid) {
        return peek_fresh_line;
    }
    return fresh_line || token_is_fresh;
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

static int indent_line_kind(const char *text, int len) {
    int i;
    int has_space = 0;
    int has_tab = 0;
    for (i = 0; i < len; ++i) {
        if (text[i] == ' ') {
            has_space = 1;
        } else if (text[i] == '\t') {
            has_tab = 1;
        }
    }
    if (has_tab && has_space) {
        return -2;
    }
    if (has_tab) {
        return INDENT_KIND_TABS;
    }
    if (has_space) {
        return INDENT_KIND_SPACES;
    }
    return INDENT_KIND_UNKNOWN;
}

static int handle_indent(int width, int kind) {
    int top = indent_stack[indent_depth - 1];
    if (kind == -2) {
        fprintf(stderr,
                "SYNTAX_ERROR: line=%d near='indent' message='Mezcla de tabuladores y espacios en indentacion'\n",
                line_no);
        lexical_error_seen = 1;
        return TOKEN_ERROR;
    }
    if (width > top) {
        if (indent_depth >= (int)(sizeof(indent_stack) / sizeof(indent_stack[0]))) {
            return TOKEN_ERROR;
        }
        if (kind != INDENT_KIND_UNKNOWN) {
            if (indent_kind[indent_depth] == INDENT_KIND_UNKNOWN) {
                indent_kind[indent_depth] = kind;
            } else if (indent_kind[indent_depth] != kind) {
                fprintf(stderr,
                        "SYNTAX_ERROR: line=%d near='indent' message='Mezcla de tabuladores y espacios en indentacion'\n",
                        line_no);
                lexical_error_seen = 1;
                return TOKEN_ERROR;
            }
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
    if (kind != INDENT_KIND_UNKNOWN) {
        if (indent_kind[indent_depth - 1] == INDENT_KIND_UNKNOWN) {
            indent_kind[indent_depth - 1] = kind;
        } else if (indent_kind[indent_depth - 1] != kind) {
            fprintf(stderr,
                    "SYNTAX_ERROR: line=%d near='indent' message='Mezcla de tabuladores y espacios en indentacion'\n",
                    line_no);
            lexical_error_seen = 1;
            return TOKEN_ERROR;
        }
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
    if (!strcmp(lex, "is")) return KW_IS;
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

int yypeek(void) {
    if (!peek_valid) {
        peek_token = yylex();
        peek_yylval = yylval;
        peek_fresh_line = token_is_fresh;
        peek_valid = 1;
    }
    return peek_token;
}

void yyunput(int tok) {
    peek_token = tok;
    peek_yylval = yylval;
    peek_valid = 1;
}

void lexer_reset_for_parse(void) {
    int i;
    indent_depth = 1;
    indent_stack[0] = 0;
    for (i = 0; i < (int)(sizeof(indent_kind) / sizeof(indent_kind[0])); ++i) {
        indent_kind[i] = INDENT_KIND_UNKNOWN;
    }
    pending_count = 0;
    peek_valid = 0;
    peek_token = 0;
    peek_fresh_line = 0;
    fresh_line = 0;
    token_is_fresh = 0;
    deferred_tok = 0;
    lex_prev = 0;
    lex_prev2 = 0;
    lex_prev_line = 0;
    saw_assign_this_line = 0;
    line_has_ws = 0;
    at_line_start = 1;
    paren_depth = 0;
    bracket_depth = 0;
    lexical_error_seen = 0;
}

int yylex(void) {
    int tok;

    if (peek_valid) {
        peek_valid = 0;
        yylval = peek_yylval;
        return peek_token;
    }

    if (parser_mode) {
        tok = pop_pending();
        if (tok == TOKEN_DEDENT && !at_line_start && !fresh_line) {
            push_pending(tok);
            tok = 0;
        }
        if (tok != 0) {
            return tok;
        }
    }

    if (deferred_tok != 0) {
        tok = deferred_tok;
        yylval = deferred_yylval;
        deferred_tok = 0;
        return tok;
    }

    tok = yyflexlex();

    if (parser_mode && tok != 0 && tok != TOKEN_NEWLINE && tok != TOKEN_COMMENT &&
        tok != TOKEN_INDENT && tok != TOKEN_DEDENT) {
        if (lexer_multistmt_error(tok)) {
            fprintf(stderr,
                    "SYNTAX_ERROR: line=%d near='' message='multiples sentencias en la misma linea'\n",
                    line_no);
            syntax_error_seen = 1;
        }
        token_is_fresh = fresh_line;
        fresh_line = 0;
        lexer_note_token(tok);
    } else {
        token_is_fresh = 0;
    }

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
