/*
 * Archivo : parser/symtab.h
 * Proposito: Interfaz de la tabla de simbolos del analizador sintactico.
 *            Define los tipos de entrada (funcion, parametro, variable,
 *            importacion) y declara las funciones de insercion y consulta
 *            que las acciones semanticas de parser.y invocan durante el
 *            analisis de cada construccion del lenguaje .tri.
 * Relacion : Incluido por parser/parser.y (acciones semanticas) y por
 *            parser/symtab.c (implementacion). La informacion recopilada
 *            aqui se imprime al final de un parse exitoso mediante
 *            symtab_print(), llamada desde src/driver.c.
 */

#ifndef SYMTAB_H
#define SYMTAB_H

/*
 * FuncEntry: registro de una funcion definida con 'def'.
 *   name        -- nombre del identificador de la funcion.
 *   line        -- linea del archivo fuente donde aparece 'def'.
 *   arity       -- numero de parametros formales.
 *   is_triton_jit -- 1 si la funcion esta decorada con @triton.jit, 0 si no.
 */
typedef struct {
    char name[256];
    int  line;
    int  arity;
    int  is_triton_jit;
} FuncEntry;

/*
 * ParamEntry: registro de un parametro formal de una funcion.
 *   func     -- nombre de la funcion a la que pertenece el parametro.
 *   name     -- nombre del parametro.
 *   position -- posicion ordinal (0-based) en la lista de parametros.
 *   annot    -- anotacion de tipo si existe (p.ej. "tl.constexpr"), vacio si no.
 *   line     -- linea donde aparece el parametro en la definicion.
 */
typedef struct {
    char func[256];
    char name[256];
    int  position;
    char annot[256];
    int  line;
} ParamEntry;

/*
 * VarEntry: registro de una variable asignada dentro de una funcion o global.
 *   name  -- nombre de la variable.
 *   line  -- linea de la primera asignacion.
 *   scope -- nombre de la funcion que contiene la variable, o "global".
 */
typedef struct {
    char name[256];
    int  line;
    char scope[64];
} VarEntry;

/*
 * ImportEntry: registro de una sentencia 'import' o 'import ... as ...'.
 *   module -- nombre completo del modulo (puede ser "triton.language").
 *   alias  -- alias introducido con 'as' (vacio si no hay).
 *   line   -- linea del import en el archivo fuente.
 */
typedef struct {
    char module[256];
    char alias[256];
    int  line;
} ImportEntry;

/* -- API de la tabla de simbolos -------------------------------------------- */

/* symtab_reset: vacia todas las tablas; debe llamarse antes de cada parse.   */
void symtab_reset(void);

/* symtab_add_import: registra una sentencia import con su modulo y alias.    */
void symtab_add_import(const char *module, const char *alias, int line);

/*
 * symtab_add_function: registra una funcion nueva y establece el ambito
 * actual (current_scope) a su nombre para que los parametros y variables
 * subsiguientes se asocien correctamente.
 */
void symtab_add_function(const char *name, int line, int arity, int is_triton_jit);

/* symtab_add_param: anade un parametro a la funcion actualmente en scope.   */
void symtab_add_param(const char *func, const char *name, int pos,
                      const char *annot, int line);

/*
 * symtab_add_variable: inserta una variable si no existe ya en el mismo
 * scope; las redeclaraciones (asignaciones repetidas) se ignoran.
 */
void symtab_add_variable(const char *name, int line, const char *scope);

/* symtab_set_scope: cambia manualmente el ambito activo (uso interno).       */
void symtab_set_scope(const char *scope);

/* symtab_print: imprime todas las entradas de las cuatro tablas por stdout.  */
void symtab_print(void);

#endif /* SYMTAB_H */
