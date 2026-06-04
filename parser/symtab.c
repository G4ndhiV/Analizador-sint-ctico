#include "symtab.h"

#include <stdio.h>
#include <string.h>

#define MAX_FUNCS   256
#define MAX_PARAMS  1024
#define MAX_VARS    1024
#define MAX_IMPORTS 64

static FuncEntry funcs[MAX_FUNCS];
static int func_count;

static ParamEntry params[MAX_PARAMS];
static int param_count;

static VarEntry vars[MAX_VARS];
static int var_count;

static ImportEntry imports[MAX_IMPORTS];
static int import_count;

static char current_scope[64] = "global";

static void copy_str(char *dst, size_t n, const char *src) {
    if (!src) {
        dst[0] = '\0';
        return;
    }
    strncpy(dst, src, n - 1);
    dst[n - 1] = '\0';
}

void symtab_reset(void) {
    func_count = 0;
    param_count = 0;
    var_count = 0;
    import_count = 0;
    copy_str(current_scope, sizeof(current_scope), "global");
}

void symtab_set_scope(const char *scope) {
    copy_str(current_scope, sizeof(current_scope), scope ? scope : "global");
}

void symtab_add_import(const char *module, const char *alias, int line) {
    if (import_count >= MAX_IMPORTS) {
        return;
    }
    copy_str(imports[import_count].module, sizeof(imports[import_count].module), module);
    copy_str(imports[import_count].alias, sizeof(imports[import_count].alias), alias);
    imports[import_count].line = line;
    import_count++;
}

void symtab_add_function(const char *name, int line, int arity, int is_triton_jit) {
    if (func_count >= MAX_FUNCS) {
        return;
    }
    copy_str(funcs[func_count].name, sizeof(funcs[func_count].name), name);
    funcs[func_count].line = line;
    funcs[func_count].arity = arity;
    funcs[func_count].is_triton_jit = is_triton_jit;
    func_count++;
    symtab_set_scope(name);
}

void symtab_add_param(const char *func, const char *name, int pos, const char *annot, int line) {
    if (param_count >= MAX_PARAMS) {
        return;
    }
    copy_str(params[param_count].func, sizeof(params[param_count].func), func);
    copy_str(params[param_count].name, sizeof(params[param_count].name), name);
    copy_str(params[param_count].annot, sizeof(params[param_count].annot), annot);
    params[param_count].position = pos;
    params[param_count].line = line;
    param_count++;
}

void symtab_add_variable(const char *name, int line, const char *scope) {
    int i;
    for (i = 0; i < var_count; ++i) {
        if (strcmp(vars[i].name, name) == 0 && strcmp(vars[i].scope, scope ? scope : current_scope) == 0) {
            return;
        }
    }
    if (var_count >= MAX_VARS) {
        return;
    }
    copy_str(vars[var_count].name, sizeof(vars[var_count].name), name);
    copy_str(vars[var_count].scope, sizeof(vars[var_count].scope), scope ? scope : current_scope);
    vars[var_count].line = line;
    var_count++;
}

void symtab_print(void) {
    int i;
    printf("\n=== PARSER SYMBOL TABLE ===\n");
    printf("--- IMPORTS ---\n");
    for (i = 0; i < import_count; ++i) {
        printf("%d\tline=%d\tmodule=%s\talias=%s\n", i + 1, imports[i].line, imports[i].module,
               imports[i].alias[0] ? imports[i].alias : "-");
    }
    printf("--- FUNCTIONS ---\n");
    for (i = 0; i < func_count; ++i) {
        printf("%d\tline=%d\tname=%s\tarity=%d\ttriton_jit=%d\n", i + 1, funcs[i].line, funcs[i].name,
               funcs[i].arity, funcs[i].is_triton_jit);
    }
    printf("--- PARAMETERS ---\n");
    for (i = 0; i < param_count; ++i) {
        printf("%d\tline=%d\tfunc=%s\tparam=%s\tpos=%d\tannot=%s\n", i + 1, params[i].line,
               params[i].func, params[i].name, params[i].position,
               params[i].annot[0] ? params[i].annot : "-");
    }
    printf("--- VARIABLES ---\n");
    for (i = 0; i < var_count; ++i) {
        printf("%d\tline=%d\tscope=%s\tname=%s\n", i + 1, vars[i].line, vars[i].scope, vars[i].name);
    }
}
