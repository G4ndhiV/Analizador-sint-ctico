#ifndef SYMTAB_H
#define SYMTAB_H

typedef struct {
    char name[256];
    int line;
    int arity;
    int is_triton_jit;
} FuncEntry;

typedef struct {
    char func[256];
    char name[256];
    int position;
    char annot[256];
    int line;
} ParamEntry;

typedef struct {
    char name[256];
    int line;
    char scope[64];
} VarEntry;

typedef struct {
    char module[256];
    char alias[256];
    int line;
} ImportEntry;

void symtab_reset(void);
void symtab_add_import(const char *module, const char *alias, int line);
void symtab_add_function(const char *name, int line, int arity, int is_triton_jit);
void symtab_add_param(const char *func, const char *name, int pos, const char *annot, int line);
void symtab_add_variable(const char *name, int line, const char *scope);
void symtab_set_scope(const char *scope);
void symtab_print(void);

#endif
