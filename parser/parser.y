%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "tokens.h"
#include "symtab.h"
#include "lexer.h"

extern int yylex(void);
extern int yylineno;
void yyerror(const char *msg);
int yydebug = 0;

static char current_func[256] = "";
static int param_pos_counter = 0;
static int triton_decorator_pending = 0;
static int parse_ok = 0;

static const char *id_text(int idx) {
    return lexeme_by_id(100, idx);
}

static const char *int_text(int idx) {
    return lexeme_by_id(200, idx);
}

static const char *float_text(int idx) {
    return lexeme_by_id(300, idx);
}

static const char *str_text(int idx) {
    return lexeme_by_id(400, idx);
}

static int delim_is(const char *s, const char *ch) {
    return s && ch && strcmp(s, ch) == 0;
}
%}

%define parse.error verbose
%union {
    char *s;
    int i;
}

%token <i> TOKEN_IDENTIFIER 100
%token <i> TOKEN_INTEGER 200
%token <i> TOKEN_FLOAT 300
%token <i> TOKEN_STRING 400
%token <s> TOKEN_OPERATOR 500
%token <s> TOKEN_DELIMITER 600
%token <s> TOKEN_KEYWORD 101
%token TOKEN_COMMENT 700
%token TOKEN_NEWLINE 950
%token TOKEN_INDENT 910
%token TOKEN_DEDENT 911
%token KW_DEF KW_RETURN KW_IF KW_ELIF KW_ELSE KW_WHILE KW_FOR KW_IN
%token KW_IMPORT KW_AS KW_PASS KW_NONE KW_TRUE KW_FALSE
%token KW_BREAK KW_CONTINUE KW_AND KW_OR KW_NOT

%type <i> expr param_list param_list_opt param unary_expr call_expr opt_expr subscript
%type <s> opt_as import_name

%left TOKEN_NEWLINE
%left KW_OR
%left KW_AND
%nonassoc KW_NOT
%left TOKEN_OPERATOR
%nonassoc KW_ELIF
%nonassoc KW_ELSE

%start program

%%

program
    : opt_newlines top_block opt_newlines
      { parse_ok = 1; }
    ;

opt_newlines
    : /* empty */
    | opt_newlines TOKEN_NEWLINE
    ;

top_block
    : /* empty */
    | top_block top_line
    ;

top_line
    : stmt
    | stmt TOKEN_NEWLINE
    ;

stmt
    : import_stmt
    | def_stmt
    | assign_stmt
    | if_stmt
    | while_stmt
    | for_stmt
    | return_stmt
    | pass_stmt
    | expr_stmt
    ;

import_stmt
    : KW_IMPORT import_name opt_as
      {
          symtab_add_import($2, $3 ? $3 : "", line_no);
      }
    ;

import_name
    : TOKEN_IDENTIFIER
      {
          $$ = strdup(id_text($1));
      }
    | import_name '.' TOKEN_IDENTIFIER
      {
          size_t len = strlen($1) + strlen(id_text($3)) + 2;
          char *buf = (char *)malloc(len);
          snprintf(buf, len, "%s.%s", $1, id_text($3));
          free($1);
          $$ = buf;
      }
    ;

opt_as
    : /* empty */ { $$ = NULL; }
    | KW_AS TOKEN_IDENTIFIER { $$ = (char *)id_text($2); }
    ;

triton_decorator
    : '@' TOKEN_IDENTIFIER '.' TOKEN_IDENTIFIER
      {
          if (strcmp(id_text($2), "triton") == 0 && strcmp(id_text($4), "jit") == 0) {
              triton_decorator_pending = 1;
          }
      }
    ;

def_stmt
    : opt_triton_decorator KW_DEF TOKEN_IDENTIFIER
      {
          strncpy(current_func, id_text($3), sizeof(current_func) - 1);
          current_func[sizeof(current_func) - 1] = '\0';
          param_pos_counter = 0;
      }
      '(' param_list_opt ')' ':'
      {
          symtab_add_function(current_func, line_no, $6, triton_decorator_pending);
          triton_decorator_pending = 0;
      }
      suite
    ;

opt_triton_decorator
    : /* empty */
    | triton_decorator opt_newlines
    ;

param_list_opt
    : /* empty */ { $$ = 0; }
    | param_list { $$ = $1; }
    ;

param_list
    : param
      { $$ = 1; }
    | param_list ',' param
      { $$ = $1 + 1; }
    ;

param
    : TOKEN_IDENTIFIER
      {
          symtab_add_param(current_func, id_text($1), param_pos_counter++, "", line_no);
          $$ = 1;
      }
    | TOKEN_IDENTIFIER ':' expr
      {
          symtab_add_param(current_func, id_text($1), param_pos_counter++, "", line_no);
          $$ = 1;
      }
    ;

suite
    : simple_stmt
    | opt_newlines TOKEN_INDENT block_body TOKEN_DEDENT
    ;

block_body
    : /* empty */
    | block_body block_stmt
    ;

block_stmt
    : stmt
    | block_body TOKEN_NEWLINE
    | block_body TOKEN_NEWLINE stmt
    ;

simple_stmt
    : stmt
    ;

assign_stmt
    : TOKEN_IDENTIFIER TOKEN_OPERATOR expr
      {
          if (delim_is($2, "=")) {
              symtab_add_variable(id_text($1), line_no, current_func[0] ? current_func : "global");
          }
      }
    ;

if_stmt
    : KW_IF expr ':' suite elif_parts else_part
    ;

elif_parts
    : /* empty */
    | elif_parts KW_ELIF expr ':' suite
    ;

else_part
    : /* empty */
    | KW_ELSE ':' suite
    ;

while_stmt
    : KW_WHILE expr ':' suite
    ;

for_stmt
    : KW_FOR TOKEN_IDENTIFIER KW_IN expr ':' suite
    ;

return_stmt
    : KW_RETURN expr
    | KW_RETURN
    ;

pass_stmt
    : KW_PASS
    ;

expr_stmt
    : expr
    ;

expr
    : TOKEN_INTEGER { $$ = $1; }
    | TOKEN_FLOAT { $$ = $1; }
    | TOKEN_STRING { $$ = $1; }
    | TOKEN_IDENTIFIER { $$ = $1; }
    | TOKEN_IDENTIFIER member_chain { $$ = $1; }
    | KW_NONE { $$ = 0; }
    | KW_TRUE { $$ = 0; }
    | KW_FALSE { $$ = 0; }
    | expr TOKEN_OPERATOR expr { $$ = 0; }
    | expr TOKEN_DELIMITER expr { $$ = 0; }
    | '(' arg_list_opt ')' { $$ = 0; }
    | '[' expr ']' { $$ = $2; }
    | '[' expr ':' expr ']' { $$ = 0; }
    | '[' expr ':' expr ',' expr ']' { $$ = 0; }
    | expr '[' subscript_list ']' { $$ = 0; }
    | call_expr { $$ = 0; }
    | unary_expr { $$ = $1; }
    ;

opt_expr
    : /* empty */ { $$ = 0; }
    | expr { $$ = $1; }
    ;

subscript_list
    : subscript
    | subscript_list ',' subscript
    ;

subscript
    : expr { $$ = $1; }
    | KW_NONE { $$ = 0; }
    | ':' opt_expr { $$ = 0; }
    | opt_expr ':' opt_expr { $$ = 0; }
    | opt_expr ':' opt_expr ':' opt_expr { $$ = 0; }
    ;

unary_expr
    : TOKEN_OPERATOR expr { $$ = $2; }
    ;

member_chain
    : '.' TOKEN_IDENTIFIER
    | member_chain '.' TOKEN_IDENTIFIER
    | TOKEN_DELIMITER TOKEN_IDENTIFIER
    | member_chain TOKEN_DELIMITER TOKEN_IDENTIFIER
    ;

call_expr
    : TOKEN_IDENTIFIER '(' arg_list_opt ')' { $$ = 0; }
    | TOKEN_IDENTIFIER member_chain '(' arg_list_opt ')' { $$ = 0; }
    | TOKEN_IDENTIFIER '(' ')' { $$ = 0; }
    ;

arg_list_opt
    : /* empty */
    | arg_list
    ;

arg_list
    : arg
    | arg_list ',' arg
    ;

arg
    : expr
    | TOKEN_IDENTIFIER '=' expr
    ;

%%

void yyerror(const char *msg) {
    fprintf(stderr, "SYNTAX_ERROR: line=%d near='' message='%s'\n", line_no, msg);
}

int yyparse_started(void) {
    parser_mode = 1;
    lexer_reset_for_parse();
    symtab_reset();
    return 0;
}
