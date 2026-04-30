// =====================================================================
// nova_libc.h - NoVa OS Ring 3 Standard Library (Single Window)
// =====================================================================
#ifndef NOVA_LIBC_H
#define NOVA_LIBC_H

typedef unsigned int size_t;
#define STDOUT 1

// --- Core API ---
void exit(int code);
int open(const char* filename);
int close(int fd);
int read(int fd, char* buffer, size_t count);
int write(int fd, const char* buffer, size_t count);
void print(const char* str);
size_t strlen(const char* str);
void* memset(void* ptr, int value, size_t num);
void* memcpy(void* dest, const void* src, size_t num);
void* sys_brk(void* addr);
void* malloc(size_t size);
void free(void* ptr);

// --- Single Window Manager & Inputs ---
void* sys_create_window(int width, int height);
void sys_update_window();
void sys_set_window_pos(int x, int y);
void sys_get_mouse(int* x, int* y, int* buttons);
void sys_clear_background();
void* sys_resize_window(int w, int h);
void sys_yield();
void sys_draw_rect_xor(int x, int y, int w, int h);
int sys_get_key_state(int scancode);
unsigned int sys_get_ticks();
void sys_sleep(unsigned int ms);
void* sys_fat32_load(const char* filename, unsigned int* out_size);

// --- PlutoGL Engine ---
typedef struct {
    unsigned int* buffer;
    int width;
    int height;
    int x;
    int y;
} PlutoContext;

void pluto_init(PlutoContext* ctx, int w, int h);
void pluto_put_pixel(PlutoContext* ctx, int x, int y, unsigned int color);
void pluto_clear(PlutoContext* ctx, unsigned int color);
void pluto_swap_buffers();
void pluto_draw_text(PlutoContext* ctx, int x, int y, const char* str, unsigned int color);

#endif