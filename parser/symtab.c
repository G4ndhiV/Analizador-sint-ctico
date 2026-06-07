/*
 * Archivo : parser/symtab.c
 * Proposito: Implementacion de la tabla de simbolos del analizador sintactico.
 *            Mantiene cuatro arreglos estaticos para almacenar registros de
 *            imports, funciones, parametros y variables descubiertos durante
 *            el recorrido de la gramatica en parser.y. Las entradas se insertan
 *            desde las acciones semanticas de yacc (reglas import_stmt,
 *            def_stmt, param y assign_stmt/ident_stmt).
 * Relacion : Implementa la interfaz declarada en parser/symtab.h.
 *            Es compilado junto con parser.y y src/driver.c para formar el
 *            ejecutable build/triton_parser.
 */

#include "symtab.h"

#include <stdio.h>
#include <string.h>

/* Capacidades maximas de cada tabla (ajustables sin cambiar la interfaz).    */
#define MAX_FUNCS   256   /* Maximo de funciones por archivo .tri              */
#define MAX_PARAMS  1024  /* Maximo de parametros acumulados de todas las func */
#define MAX_VARS    1024  /* Maximo de variables (una entrada por nombre+scope)*/
#define MAX_IMPORTS 64    /* Maximo de sentencias import por archivo            */

/* -- Arreglos estaticos de las tablas ---------------------------------------- */
static FuncEntry   funcs[MAX_FUNCS];
static int         func_count;

static ParamEntry  params[MAX_PARAMS];
static int         param_count;

static VarEntry    vars[MAX_VARS];
static int         var_count;

static ImportEntry imports[MAX_IMPORTS];
static int         import_count;

/* Ambito activo: nombre de la ultima funcion procesada o "global".            *
 * Se actualiza al entrar a un def_stmt y se usa como scope de las variables.  */
static char current_scope[64] = "global";

/*
 * copy_str: copia src en dst con longitud maxima n, garantizando terminacion
 * con '\0'. Maneja src == NULL copiando una cadena vacia.
 */
static void copy_str(char *dst, size_t n, const char *src) {
    if (!src) {
        dst[0] = '\0';
        return;
    }
    strncpy(dst, src, n - 1);
    dst[n - 1] = '\0';
}

/*
 * symtab_reset: reinicia todos los contadores a 0 y el ambito a "global".
 * Debe llamarse antes de cada llamada a yyparse() para que un nuevo archivo
 * comience con tablas limpias.
 */
void symtab_reset(void) {
    func_count   = 0;
    param_count  = 0;
    var_count    = 0;
    import_count = 0;
    copy_str(current_scope, sizeof(current_scope), "global");
}

/*
 * symtab_set_scope: cambia el ambito activo al nombre dado.
 * Recibe NULL o puntero vacio como sinonimo de "global".
 */
void symtab_set_scope(const char *scope) {
    copy_str(current_scope, sizeof(current_scope), scope ? scope : "global");
}

/*
 * symtab_add_import: registra la sentencia "import <module> [as <alias>]".
 * Si la tabla esta llena, la entrada se descarta silenciosamente.
 */
void symtab_add_import(const char *module, const char *alias, int line) {
    if (import_count >= MAX_IMPORTS) {
        return;
    }
    copy_str(imports[import_count].module, sizeof(imports[import_count].module), module);
    copy_str(imports[import_count].alias,  sizeof(imports[import_count].alias),  alias);
    imports[import_count].line = line;
    import_count++;
}

/*
 * symtab_add_function: registra la funcion recien definida con 'def'.
 * Despues de la insercion, actualiza current_scope al nombre de la funcion
 * para que los parametros que siguen queden asociados a ella.
 * El campo is_triton_jit indica si el decorador @triton.jit fue detectado
 * antes del def (gestionado por triton_decorator_pending en parser.y).
 */
void symtab_add_function(const char *name, int line, int arity, int is_triton_jit) {
    if (func_count >= MAX_FUNCS) {
        return;
    }
    copy_str(funcs[func_count].name, sizeof(funcs[func_count].name), name);
    funcs[func_count].line          = line;
    funcs[func_count].arity         = arity;
    funcs[func_count].is_triton_jit = is_triton_jit;
    func_count++;
    symtab_set_scope(name);  /* Nuevas variables perteneceran a esta funcion */
}

/*
 * symtab_add_param: inserta un parametro formal asociado a la funcion dada.
 * pos es la posicion 0-based dentro de la lista de parametros.
 * annot almacena la anotacion de tipo si el parametro tiene la forma "id : expr".
 */
void symtab_add_param(const char *func, const char *name, int pos,
                      const char *annot, int line) {
    if (param_count >= MAX_PARAMS) {
        return;
    }
    copy_str(params[param_count].func,  sizeof(params[param_count].func),  func);
    copy_str(params[param_count].name,  sizeof(params[param_count].name),  name);
    copy_str(params[param_count].annot, sizeof(params[param_count].annot), annot);
    params[param_count].position = pos;
    params[param_count].line     = line;
    param_count++;
}

/*
 * symtab_add_variable: registra una variable si no existe ya una entrada con
 * el mismo nombre y scope. Esto evita entradas duplicadas cuando la misma
 * variable se asigna varias veces en el mismo cuerpo de funcion.
 * scope puede ser NULL, en cuyo caso se usa current_scope.
 */
void symtab_add_variable(const char *name, int line, const char *scope) {
    int i;
    const char *sc = scope ? scope : current_scope;

    /* Busqueda lineal: si ya existe la variable en el mismo ambito, no se duplica */
    for (i = 0; i < var_count; ++i) {
        if (strcmp(vars[i].name, name) == 0 &&
            strcmp(vars[i].scope, sc)   == 0) {
            return;
        }
    }
    if (var_count >= MAX_VARS) {
        return;
    }
    copy_str(vars[var_count].name,  sizeof(vars[var_count].name),  name);
    copy_str(vars[var_count].scope, sizeof(vars[var_count].scope), sc);
    vars[var_count].line = line;
    var_count++;
}

/*
 * symtab_print: imprime por stdout todas las entradas de las cuatro tablas
 * en formato tabular legible. Llamada por driver.c tras PARSE_OK.
 * El formato es compatible con la salida esperada por los casos de prueba.
 */
void symtab_print(void) {
    int i;
    printf("\n=== PARSER SYMBOL TABLE ===\n");

    printf("--- IMPORTS ---\n");
    for (i = 0; i < import_count; ++i) {
        printf("%d\tline=%d\tmodule=%s\talias=%s\n",
               i + 1,
               imports[i].line,
               imports[i].module,
               imports[i].alias[0] ? imports[i].alias : "-");
    }

    printf("--- FUNCTIONS ---\n");
    for (i = 0; i < func_count; ++i) {
        printf("%d\tline=%d\tname=%s\tarity=%d\ttriton_jit=%d\n",
               i + 1,
               funcs[i].line,
               funcs[i].name,
               funcs[i].arity,
               funcs[i].is_triton_jit);
    }

    printf("--- PARAMETERS ---\n");
    for (i = 0; i < param_count; ++i) {
        printf("%d\tline=%d\tfunc=%s\tparam=%s\tpos=%d\tannot=%s\n",
               i + 1,
               params[i].line,
               params[i].func,
               params[i].name,
               params[i].position,
               params[i].annot[0] ? params[i].annot : "-");
    }

    printf("--- VARIABLES ---\n");
    for (i = 0; i < var_count; ++i) {
        printf("%d\tline=%d\tscope=%s\tname=%s\n",
               i + 1,
               vars[i].line,
               vars[i].scope,
               vars[i].name);
    }
}
