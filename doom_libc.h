// =====================================================================
// doom_libc.h - Bare-Metal Definitions for Doom Engine
// =====================================================================
#ifndef DOOM_LIBC_H
#define DOOM_LIBC_H

#define NULL ((void*)0)
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2

typedef unsigned int size_t;
typedef __builtin_va_list va_list;

// --- Custom In-Memory VFS File Structure ---
typedef struct {
    unsigned char* data;
    unsigned int size;
    int pos;
} FILE;

extern FILE* stderr;
extern FILE* stdout;
extern int errno;

// --- Standard Library Stubs & String Utils ---
void exit(int code);
void* sys_brk(void* addr);
void* malloc(size_t size);
void free(void* ptr);
void* calloc(size_t nmemb, size_t size);
void* realloc(void *ptr, size_t size);

FILE* fopen(const char* filename, const char* mode);
size_t fread(void* ptr, size_t size, size_t count, FILE* stream);
int fseek(FILE* stream, long offset, int whence);
long ftell(FILE* stream);
int fclose(FILE* stream);
size_t fwrite(const void* ptr, size_t size, size_t count, FILE* stream);
int fflush(FILE *stream);
int mkdir(const char *pathname, int mode);
int remove(const char *pathname);
int rename(const char *oldpath, const char *newpath);

int abs(int j);
double fabs(double x);
int tolower(int c);
int toupper(int c);
int atoi(const char *str);
char* itoa(int num, char* str, int base);
long int strtol(const char *nptr, char **endptr, int base);
double strtod(const char *nptr, char **endptr);

int strcasecmp(const char *s1, const char *s2);
int strncasecmp(const char *s1, const char *s2, size_t n);
void* memset(void* ptr, int value, size_t num);
void* memcpy(void* dest, const void* src, size_t num);
char* strcpy(char *dest, const char *src);
char* strncpy(char *dest, const char *src, size_t n);
char* strcat(char *dest, const char *src);
char* strncat(char *dest, const char *src, size_t n);
int strcmp(const char *s1, const char *s2);
int strncmp(const char *s1, const char *s2, size_t n);
size_t strlen(const char* str);
char* strdup(const char *s);
char* strchr(const char *s, int c);
char* strrchr(const char *s, int c);
char* strstr(const char *haystack, const char *needle);
char* getenv(const char *name);

int vsnprintf(char *str, size_t size, const char *format, va_list args);
int snprintf(char *str, size_t size, const char *format, ...);
int printf(const char *format, ...);
int puts(const char *s);
int putc(int c, FILE *stream);
int fprintf(FILE *stream, const char *format, ...);
int vfprintf(FILE *stream, const char *format, va_list args);
int system(const char *command);
void print(const char* str);

unsigned short** __ctype_b_loc(void);

// --- PlutoGL Graphics Context ---
typedef struct {
    unsigned int* buffer;
    int width;
    int height;
    int x;
    int y;
    int id;
} PlutoContext;

void pluto_init(PlutoContext* ctx, int w, int h);
void pluto_swap_buffers();
void DG_SetWindowTitle(const char *title);

// --- Hardware Syscalls ---
void* sys_create_window(int w, int h, int* out_id);
void sys_update_window();
void sys_set_window_pos(int id, int x, int y);
void sys_yield();
int sys_get_key_state(int scancode);
unsigned int sys_get_ticks();
void sys_sleep(unsigned int ms);
void* sys_fat32_load(const char* filename, unsigned int* out_size);

// --- Application Entry Point ---
int main(int argc, char** argv);
void _start();

#endif