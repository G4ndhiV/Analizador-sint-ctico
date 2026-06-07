/*
 * Archivo : parser/parser.y
 * Proposito: Especificacion yacc/Bison del analizador sintactico para kernels
 *            Triton GPU escritos en archivos .tri. Define la gramatica libre de
 *            contexto (CFG) del subconjunto del lenguaje Python/Triton reconocido
 *            por el compilador del Equipo 11, con acciones semanticas que
 *            actualizan la tabla de simbolos (symtab) y reportan errores.
 *
 * Estructura del archivo (secciones yacc):
 *   Sec.1 Preambulo C  -- includes, variables globales y funciones auxiliares.
 *   Sec.2 Declaraciones -- %union, %token, %type, precedencias y simbolo inicial.
 *   Sec.3 Reglas       -- producciones de la CFG con acciones semanticas.
 *   Sec.4 Codigo C     -- implementacion de validate_stmt_line_end y yyerror.
 *
 * Relacion : Compilado con Bison para generar y.tab.c y y.tab.h.
 *            Incluye lexer/lexer.h para acceder a las funciones del scanner,
 *            parser/symtab.h para la tabla de simbolos e include/tokens.h
 *            para los IDs de token compartidos.
 */

%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "tokens.h"   /* IDs de token compartidos (DOC_*) y MAX_LEXEME_LEN   */
#include "symtab.h"   /* API de la tabla de simbolos del parser               */
#include "lexer.h"    /* API del scanner: line_no, yypeek, lexeme_by_id, ...   */

/* Funciones generadas por Bison y Flex respectivamente */
extern int yylex(void);
extern int yypeek(void);
extern int yylineno;  /* Contador de lineas de Flex (respaldo; se usa line_no)*/

/* Declarada al final del archivo; llamada por Bison en caso de error.        */
void yyerror(const char *msg);

/* yydebug: si se pone a 1 (flag -d en driver.c), Bison traza las acciones.  */
int yydebug = 0;

/* syntax_error_seen: bandera global que se activa en yyerror(); revisada por *
 * driver.c para devolver codigo de salida 1 en caso de error sintactico.     */
int syntax_error_seen = 0;

/* -- Variables de contexto para acciones semanticas ------------------------ */

/* Nombre de la funcion que se esta analizando actualmente; se establece en
 * def_stmt al leer el TOKEN_IDENTIFIER del nombre de funcion, y se pasa a
 * symtab_add_function() y symtab_add_param().                                */
static char current_func[256] = "";

/* Contador de posicion de parametros (0-based); se reinicia a 0 en cada def.*/
static int param_pos_counter = 0;

/* Flag que indica si se encontro @triton.jit antes del 'def' actual.         *
 * Se activa en la accion de triton_decorator y se consume en def_stmt.       */
static int triton_decorator_pending = 0;

/* parse_ok: se pone a 1 al reducir la regla 'program' sin errores.           *
 * No se usa externamente; el estado de exito lo indica syntax_error_seen.   */
static int parse_ok = 0;

/* -- Funciones auxiliares para recuperar lexemas de las tablas ------------ */

/* id_text: retorna el nombre del identificador almacenado en el indice idx.  */
static const char *id_text(int idx) {
    return lexeme_by_id(100, idx);
}

/* int_text: retorna el literal entero almacenado en el indice idx.           */
static const char *int_text(int idx) {
    return lexeme_by_id(200, idx);
}

/* float_text: retorna el literal flotante almacenado en el indice idx.       */
static const char *float_text(int idx) {
    return lexeme_by_id(300, idx);
}

/* str_text: retorna el literal cadena almacenado en el indice idx.           */
static const char *str_text(int idx) {
    return lexeme_by_id(400, idx);
}

/*
 * delim_is: compara el lexema del token actual (s) con el caracter esperado
 * (ch). Devuelve 1 si coinciden; 0 en caso contrario. Se usa en las acciones
 * de expr e ident_suffix para detectar el '=' de asignacion que no debe
 * aparecer dentro de una expresion (solo como TOKEN_ASSIGN).
 */
static int delim_is(const char *s, const char *ch) {
    return s && ch && strcmp(s, ch) == 0;
}

/* Prototipo interno; implementacion al final del archivo (Sec.4).               */
static void validate_stmt_line_end(void);

%}

/* -- Sec.2: Declaraciones yacc ----------------------------------------------- */

/* parse.error verbose: Bison genera mensajes de error detallados con el      *
 * token inesperado y los tokens esperados en ese punto de la gramatica.      */
%define parse.error verbose

/*
 * %union: define el tipo semantico YYSTYPE. Los tokens y no-terminales
 * pueden transportar un entero (i, para indices de tabla lexica) o un
 * puntero a char (s, para lexemas de operadores y delimitadores).
 */
%union {
    char *s;  /* Lexema de TOKEN_OPERATOR, TOKEN_ASSIGN, TOKEN_DELIMITER */
    int   i;  /* Indice 1-based en tabla lexica (ID, INT, FLOAT, STRING)  */
}

/* -- Declaracion de tokens terminales ------------------------------------ */
/* Los numeros coinciden con los IDs del Cuadro 1 del reporte lexico.        */
%token <i> TOKEN_IDENTIFIER 100  /* Identificadores validos                  */
%token <i> TOKEN_INTEGER    200  /* Literales enteros                        */
%token <i> TOKEN_FLOAT      300  /* Literales de punto flotante              */
%token <i> TOKEN_STRING     400  /* Cadenas literales                        */
%token <s> TOKEN_OPERATOR   500  /* Operadores (+, -, **, ==, <=, ...)         */
%token <s> TOKEN_ASSIGN          /* El operador '=' de asignacion            */
%token <s> TOKEN_DELIMITER  600  /* Delimitadores: ( ) [ ] { } , . : ; @ -> */
%token <s> TOKEN_KEYWORD    101  /* Palabras reservadas no mapeadas a KW_*   */
%token TOKEN_COMMENT        700  /* Comentarios (#...); ignorados en el parser */
%token TOKEN_NEWLINE        950  /* Salto de linea \n                        */
%token TOKEN_INDENT         910  /* Apertura de bloque indentado             */
%token TOKEN_DEDENT         911  /* Cierre de bloque indentado               */

/* Palabras reservadas con tokens propios para mejor control en la gramatica  */
%token KW_DEF KW_RETURN KW_IF KW_ELIF KW_ELSE KW_WHILE KW_FOR KW_IN
%token KW_IMPORT KW_AS KW_PASS KW_NONE KW_TRUE KW_FALSE
%token KW_BREAK KW_CONTINUE KW_AND KW_OR KW_NOT KW_IS

/* -- Tipos de no-terminales ---------------------------------------------- */
/* Los no-terminales que producen o propagan valores usan <i> o <s>.          */
%type <i> expr param_list param_list_opt param unary_expr call_expr opt_expr
%type <i> subscript list_expr ident_suffix ident_op
%type <s> opt_as import_name

/* -- Declaraciones de precedencia y asociatividad ------------------------ */
/* Las reglas se listan de menor a mayor precedencia (de arriba a abajo).     *
 * Resuelven conflictos shift/reduce en expresiones y en la construccion      *
 * "dangling else" (KW_IF / KW_ELIF / KW_ELSE).                              */
%left  TOKEN_NEWLINE        /* Menor precedencia: separa sentencias           */
%left  KW_OR                /* Operador logico OR                             */
%left  KW_AND               /* Operador logico AND                            */
%nonassoc KW_NOT            /* Operador unario NOT (no asociativo)            */
%left  TOKEN_OPERATOR       /* Operadores aritmeticos/relacionales            */
%nonassoc KW_ELIF           /* Resuelve ambiguedad en cadenas if-elif-else    */
%nonassoc KW_ELSE           /* 'else' se asocia al 'if' mas cercano           */
%right KW_IF                /* Expresion condicional: expr IF cond ELSE expr  */

/* Simbolo inicial de la gramatica */
%start program

/* -- Sec.3: Reglas de la gramatica (CFG) ------------------------------------ */
%%

/*
 * program: simbolo inicial.
 * Un programa .tri es una secuencia opcional de newlines, seguida del bloque
 * superior (imports y defs) y posibles newlines al final.
 * La accion fija parse_ok = 1 para indicar que la reduccion fue exitosa.
 */
program
    : opt_newlines top_block opt_newlines
      { parse_ok = 1; }
    ;

/*
 * opt_newlines: cero o mas saltos de linea consecutivos.
 * Produccion auxiliar que permite lineas en blanco entre declaraciones y al
 * inicio/fin del archivo sin generar errores sintacticos.
 */
opt_newlines
    : /* vacio */
    | opt_newlines TOKEN_NEWLINE
    ;

/*
 * top_block: secuencia de declaraciones de nivel superior.
 * Solo se permiten imports y definiciones de funcion ('def') en el nivel 0
 * de indentacion; sentencias sueltas generarian un error en la practica
 * porque el lexer emitiria DEDENT antes de ellas.
 */
top_block
    : /* vacio */
    | top_block opt_newlines top_line
    ;

/*
 * top_line: una declaracion de nivel superior.
 * Puede ser un import o un def, con newline opcional al final.
 */
top_line
    : import_stmt
    | import_stmt TOKEN_NEWLINE
    | def_stmt
    | def_stmt TOKEN_NEWLINE
    ;

/*
 * stmt: cualquier sentencia valida dentro de un bloque.
 * Cubre todos los tipos de sentencias del subconjunto Triton: imports,
 * definiciones de funcion anidadas, asignaciones, expresiones, control de
 * flujo y la sentencia nula 'pass'.
 */
stmt
    : import_stmt
    | def_stmt
    | assign_stmt
    | ident_stmt
    | if_stmt
    | while_stmt
    | for_stmt
    | return_stmt
    | pass_stmt
    | expr_stmt
    ;

/*
 * import_stmt: sentencia de importacion "import <modulo> [as <alias>]".
 * La accion semantica inserta el modulo y su alias opcional en symtab.
 * Soporta modulos compuestos (triton.language) mediante la regla import_name.
 */
import_stmt
    : KW_IMPORT import_name opt_as
      {
          symtab_add_import($2, $3 ? $3 : "", line_no);
      }
    ;

/*
 * import_name: nombre del modulo, posiblemente compuesto con puntos.
 * Se construye concatenando segmentos con '.' para producir "triton.language".
 * El string resultante se aloja con malloc; la accion libera el parcial anterior.
 */
import_name
    : TOKEN_IDENTIFIER
      {
          $$ = strdup(id_text($1));  /* Nombre simple: "triton" */
      }
    | import_name '.' TOKEN_IDENTIFIER
      {
          /* Nombre compuesto: concatena "triton" + "." + "language" */
          size_t len = strlen($1) + strlen(id_text($3)) + 2;
          char *buf = (char *)malloc(len);
          snprintf(buf, len, "%s.%s", $1, id_text($3));
          free($1);   /* Liberar el segmento parcial acumulado anteriormente */
          $$ = buf;
      }
    ;

/*
 * opt_as: clausula "as <alias>" opcional.
 * Produce NULL si no hay alias, o el lexema del identificador alias.
 */
opt_as
    : /* vacio */ { $$ = NULL; }
    | KW_AS TOKEN_IDENTIFIER { $$ = (char *)id_text($2); }
    ;

/*
 * triton_decorator: reconoce "@triton.jit" en la linea anterior al def.
 * Solo activa triton_decorator_pending si la forma es exactamente
 * @triton.jit; otros decoradores se aceptan pero no marcan el flag.
 */
triton_decorator
    : '@' TOKEN_IDENTIFIER '.' TOKEN_IDENTIFIER
      {
          if (strcmp(id_text($2), "triton") == 0 &&
              strcmp(id_text($4), "jit")    == 0) {
              triton_decorator_pending = 1;
          }
      }
    ;

/*
 * def_stmt: definicion de funcion con sintaxis Python/Triton.
 * Flujo de acciones semanticas:
 *   1. Al leer el nombre (TOKEN_IDENTIFIER): se guarda en current_func y
 *      se reinicia param_pos_counter para la nueva lista de parametros.
 *   2. Despues del ')':
 *      - se registra la funcion en symtab con aridad = numero de params ($3)
 *        y el flag triton_jit tomado de triton_decorator_pending.
 *      - se limpia triton_decorator_pending para la siguiente definicion.
 *   3. suite: cuerpo de la funcion (bloque indentado o sentencia simple).
 */
def_stmt
    : opt_triton_decorator KW_DEF TOKEN_IDENTIFIER
      {
          strncpy(current_func, id_text($3), sizeof(current_func) - 1);
          current_func[sizeof(current_func) - 1] = '\0';
          param_pos_counter = 0;  /* Reiniciar contador de posicion de parametros */
      }
      '(' opt_newlines param_list_opt opt_newlines ')' ':'
      {
          /* Registrar la funcion ya con su aridad (param_list_opt devuelve el count) */
          symtab_add_function(current_func, line_no, $3, triton_decorator_pending);
          triton_decorator_pending = 0;  /* Consumir el flag del decorador */
      }
      suite
    ;

/*
 * opt_triton_decorator: el decorador @triton.jit es opcional.
 * opt_newlines despues del decorador permite que aparezca en su propia linea.
 */
opt_triton_decorator
    : /* vacio */
    | triton_decorator opt_newlines
    ;

/*
 * param_list_opt: lista de parametros formales opcional.
 * Retorna 0 si la lista esta vacia, o el conteo de parametros si hay al menos uno.
 * Este valor es el que def_stmt pasa a symtab_add_function como aridad.
 */
param_list_opt
    : /* vacio */ { $$ = 0; }
    | param_list  { $$ = $1; }
    ;

/*
 * param_list: uno o mas parametros separados por comas.
 * La coma puede ir seguida de opt_newlines para permitir parametros en
 * lineas separadas (estilo Python multi-linea entre parentesis).
 * Retorna la cuenta acumulada de parametros procesados.
 */
param_list
    : param
      { $$ = 1; }
    | param_list opt_newlines ',' opt_newlines param
      { $$ = $1 + 1; }  /* Incrementar el contador por cada parametro adicional */
    ;

/*
 * param: un parametro formal, con o sin anotacion de tipo.
 * Forma simple:   "nombre"
 * Forma anotada:  "nombre : tipo_expr" (p. ej. "n_elements : tl.constexpr")
 * En ambos casos se inserta el parametro en symtab y se avanza param_pos_counter.
 * Nota: la anotacion se guarda como cadena vacia (simplificacion; el tipo
 * exacto requeriria evaluar la expresion, fuera del alcance sintactico).
 */
param
    : TOKEN_IDENTIFIER
      {
          symtab_add_param(current_func, id_text($1), param_pos_counter++, "", line_no);
          $$ = 1;
      }
    | TOKEN_IDENTIFIER ':' opt_newlines expr
      {
          symtab_add_param(current_func, id_text($1), param_pos_counter++, "", line_no);
          $$ = 1;
      }
    ;

/*
 * suite: cuerpo de una estructura de control (def, if, while, for).
 * Hay dos formas:
 *   - simple_stmt: una sola sentencia en la misma linea que el ':'.
 *   - bloque indentado: delimitado por TOKEN_INDENT y TOKEN_DEDENT, con
 *     cero o mas sentencias (block_body) separadas por newlines opcionales.
 * Los tokens INDENT/DEDENT son generados por el lexer al detectar cambios
 * en la columna de inicio de linea (pila de indentacion).
 */
suite
    : simple_stmt
    | opt_newlines TOKEN_INDENT block_body TOKEN_DEDENT
    ;

/*
 * block_body: cuerpo de un bloque indentado.
 * Puede estar vacio (funcion con solo 'pass') o contener multiples sentencias.
 */
block_body
    : /* vacio */
    | block_body opt_newlines block_stmt
    ;

/*
 * block_stmt: sentencia dentro de un bloque indentado.
 * La version sin TOKEN_NEWLINE llama a validate_stmt_line_end() para
 * detectar multiples sentencias ilegales en la misma linea sin separador.
 */
block_stmt
    : stmt TOKEN_NEWLINE
    | stmt
      {
          validate_stmt_line_end();
      }
    ;

/*
 * simple_stmt: sentencia unica en la misma linea que el ':' (suite inline).
 */
simple_stmt
    : stmt
    ;

/*
 * assign_stmt: asignacion con anotacion de tipo "id : tipo = expr".
 * Esta forma es especifica del subconjunto Triton que usa anotaciones de tipo
 * en variables locales (p. ej. "offs_am: tl.tensor = ..."). La variable se
 * registra en symtab con el ambito de la funcion actual.
 */
assign_stmt
    : TOKEN_IDENTIFIER ':' expr TOKEN_ASSIGN expr
      {
          symtab_add_variable(id_text($1), line_no,
                              current_func[0] ? current_func : "global");
      }
    ;

/*
 * ident_stmt: sentencia que comienza con un identificador.
 * Cubre dos casos:
 *   - Asignacion simple "id = expr": ident_op retorna 1, se registra en symtab.
 *   - Expresion de identificador puro (llamada, acceso a atributo): ident_op
 *     retorna 0, no se registra (no es una nueva variable).
 */
ident_stmt
    : TOKEN_IDENTIFIER ident_op
      {
          if ($2) {
              symtab_add_variable(id_text($1), line_no,
                                  current_func[0] ? current_func : "global");
          }
      }
    ;

/*
 * ident_op: continuacion de una sentencia que comienza con identificador.
 *   TOKEN_ASSIGN expr -> asignacion (retorna 1, symtab registra la variable).
 *   ident_suffix      -> expresion sin asignacion (retorna 0, sin registro).
 */
ident_op
    : TOKEN_ASSIGN expr { $$ = 1; }
    | ident_suffix      { $$ = 0; }
    ;

/*
 * if_stmt: sentencia condicional con elif y else opcionales.
 * La ambiguedad del "dangling else" se resuelve con %nonassoc KW_ELIF y
 * %nonassoc KW_ELSE en la seccion de precedencias: cada else/elif se asocia
 * al if/elif mas cercano (comportamiento estandar de Python).
 */
if_stmt
    : KW_IF expr ':' suite elif_parts else_part
    ;

/* elif_parts: cero o mas clausulas "elif expr : suite" encadenadas. */
elif_parts
    : /* vacio */
    | elif_parts KW_ELIF expr ':' suite
    ;

/* else_part: clausula "else : suite" opcional al final del if. */
else_part
    : /* vacio */
    | KW_ELSE ':' suite
    ;

/* while_stmt: bucle "while expr : suite". */
while_stmt
    : KW_WHILE expr ':' suite
    ;

/*
 * for_stmt: iteracion "for id in expr : suite".
 * Solo se soporta la variable de iteracion simple (sin tuplas), suficiente
 * para los patrones "for i in range(...)" comunes en kernels Triton.
 */
for_stmt
    : KW_FOR TOKEN_IDENTIFIER KW_IN expr ':' suite
    ;

/*
 * return_stmt: retorno de funcion, con o sin valor.
 * La forma sin expresion corresponde a "return" en funciones void de Triton.
 */
return_stmt
    : KW_RETURN expr
    | KW_RETURN
    ;

/* pass_stmt: sentencia nula Python; valida en cualquier bloque. */
pass_stmt
    : KW_PASS
    ;

/* expr_stmt: una expresion usada como sentencia (p. ej. llamadas a funciones).*/
expr_stmt
    : expr
    ;

/*
 * ident_suffix: continuacion posible de un identificador en una expresion.
 * Maneja todos los sufijos que puede tener un identificador en Triton:
 *   - Acceso a atributo: ".attr" (member_chain)
 *   - Indexacion: "[subscript]"
 *   - Llamada: "(args)"
 *   - Operacion binaria: "op expr"
 *   - Identidad: "is expr"
 *   - Condicional inline: "if cond else alt"
 *   - Separador de expresiones: TOKEN_DELIMITER expr (p. ej. "," en tuplas)
 *   - Vacio: el identificador termina aqui
 *
 * La accion en TOKEN_OPERATOR verifica que '=' no aparezca como operador
 * dentro de una expresion (solo es valido como TOKEN_ASSIGN en asignaciones).
 */
ident_suffix
    : member_chain ident_suffix
    | '[' subscript_list ']' ident_suffix
    | '(' opt_newlines arg_list_opt opt_newlines ')' ident_suffix
    | TOKEN_OPERATOR opt_newlines expr
      {
          /* El '=' dentro de una expresion es siempre un error semantico */
          if (delim_is($1, "=")) {
              yyerror("asignacion invalida dentro de expresion");
          }
      }
    | KW_IS expr
    | KW_IF expr KW_ELSE expr %prec KW_ELSE   /* Expresion condicional ternaria */
    | TOKEN_DELIMITER opt_newlines expr
    | %empty
    ;

/*
 * expr: expresion del lenguaje Triton.
 * Cubre todos los tipos de valor que pueden aparecer en el lado derecho de
 * una asignacion, en condiciones de control de flujo y en argumentos:
 *   - Literales: entero, flotante, cadena, None, True, False.
 *   - Identificador con sufijo (acceso, llamada, indexacion, operacion).
 *   - Operacion binaria: expr OP expr (precedencias definidas en Sec.2).
 *   - Identidad: expr is expr (para "dtype is tl.float32").
 *   - Expresion condicional ternaria: expr if cond else alt.
 *   - Expresion separada por delimitador (coma en tuplas implicitas).
 *   - Expresion parentizada: (args).
 *   - Lista literal: [elementos].
 *   - Indexacion: expr[subscript].
 *   - Llamada explicita: call_expr.
 *   - Negacion/inversion unaria: unary_expr.
 *
 * La accion en TOKEN_OPERATOR verifica que '=' no sea usado como operador.
 */
expr
    : TOKEN_INTEGER   { $$ = $1; }
    | TOKEN_FLOAT     { $$ = $1; }
    | TOKEN_STRING    { $$ = $1; }
    | TOKEN_IDENTIFIER ident_suffix { $$ = $1; }
    | KW_NONE  { $$ = 0; }
    | KW_TRUE  { $$ = 0; }
    | KW_FALSE { $$ = 0; }
    | expr TOKEN_OPERATOR opt_newlines expr
      {
          if (delim_is($2, "=")) {
              yyerror("asignacion invalida dentro de expresion");
          }
          $$ = 0;
      }
    | expr KW_IS expr { $$ = 0; }                              /* "dtype is tl.float32" */
    | expr KW_IF expr KW_ELSE expr %prec KW_ELSE { $$ = 0; }  /* Condicional ternario   */
    | expr TOKEN_DELIMITER opt_newlines expr { $$ = 0; }       /* Coma entre expresiones */
    | '(' opt_newlines arg_list_opt opt_newlines ')' { $$ = 0; }
    | list_expr   { $$ = 0; }
    | expr '[' subscript_list ']' { $$ = 0; }
    | call_expr   { $$ = 0; }
    | unary_expr  { $$ = $1; }
    ;

/*
 * opt_expr: expresion opcional (puede estar vacia).
 * Usada en los limites de slices: "a[: , :]" donde algun extremo es vacio.
 */
opt_expr
    : /* vacio */ { $$ = 0; }
    | expr        { $$ = $1; }
    ;

/* subscript_list: uno o mas subscripts separados por coma (e.g. a[i, j]).   */
subscript_list
    : subscript
    | subscript_list ',' subscript
    ;

/*
 * subscript: un indice dentro de corchetes.
 * Soporta todas las formas de indexacion de tensores Triton:
 *   - expr           : indice simple (a[i])
 *   - None           : insercion de dimension (a[None, :])
 *   - : opt_expr     : slice desde el inicio (a[:n])
 *   - opt_expr : opt_expr     : slice basico (a[lo:hi])
 *   - opt_expr : opt_expr : opt_expr : slice con paso (a[lo:hi:step])
 */
subscript
    : expr            { $$ = $1; }
    | KW_NONE         { $$ = 0; }
    | ':' opt_expr    { $$ = 0; }
    | opt_expr ':' opt_expr { $$ = 0; }
    | opt_expr ':' opt_expr ':' opt_expr { $$ = 0; }
    ;

/*
 * unary_expr: expresion unaria prefija (negacion, NOT bit a bit).
 * Se rechazan explicitamente '*' y '/' como operadores unarios ya que
 * no tienen semantica definida en el subconjunto Triton del curso.
 */
unary_expr
    : TOKEN_OPERATOR expr
      {
          if (delim_is($1, "*") || delim_is($1, "/")) {
              yyerror("operador unario no permitido");
          }
          $$ = $2;
      }
    ;

/*
 * list_expr: lista literal entre corchetes "[elem, elem, ...]".
 * Los elementos se tratan como arg_list_opt (misma regla que los argumentos).
 */
list_expr
    : '[' opt_newlines arg_list_opt opt_newlines ']'
      { $$ = 0; }
    ;

/*
 * member_chain: cadena de accesos a atributos o delimitadores.
 * Cubre patrones como ".method", ".attr.method" y los delimitadores de
 * acceso con "->" que aparecen en anotaciones de retorno de funcion.
 */
member_chain
    : '.' opt_newlines TOKEN_IDENTIFIER
    | member_chain '.' opt_newlines TOKEN_IDENTIFIER
    | TOKEN_DELIMITER opt_newlines TOKEN_IDENTIFIER
    | member_chain TOKEN_DELIMITER opt_newlines TOKEN_IDENTIFIER
    ;

/*
 * call_expr: llamada a funcion o metodo.
 * Cubre cuatro formas comunes en kernels Triton:
 *   - f(args)                  : llamada simple
 *   - obj.method(args)         : llamada a metodo (con member_chain)
 *   - f()                      : llamada sin argumentos
 *   - call_expr.method(args)   : encadenamiento de llamadas
 */
call_expr
    : TOKEN_IDENTIFIER '(' opt_newlines arg_list_opt opt_newlines ')' { $$ = 0; }
    | TOKEN_IDENTIFIER member_chain '(' opt_newlines arg_list_opt opt_newlines ')' { $$ = 0; }
    | TOKEN_IDENTIFIER '(' opt_newlines ')' { $$ = 0; }
    | call_expr '.' TOKEN_IDENTIFIER '(' opt_newlines arg_list_opt opt_newlines ')' { $$ = 0; }
    ;

/* arg_list_opt: lista de argumentos de una llamada, opcional. */
arg_list_opt
    : /* vacio */
    | arg_list
    ;

/* arg_list: uno o mas argumentos separados por coma. */
arg_list
    : arg
    | arg_list ',' opt_newlines arg
    ;

/*
 * arg: un argumento de llamada.
 * Puede ser una expresion posicional o un argumento con nombre "key=valor",
 * que es el patron habitual en llamadas a tl.load(ptr, mask=mask, ...).
 */
arg
    : expr
    | TOKEN_IDENTIFIER TOKEN_ASSIGN opt_newlines expr  /* Argumento con nombre */
    ;

/* -- Sec.4: Codigo C auxiliar ------------------------------------------------ */
%%

/*
 * validate_stmt_line_end: verifica que no haya multiples sentencias en la
 * misma linea sin separador de newline entre ellas.
 *
 * Se llama desde block_stmt cuando una sentencia termina sin TOKEN_NEWLINE.
 * Usa yypeek() para ver el siguiente token sin consumirlo; si ese token puede
 * iniciar una sentencia nueva (keyword, literal), emite un error sintactico.
 *
 * Tokens que terminan legalmente sin newline: TOKEN_DEDENT, EOF (0),
 * TOKEN_NEWLINE. Cualquier otro token que pueda iniciar sentencia es invalido.
 *
 * Ejemplos detectados: "pass pass", "return 5 6", "x = 5 y = 6".
 */
static void validate_stmt_line_end(void) {
    int t = yypeek();

    /* Fin de bloque, fin de archivo o newline: todo correcto */
    if (t == TOKEN_DEDENT || t == 0 || t == TOKEN_NEWLINE) {
        return;
    }

    /* Tokens que pueden iniciar una nueva sentencia en la misma linea */
    switch (t) {
    case KW_PASS:
    case KW_RETURN:
    case KW_WHILE:
    case KW_FOR:
    case KW_IMPORT:
    case KW_DEF:
    case KW_ELIF:
    case KW_ELSE:
    case TOKEN_INTEGER:
    case TOKEN_FLOAT:
    case TOKEN_STRING:
        yyerror("multiples sentencias en la misma linea");
        break;
    default:
        break;
    }
}

/*
 * yyerror: funcion de reporte de errores requerida por Bison.
 * Activa la bandera global syntax_error_seen y escribe en stderr con el
 * formato esperado por los scripts de prueba:
 *   SYNTAX_ERROR: line=<n> near='' message='<msg>'
 */
void yyerror(const char *msg) {
    syntax_error_seen = 1;
    fprintf(stderr, "SYNTAX_ERROR: line=%d near='' message='%s'\n", line_no, msg);
}

/*
 * yyparse_started: funcion de inicializacion del parser (uso interno/pruebas).
 * Activa parser_mode, reinicia el estado del lexer y limpia symtab.
 * En produccion este mismo flujo lo ejecuta driver.c antes de llamar yyparse().
 */
int yyparse_started(void) {
    parser_mode = 1;
    lexer_reset_for_parse();
    symtab_reset();
    return 0;
}
