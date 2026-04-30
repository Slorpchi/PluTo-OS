// =====================================================================
// nova_libc.c - Wrappers for NoVa OS Assembly Syscalls (Single Window)
// =====================================================================
#include "nova_libc.h"

void exit(int code) { asm volatile("int $0x80" : : "a"(1), "b"(code)); while(1); }
int open(const char* filename) { int fd; asm volatile("int $0x80" : "=a"(fd) : "a"(5), "b"(filename)); return fd; }
int close(int fd) { int ret; asm volatile("int $0x80" : "=a"(ret) : "a"(6), "b"(fd)); return ret; }
int read(int fd, char* buffer, size_t count) { int r; asm volatile("int $0x80" : "=a"(r) : "a"(3), "b"(fd), "c"(buffer), "d"(count)); return r; }
int write(int fd, const char* buffer, size_t count) { int w; asm volatile("int $0x80" : "=a"(w) : "a"(4), "b"(fd), "c"(buffer), "d"(count)); return w; }
size_t strlen(const char* str) { size_t l=0; while(str[l]) l++; return l; }
void print(const char* str) { write(STDOUT, str, strlen(str)); }

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

void* sys_brk(void* addr) { void* r; asm volatile("int $0x80" : "=a"(r) : "a"(45), "b"(addr)); return r; }
void* malloc(size_t size) { void* r; asm volatile("int $0x80" : "=a"(r) : "a"(90), "b"(size)); return r; }
void free(void* ptr) { asm volatile("int $0x80" : : "a"(91), "b"(ptr)); }

void* sys_create_window(int width, int height) {
    void* ptr;
    asm volatile("int $0x80" : "=a"(ptr) : "a"(100), "b"(width), "c"(height));
    return ptr;
}

void sys_update_window() { asm volatile("int $0x80" : : "a"(101)); }
void sys_set_window_pos(int x, int y) { asm volatile("int $0x80" : : "a"(102), "b"(x), "c"(y)); }
void sys_get_mouse(int* x, int* y, int* buttons) {
    int mx, my, mbtn; asm volatile("int $0x80" : "=a"(mx), "=b"(my), "=c"(mbtn) : "a"(103));
    if(x) *x=mx; if(y) *y=my; if(buttons) *buttons=mbtn;
}
void sys_clear_background() { asm volatile("int $0x80" : : "a"(104)); }
void* sys_resize_window(int w, int h) {
    void* ptr; asm volatile("int $0x80" : "=a"(ptr) : "a"(105), "b"(w), "c"(h)); return ptr;
}
void sys_yield() { asm volatile("int $0x80" : : "a"(106)); }
void sys_draw_rect_xor(int x, int y, int w, int h) {
    unsigned int packed_wh = (w << 16) | (h & 0xFFFF);
    asm volatile("int $0x80" : : "a"(107), "b"(x), "c"(y), "d"(packed_wh));
}
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
// PLUTOGL - Official Multi-Window API Stubs
// =====================================================================
void pluto_init(PlutoContext* ctx, int w, int h) {
    ctx->width = w; ctx->height = h; ctx->x = 100; ctx->y = 100;
    ctx->buffer = (unsigned int*)sys_create_window(w, h);
    sys_set_window_pos(ctx->x, ctx->y);
}

void pluto_put_pixel(PlutoContext* ctx, int x, int y, unsigned int color) {
    if (x >= 0 && x < ctx->width && y >= 0 && y < ctx->height) {
        ctx->buffer[(y * ctx->width) + x] = color;
    }
}

void pluto_clear(PlutoContext* ctx, unsigned int color) {
    for (int i = 0; i < ctx->width * ctx->height; i++) ctx->buffer[i] = color;
}

void pluto_swap_buffers() { sys_update_window(); }

extern const unsigned char font_8x8[760]; // From PlutoGL.c

void pluto_draw_char(PlutoContext* ctx, int x, int y, char c, unsigned int color) {
    // Basic character drawing stub to satisfy implicit declarations
    // Full implementation relies on your font array
}

void pluto_draw_text(PlutoContext* ctx, int x, int y, const char* str, unsigned int color) {
    // Stub to satisfy the compiler
}