// =====================================================================
// doom_libc.c - The Ultimate Bare-Metal NoVa OS C Library for Doom
// =====================================================================
#include "doom_libc.h"

FILE* stderr = 0;
FILE* stdout = 0;
int errno = 0;

// =====================================================================
// OS ENTRY POINT
// =====================================================================
void _start() {
    char *argv[] = {"doom", NULL};
    main(1, argv);
    exit(0);
}

// =====================================================================
// NOVA OS HARDWARE SYSCALLS
// =====================================================================
void* sys_brk(void* addr) { void* r; asm volatile("int $0x80" : "=a"(r) : "a"(45), "b"(addr)); return r; }
void* malloc(size_t size) { void* r; asm volatile("int $0x80" : "=a"(r) : "a"(90), "b"(size)); return r; }
void free(void* ptr) { asm volatile("int $0x80" : : "a"(91), "b"(ptr)); }

// The Tab Expander! Translates \t into spaces so the NoVa terminal doesn't break layout!
void print(const char* str) { 
    char buf[1024];
    int i = 0;
    while (*str && i < 1000) {
        if (*str == '\t') {
            buf[i++] = ' '; buf[i++] = ' '; buf[i++] = ' '; buf[i++] = ' ';
        } else if (*str != '\r') { // Ignore carriage returns to stop weird line breaks
            buf[i++] = *str;
        }
        str++;
    }
    buf[i] = '\0';
    asm volatile("int $0x80" : : "a"(4), "b"(1), "c"(buf), "d"(i));
}

// --- NORMAL KERNEL EXIT ---
// Tells NoVa OS to clean up the window and return to the Shell!
void exit(int code) { 
    asm volatile("int $0x80" : : "a"(1), "b"(code)); 
    while(1); 
}

void* sys_create_window(int w, int h, int* out_id) {
    void* ptr; int id;
    asm volatile("int $0x80" : "=a"(ptr), "=b"(id) : "a"(100), "b"(w), "c"(h));
    if (out_id) *out_id = id; return ptr;
}
void sys_update_window() { asm volatile("int $0x80" : : "a"(101)); }
void sys_set_window_pos(int id, int x, int y) { asm volatile("int $0x80" : : "a"(102), "b"(x), "c"(y), "d"(id)); }
void sys_yield() { asm volatile("int $0x80" : : "a"(106)); }
int sys_get_key_state(int scancode) { int s; asm volatile("int $0x80" : "=a"(s) : "a"(108), "b"(scancode)); return s; }
unsigned int sys_get_ticks() { unsigned int t; asm volatile("int $0x80" : "=a"(t) : "a"(109)); return t; }
void sys_sleep(unsigned int ms) { asm volatile("int $0x80" : : "a"(110), "b"(ms)); }

void* sys_fat32_load(const char* filename, unsigned int* out_size) {
    void* ret_ptr; unsigned int ret_size;
    asm volatile(
        "mov $111, %%eax\n" "mov %2, %%ebx\n" "int $0x80\n"
        "mov %%eax, %0\n" "mov %%ecx, %1\n"
        : "=r" (ret_ptr), "=r" (ret_size) : "r" (filename) : "eax", "ebx", "ecx", "memory"
    );
    if (out_size) *out_size = ret_size;
    return ret_ptr;
}

// =====================================================================
// BARE-METAL VIRTUAL FILE SYSTEM (RAM-Backed)
// =====================================================================
FILE* fopen(const char* filename, const char* mode) {
    const char* name = filename;
    const char* slash = strrchr(name, '/');
    if (slash) name = slash + 1;
    slash = strrchr(name, '\\');
    if (slash) name = slash + 1;

    unsigned int size = 0;
    void* data = sys_fat32_load(name, &size);
    if (!data || size == 0) {
        print("VFS ERROR: Kernel could not find file: ");
        print(name);
        print("\n");
        return 0; 
    }
    
    FILE* f = (FILE*)malloc(sizeof(FILE));
    f->data = (unsigned char*)data;
    f->size = size;
    f->pos = 0;
    return f;
}

size_t fread(void* ptr, size_t size, size_t count, FILE* stream) {
    if (!stream || !stream->data || !ptr) return 0;
    size_t total_bytes = size * count;
    if (stream->pos >= stream->size) return 0;
    if (stream->pos + total_bytes > stream->size) total_bytes = stream->size - stream->pos;
    if (total_bytes <= 0) return 0;
    
    memcpy(ptr, stream->data + stream->pos, total_bytes);
    stream->pos += total_bytes;
    return total_bytes / size;
}

int fseek(FILE* stream, long offset, int whence) {
    if (!stream) return -1;
    if (whence == SEEK_SET) stream->pos = offset;
    else if (whence == SEEK_CUR) stream->pos += offset;
    else if (whence == SEEK_END) stream->pos = stream->size + offset;
    
    if (stream->pos < 0) stream->pos = 0;
    if (stream->pos > stream->size) stream->pos = stream->size;
    return 0;
}

long ftell(FILE* stream) { return stream ? stream->pos : 0; }

int fclose(FILE* stream) {
    if (!stream) return 0;
    free(stream->data); 
    free(stream);
    return 0;
}

size_t fwrite(const void* ptr, size_t size, size_t count, FILE* stream) { return count; }
int fflush(FILE *stream) { return 0; }
int mkdir(const char *pathname, int mode) { return 0; }
int remove(const char *pathname) { return -1; }
int rename(const char *oldpath, const char *newpath) { return -1; }

// =====================================================================
// MATH & STRING FUNCTIONS
// =====================================================================
int abs(int j) { return j < 0 ? -j : j; }
double fabs(double x) { return x < 0.0 ? -x : x; }

int tolower(int c) { return (c >= 'A' && c <= 'Z') ? c + 32 : c; }
int toupper(int c) { return (c >= 'a' && c <= 'z') ? c - 32 : c; }

int strcasecmp(const char *s1, const char *s2) {
    while (1) {
        int c1 = tolower((unsigned char)*s1);
        int c2 = tolower((unsigned char)*s2);
        if (c1 != c2) return c1 - c2;
        if (c1 == '\0') return 0;
        s1++; s2++;
    }
}

int strncasecmp(const char *s1, const char *s2, size_t n) {
    while (n > 0) {
        int c1 = tolower((unsigned char)*s1);
        int c2 = tolower((unsigned char)*s2);
        if (c1 != c2) return c1 - c2;
        if (c1 == '\0') return 0;
        s1++; s2++; n--;
    }
    return 0;
}

void* memset(void* ptr, int value, size_t num) {
    unsigned char* p = (unsigned char*)ptr;
    while(num--) *p++ = (unsigned char)value;
    return ptr;
}

void* memcpy(void* dest, const void* src, size_t num) {
    unsigned char* d = (unsigned char*)dest;
    const unsigned char* s = (const unsigned char*)src;
    while(num--) *d++ = *s++;
    return dest;
}

void* calloc(size_t nmemb, size_t size) {
    size_t total = nmemb * size;
    void *ptr = malloc(total);
    if (ptr) memset(ptr, 0, total);
    return ptr;
}

void* realloc(void *ptr, size_t size) {
    if (size == 0) { free(ptr); return 0; }
    if (!ptr) return malloc(size);
    
    unsigned int* header = (unsigned int*)((unsigned char*)ptr - 16);
    unsigned int old_data_size = header[0] - 16; 
    
    void *new_ptr = malloc(size);
    if (new_ptr) {
        size_t copy_size = (old_data_size < size) ? old_data_size : size;
        memcpy(new_ptr, ptr, copy_size); 
        free(ptr);
    }
    return new_ptr;
}

char* strcpy(char *dest, const char *src) {
    char *d = dest;
    while ((*d++ = *src++));
    return dest;
}

char* strncpy(char *dest, const char *src, size_t n) {
    char *d = dest;
    while (n > 0 && *src) { *d++ = *src++; n--; }
    while (n > 0) { *d++ = '\0'; n--; }
    return dest;
}

char* strcat(char *dest, const char *src) {
    char *d = dest;
    while (*d) d++;
    while ((*d++ = *src++));
    return dest;
}

char* strncat(char *dest, const char *src, size_t n) {
    char *d = dest;
    while (*d) d++;
    while (n-- > 0 && *src) *d++ = *src++;
    *d = '\0';
    return dest;
}

int strcmp(const char *s1, const char *s2) {
    while (*s1 && (*s1 == *s2)) { s1++; s2++; }
    return *(const unsigned char*)s1 - *(const unsigned char*)s2;
}

int strncmp(const char *s1, const char *s2, size_t n) {
    while (n && *s1 && (*s1 == *s2)) { ++s1; ++s2; --n; }
    if (n == 0) return 0;
    return *(const unsigned char*)s1 - *(const unsigned char*)s2;
}

size_t strlen(const char* str) {
    size_t len = 0;
    while(str[len]) len++;
    return len;
}

char* strdup(const char *s) {
    size_t len = strlen(s) + 1;
    char *d = malloc(len);
    if (d) memcpy(d, s, len);
    return d;
}

char* strchr(const char *s, int c) {
    while (*s != (char)c) { if (!*s++) return 0; }
    return (char *)s;
}

char* strrchr(const char *s, int c) {
    const char* ret = 0;
    do { if (*s == (char)c) ret = s; } while (*s++);
    return (char*)ret;
}

char* strstr(const char *haystack, const char *needle) {
    size_t n = strlen(needle);
    while (*haystack) {
        if (!strncmp(haystack, needle, n)) return (char *)haystack;
        haystack++;
    }
    return 0;
}

int atoi(const char *str) {
    int res = 0;
    for (int i = 0; str[i] != '\0'; ++i) res = res * 10 + str[i] - '0';
    return res;
}

long int strtol(const char *nptr, char **endptr, int base) { return atoi(nptr); }
double strtod(const char *nptr, char **endptr) { return 0.0; }

char* itoa(int num, char* str, int base) {
    int i = 0; int isNegative = 0;
    if (num == 0) { str[i++] = '0'; str[i] = '\0'; return str; }
    if (num < 0 && base == 10) { isNegative = 1; num = -num; }
    while (num != 0) {
        int rem = num % base;
        str[i++] = (rem > 9) ? (rem - 10) + 'a' : rem + '0';
        num = num / base;
    }
    if (isNegative) str[i++] = '-';
    str[i] = '\0';
    int start = 0; int end = i - 1;
    while (start < end) {
        char temp = str[start]; str[start] = str[end]; str[end] = temp;
        start++; end--;
    }
    return str;
}

char* getenv(const char *name) { return 0; }

// =====================================================================
// GLIBC HOST BYPASSES & ADVANCED FORMATTING FIX
// =====================================================================
int system(const char *command) { return -1; }
int putc(int c, FILE *stream) { char s[2]={(char)c,0}; print(s); return c; }
int* __errno_location(void) { return &errno; }

int vsnprintf(char *str, size_t size, const char *format, va_list args) {
    char* out = str;
    size_t remain = size > 0 ? size - 1 : 0;
    
    while (*format && remain > 0) {
        if (*format == '%') {
            format++;
            int pad_zero = 0, width = 0, precision = -1;

            if (*format == '0') { pad_zero = 1; format++; }
            while (*format >= '0' && *format <= '9') { width = width * 10 + (*format - '0'); format++; }
            if (*format == '.') {
                format++; precision = 0;
                while (*format >= '0' && *format <= '9') { precision = precision * 10 + (*format - '0'); format++; }
            }
            while (*format == 'l' || *format == 'h') format++; // skip length modifiers

            if (*format == 's') {
                char* s = __builtin_va_arg(args, char*);
                if (!s) s = "(null)";
                while (*s && remain > 0) { *out++ = *s++; remain--; }
            } else if (*format == 'd' || *format == 'i' || *format == 'u') {
                int n = __builtin_va_arg(args, int);
                char buf[32]; itoa(n, buf, 10);
                char* s = buf;
                int len = strlen(s);
                int zeros = 0, spaces = 0;
                if (precision >= 0 && len < precision) zeros = precision - len;
                else if (pad_zero && width > len) zeros = width - len;
                else if (width > len) spaces = width - len;
                
                while (spaces-- > 0 && remain > 0) { *out++ = ' '; remain--; }
                while (zeros-- > 0 && remain > 0) { *out++ = '0'; remain--; }
                while (*s && remain > 0) { *out++ = *s++; remain--; }
            } else if (*format == 'x' || *format == 'X' || *format == 'p') {
                unsigned int n = __builtin_va_arg(args, unsigned int);
                char buf[32]; itoa(n, buf, 16);
                char* s = buf;
                int len = strlen(s);
                int zeros = 0, spaces = 0;
                if (precision >= 0 && len < precision) zeros = precision - len;
                else if (pad_zero && width > len) zeros = width - len;
                else if (width > len) spaces = width - len;

                while (spaces-- > 0 && remain > 0) { *out++ = ' '; remain--; }
                while (zeros-- > 0 && remain > 0) { *out++ = '0'; remain--; }
                while (*s && remain > 0) { 
                    char c = *s++;
                    if (*format == 'X' && c >= 'a' && c <= 'z') c -= 32;
                    *out++ = c; remain--; 
                }
            } else if (*format == 'c') {
                char c = (char)__builtin_va_arg(args, int);
                *out++ = c; remain--;
            } else {
                *out++ = '%'; remain--;
                if (remain > 0 && *format) { *out++ = *format; remain--; }
            }
        } else {
            *out++ = *format; remain--;
        }
        if (*format) format++;
    }
    if (size > 0) *out = '\0';
    return out - str;
}

int snprintf(char *str, size_t size, const char *format, ...) {
    va_list args;
    __builtin_va_start(args, format);
    int res = vsnprintf(str, size, format, args);
    __builtin_va_end(args);
    return res;
}

int vfprintf(FILE *stream, const char *format, va_list args) {
    char buf[1024];
    vsnprintf(buf, sizeof(buf), format, args);
    print(buf);
    return 0;
}

int printf(const char *format, ...) { 
    char buf[1024];
    va_list args;
    __builtin_va_start(args, format);
    vsnprintf(buf, sizeof(buf), format, args);
    __builtin_va_end(args);
    print(buf);
    return 0; 
}

int fprintf(FILE *stream, const char *format, ...) { 
    char buf[1024];
    va_list args;
    __builtin_va_start(args, format);
    vsnprintf(buf, sizeof(buf), format, args);
    __builtin_va_end(args);
    print(buf);
    return 0; 
}

int puts(const char *s) { print(s); print("\n"); return 0; }
int __isoc99_sscanf(const char *str, const char *format, ...) { return 0; }

int __vfprintf_chk(FILE * fp, int flag, const char * format, va_list ap) { return vfprintf(fp, format, ap); }
int __printf_chk(int flag, const char *format, ...) { 
    char buf[1024]; va_list args; __builtin_va_start(args, format);
    vsnprintf(buf, sizeof(buf), format, args); __builtin_va_end(args);
    print(buf); return 0; 
}
int __fprintf_chk(FILE *stream, int flag, const char *format, ...) { 
    char buf[1024]; va_list args; __builtin_va_start(args, format);
    vsnprintf(buf, sizeof(buf), format, args); __builtin_va_end(args);
    print(buf); return 0; 
}
int __snprintf_chk(char *str, size_t maxlen, int flag, size_t os, const char *format, ...) {
    va_list args; __builtin_va_start(args, format);
    int res = vsnprintf(str, maxlen, format, args); __builtin_va_end(args);
    return res;
}
int __vsnprintf_chk(char *str, size_t maxlen, int flag, size_t os, const char *format, va_list args) {
    return vsnprintf(str, maxlen, format, args);
}

char *__strncpy_chk(char *dest, const char *src, size_t n, size_t destlen) { return strncpy(dest, src, n); }
void *__memset_chk(void *s, int c, size_t n, size_t destlen) { return memset(s, c, n); }
void *__memcpy_chk(void *dest, const void *src, size_t n, size_t destlen) { return memcpy(dest, src, n); }

unsigned short dummy_ctype_b_arr[384];
unsigned short* dummy_ctype_b_ptr = &dummy_ctype_b_arr[128];
unsigned short** __ctype_b_loc(void) {
    static int init = 0;
    if (!init) {
        for (int i = -128; i < 256; i++) {
            unsigned short mask = 0;
            if (i >= '0' && i <= '9') mask |= 2048; // isdigit
            if ((i >= 'A' && i <= 'Z') || (i >= 'a' && i <= 'z')) mask |= 1024; // isalpha
            if (i == ' ' || i == '\t' || i == '\n' || i == '\r' || i == '\v' || i == '\f') mask |= 8192; // isspace
            dummy_ctype_b_arr[i + 128] = mask;
        }
        init = 1;
    }
    return &dummy_ctype_b_ptr;
}

int dummy_toupper_arr[384];
int* dummy_toupper_ptr = &dummy_toupper_arr[128];
int** __ctype_toupper_loc(void) {
    static int init = 0;
    if (!init) {
        for (int i = -128; i < 256; i++) dummy_toupper_arr[i + 128] = (i >= 'a' && i <= 'z') ? (i - 32) : i;
        init = 1;
    }
    return &dummy_toupper_ptr;
}

long long __divdi3(long long a, long long b) {
    int neg = 0;
    unsigned long long n = a;
    unsigned long long d = b;
    if (a < 0) { n = -a; neg ^= 1; }
    if (b < 0) { d = -b; neg ^= 1; }

    unsigned long long q = 0;
    for (int i = 63; i >= 0; i--) {
        if ((n >> i) >= d) {
            q += (1ULL << i);
            n -= (d << i);
        }
    }
    return neg ? -q : q;
}

// =====================================================================
// PLUTOGL - Official Core Graphics Engine
// =====================================================================
void pluto_init(PlutoContext* ctx, int w, int h) {
    ctx->width = w; ctx->height = h; ctx->x = 100; ctx->y = 100;
    int id = -1;
    ctx->buffer = (unsigned int*)sys_create_window(w, h, &id);
    ctx->id = id;
    sys_set_window_pos(ctx->id, ctx->x, ctx->y);
}

void pluto_swap_buffers() { sys_update_window(); }

void DG_SetWindowTitle(const char *title) {}