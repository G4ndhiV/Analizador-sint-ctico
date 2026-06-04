#ifndef LEXER_H
#define LEXER_H

#include <stdio.h>

extern int line_no;
extern int lexer_debug_mode;
extern int parser_mode;
extern int lexical_error_seen;
extern FILE *yyin;

void print_symbol_tables(void);
void lexer_reset_for_parse(void);
const char *lexeme_by_id(int token, int index);

#endif
