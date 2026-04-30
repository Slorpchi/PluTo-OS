// =====================================================================
// PlutoGL.c - Classic MS-DOS Style GUI & Image Renderer
// =====================================================================
#include "nova_libc.h"

// --- GUI Color Palette (Classic Windows 3.1 / MS-DOS Style) ---
#define COLOR_DESKTOP  0x0000AA
#define COLOR_DIALOG   0xC0C0C0
#define COLOR_3D_LIGHT 0xFFFFFF
#define COLOR_3D_DARK  0x888888
#define COLOR_BLACK    0x000000
#define COLOR_WHITE    0xFFFFFF
#define COLOR_SELECT   0x0000AA

// --- COMPACT 8x8 FONT ARRAY (ASCII 32-127) ---
const unsigned char gui_font[768] = {
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00, 0x18,0x3C,0x3C,0x18,0x18,0x00,0x18,0x00,
    0x66,0x66,0x22,0x00,0x00,0x00,0x00,0x00, 0x36,0x36,0x7F,0x36,0x7F,0x36,0x36,0x00,
    0x18,0x3E,0x60,0x3C,0x06,0x7C,0x18,0x00, 0x63,0x66,0x0C,0x18,0x30,0x66,0xC6,0x00,
    0x38,0x6C,0x6C,0x38,0x6D,0x66,0x3B,0x00, 0x18,0x18,0x30,0x00,0x00,0x00,0x00,0x00,
    0x0C,0x18,0x30,0x30,0x30,0x18,0x0C,0x00, 0x30,0x18,0x0C,0x0C,0x0C,0x18,0x30,0x00,
    0x00,0x66,0x3C,0xFF,0x3C,0x66,0x00,0x00, 0x00,0x18,0x18,0x7E,0x18,0x18,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x18,0x18,0x30, 0x00,0x00,0x00,0x7E,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x18,0x18,0x00, 0x06,0x0C,0x18,0x30,0x60,0xC0,0x80,0x00,
    0x3C,0x66,0x6E,0x76,0x66,0x66,0x3C,0x00, 0x18,0x38,0x18,0x18,0x18,0x18,0x7E,0x00,
    0x3C,0x66,0x06,0x0C,0x18,0x30,0x7E,0x00, 0x3C,0x66,0x06,0x1C,0x06,0x66,0x3C,0x00,
    0x0C,0x1C,0x3C,0x6C,0x7E,0x0C,0x0C,0x00, 0x7E,0x60,0x7C,0x06,0x06,0x66,0x3C,0x00,
    0x3C,0x60,0x7C,0x66,0x66,0x66,0x3C,0x00, 0x7E,0x06,0x0C,0x18,0x30,0x30,0x30,0x00,
    0x3C,0x66,0x66,0x3C,0x66,0x66,0x3C,0x00, 0x3C,0x66,0x66,0x66,0x3E,0x06,0x3C,0x00,
    0x00,0x18,0x18,0x00,0x00,0x18,0x18,0x00, 0x00,0x18,0x18,0x00,0x00,0x18,0x18,0x30,
    0x06,0x0C,0x18,0x30,0x18,0x0C,0x06,0x00, 0x00,0x00,0x7E,0x00,0x7E,0x00,0x00,0x00,
    0x60,0x30,0x18,0x0C,0x18,0x30,0x60,0x00, 0x3C,0x66,0x06,0x0C,0x18,0x00,0x18,0x00,
    0x3C,0x66,0x6E,0x6E,0x60,0x66,0x3C,0x00, 0x3C,0x66,0x66,0x7E,0x66,0x66,0x66,0x00,
    0x7C,0x66,0x66,0x7C,0x66,0x66,0x7C,0x00, 0x3C,0x66,0x60,0x60,0x60,0x66,0x3C,0x00,
    0x78,0x6C,0x66,0x66,0x66,0x6C,0x78,0x00, 0x7E,0x60,0x60,0x7C,0x60,0x60,0x7E,0x00,
    0x7E,0x60,0x60,0x7C,0x60,0x60,0x60,0x00, 0x3C,0x66,0x60,0x6E,0x66,0x66,0x3E,0x00,
    0x66,0x66,0x66,0x7E,0x66,0x66,0x66,0x00, 0x3C,0x18,0x18,0x18,0x18,0x18,0x3C,0x00,
    0x1E,0x0C,0x0C,0x0C,0x0C,0x6C,0x38,0x00, 0x66,0x6C,0x78,0x70,0x78,0x6C,0x66,0x00,
    0x60,0x60,0x60,0x60,0x60,0x60,0x7E,0x00, 0x63,0x77,0x7F,0x6B,0x63,0x63,0x63,0x00,
    0x66,0x76,0x7E,0x7E,0x6E,0x66,0x66,0x00, 0x3C,0x66,0x66,0x66,0x66,0x66,0x3C,0x00,
    0x7C,0x66,0x66,0x7C,0x60,0x60,0x60,0x00, 0x3C,0x66,0x66,0x66,0x6A,0x6C,0x36,0x00,
    0x7C,0x66,0x66,0x7C,0x78,0x6C,0x66,0x00, 0x3C,0x66,0x60,0x3C,0x06,0x66,0x3C,0x00,
    0x7E,0x18,0x18,0x18,0x18,0x18,0x18,0x00, 0x66,0x66,0x66,0x66,0x66,0x66,0x3C,0x00,
    0x66,0x66,0x66,0x66,0x66,0x3C,0x18,0x00, 0x63,0x63,0x63,0x6B,0x7F,0x77,0x63,0x00,
    0x66,0x66,0x3C,0x18,0x3C,0x66,0x66,0x00, 0x66,0x66,0x66,0x3C,0x18,0x18,0x18,0x00,
    0x7E,0x06,0x0C,0x18,0x30,0x60,0x7E,0x00, 0x3C,0x30,0x30,0x30,0x30,0x30,0x3C,0x00,
    0x80,0xC0,0x60,0x30,0x18,0x0C,0x06,0x00, 0x3C,0x0C,0x0C,0x0C,0x0C,0x0C,0x3C,0x00,
    0x18,0x3C,0x66,0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xFF,
    0x30,0x18,0x0C,0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x3C,0x06,0x3E,0x66,0x3E,0x00,
    0x60,0x60,0x7C,0x66,0x66,0x66,0x7C,0x00, 0x00,0x00,0x3C,0x60,0x60,0x60,0x3C,0x00,
    0x06,0x06,0x3E,0x66,0x66,0x66,0x3E,0x00, 0x00,0x00,0x3C,0x66,0x7E,0x60,0x3C,0x00,
    0x1C,0x30,0x7C,0x30,0x30,0x30,0x30,0x00, 0x00,0x00,0x3E,0x66,0x66,0x3E,0x06,0x3C,
    0x60,0x60,0x7C,0x66,0x66,0x66,0x66,0x00, 0x18,0x00,0x38,0x18,0x18,0x18,0x3C,0x00,
    0x06,0x00,0x06,0x06,0x06,0x06,0x06,0x3C, 0x60,0x60,0x66,0x6C,0x78,0x6C,0x66,0x00,
    0x38,0x18,0x18,0x18,0x18,0x18,0x3C,0x00, 0x00,0x00,0x66,0x7F,0x7F,0x6B,0x63,0x00,
    0x00,0x00,0x7C,0x66,0x66,0x66,0x66,0x00, 0x00,0x00,0x3C,0x66,0x66,0x66,0x3C,0x00,
    0x00,0x00,0x7C,0x66,0x66,0x7C,0x60,0x60, 0x00,0x00,0x3E,0x66,0x66,0x3E,0x06,0x06,
    0x00,0x00,0x7C,0x66,0x60,0x60,0x60,0x00, 0x00,0x00,0x3E,0x60,0x3C,0x06,0x7C,0x00,
    0x30,0x30,0x7C,0x30,0x30,0x30,0x1C,0x00, 0x00,0x00,0x66,0x66,0x66,0x66,0x3E,0x00,
    0x00,0x00,0x66,0x66,0x66,0x3C,0x18,0x00, 0x00,0x00,0x63,0x6B,0x7F,0x7F,0x36,0x00,
    0x00,0x00,0x66,0x3C,0x18,0x3C,0x66,0x00, 0x00,0x00,0x66,0x66,0x66,0x3E,0x06,0x3C,
    0x00,0x00,0x7E,0x0C,0x18,0x30,0x7E,0x00, 0x0E,0x18,0x18,0x70,0x18,0x18,0x0E,0x00,
    0x18,0x18,0x18,0x00,0x18,0x18,0x18,0x00, 0x70,0x18,0x18,0x0E,0x18,0x18,0x70,0x00,
    0x76,0xDC,0x00,0x00,0x00,0x00,0x00,0x00
};

// --- Custom String Utilities ---
char* pluto_strcat(char *dest, const char *src) {
    char *d = dest;
    while (*d) d++;
    while ((*d++ = *src++));
    return dest;
}

// --- GUI Drawing Primitives ---
void gui_put_pixel(PlutoContext* ctx, int x, int y, unsigned int color) {
    if (x >= 0 && x < ctx->width && y >= 0 && y < ctx->height) {
        ctx->buffer[(y * ctx->width) + x] = color;
    }
}

void gui_draw_char(PlutoContext* ctx, int x, int y, char c, unsigned int color) {
    if (c < 32 || c > 127) return;
    int idx = (c - 32) * 8;
    for (int row = 0; row < 8; row++) {
        unsigned char data = gui_font[idx + row];
        for (int col = 0; col < 8; col++) {
            if (data & (1 << (7 - col))) {
                gui_put_pixel(ctx, x + col, y + row, color);
            }
        }
    }
}

void gui_draw_text(PlutoContext* ctx, int x, int y, const char* str, unsigned int color) {
    while (*str) {
        gui_draw_char(ctx, x, y, *str, color);
        x += 8;
        str++;
    }
}

void draw_rect(PlutoContext* ctx, int x, int y, int w, int h, unsigned int color) {
    for(int iy = y; iy < y + h; iy++) {
        for(int ix = x; ix < x + w; ix++) gui_put_pixel(ctx, ix, iy, color);
    }
}

void draw_3d_rect(PlutoContext* ctx, int x, int y, int w, int h, int sunken) {
    unsigned int tl = sunken ? COLOR_3D_DARK : COLOR_3D_LIGHT;
    unsigned int br = sunken ? COLOR_3D_LIGHT : COLOR_3D_DARK;
    
    draw_rect(ctx, x, y, w, h, COLOR_DIALOG); // Fill
    for(int ix = x; ix < x + w; ix++) {
        gui_put_pixel(ctx, ix, y, tl);           // Top
        gui_put_pixel(ctx, ix, y + h - 1, br);   // Bottom
    }
    for(int iy = y; iy < y + h; iy++) {
        gui_put_pixel(ctx, x, iy, tl);           // Left
        gui_put_pixel(ctx, x + w - 1, iy, br);   // Right
    }
}

// --- Dynamic File State ---
char valid_bmps[128][16];
int bmp_count = 0;
int active_img_idx = -1;
int selected_idx = -1;
int scroll_pos = 0;

void scan_filesystem() {
    unsigned int size = 0;
    char* list = (char*)sys_fat32_load("filelist.txt", &size);
    if (list && size > 0) {
        int name_len = 0;
        for (unsigned int j = 0; j < size; j++) {
            char c = list[j];
            if (c == '\n' || c == '\r') {
                if (name_len > 0) {
                    valid_bmps[bmp_count][name_len] = '\0';
                    bmp_count++; name_len = 0;
                    if (bmp_count >= 128) break; 
                }
            } else if (name_len < 15) {
                valid_bmps[bmp_count][name_len++] = c;
            }
        }
        if (name_len > 0 && bmp_count < 128) {
            valid_bmps[bmp_count][name_len] = '\0'; bmp_count++;
        }
        free(list); 
    }
}

// --- BMP Auto-Scaling Renderer ---
int load_and_draw_bmp(PlutoContext* screen, const char* filename, int draw_x, int draw_y) {
    unsigned int size = 0;
    unsigned char* data = (unsigned char*)sys_fat32_load(filename, &size);
    if (!data || size == 0) return 0; 

    unsigned int pixel_offset = *(unsigned int*)(&data[10]);
    int width = *(int*)(&data[18]);
    int height = *(int*)(&data[22]);
    short bpp = *(short*)(&data[28]);
    if (bpp != 24 && bpp != 32) { free(data); return 0; }

    int is_top_down = 0;
    if (width < 0) width = -width;
    if (height < 0) { height = -height; is_top_down = 1; }

    // DYNAMIC NEAREST-NEIGHBOR AUTO-SCALING!
    int scale = 1;
    if (width < 100 && height < 100) scale = 3;
    else if (width < 200 && height < 200) scale = 2;

    unsigned char* pixels = data + pixel_offset;
    int row_padded = (width * (bpp / 8) + 3) & (~3); 

    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            int target_y = is_top_down ? y : (height - 1 - y);
            int pixel_idx = (y * row_padded) + (x * (bpp / 8));
            unsigned char b = pixels[pixel_idx];
            unsigned char g = pixels[pixel_idx + 1];
            unsigned char r = pixels[pixel_idx + 2];

            if (r == 0 && g == 0 && b == 0) continue; // Transparency
            unsigned int color = (r << 16) | (g << 8) | b;

            // Draw the scaled block of pixels!
            for(int sy = 0; sy < scale; sy++) {
                for(int sx = 0; sx < scale; sx++) {
                    int final_x = draw_x + (x * scale) + sx;
                    int final_y = draw_y + (target_y * scale) + sy;
                    if (final_x >= 3 && final_x < screen->width - 3 && final_y >= 10 && final_y < screen->height - 3) {
                        screen->buffer[(final_y * screen->width) + final_x] = color;
                    }
                }
            }
        }
    }
    free(data); 
    return 1;
}

// --- Classic Desktop Layout Manager ---
void redraw_all(PlutoContext* screen) {
    // 1. Draw Master NoVa OS Window Cosmetics (These scale perfectly!)
    for(int i = 0; i < screen->width * screen->height; i++) screen->buffer[i] = 0x888888; // 3px Gray Outline
    for (int y = 0; y < 10; y++) {
        for (int x = 0; x < screen->width; x++) {
            screen->buffer[(y * screen->width) + x] = 0xFFFFFF; // White Title Bar
        }
    }
    gui_draw_text(screen, 5, 2, "PlutoGL Image Viewer", COLOR_BLACK);
    draw_rect(screen, 3, 10, screen->width - 6, screen->height - 13, COLOR_DESKTOP); // Inner Desktop
    
    // ==========================================
    // WINDOW 1: File Picker Dialog
    // ==========================================
    draw_3d_rect(screen, 10, 20, 280, 250, 0); 
    draw_rect(screen, 12, 22, 276, 14, COLOR_DESKTOP); // Dialog Title Bar
    gui_draw_text(screen, 16, 25, "Open Image", COLOR_WHITE);
    
    // File Listbox (Sunken)
    draw_3d_rect(screen, 20, 45, 160, 210, 1);
    draw_rect(screen, 22, 47, 156, 206, COLOR_WHITE); // White interior
    
    // Draw List Items
    for (int i = 0; i < 20; i++) {
        int idx = scroll_pos + i;
        if (idx >= bmp_count) break;
        
        int text_y = 50 + (i * 10);
        if (idx == selected_idx) {
            draw_rect(screen, 22, text_y - 1, 156, 10, COLOR_SELECT); // Highlight bar
            gui_draw_text(screen, 26, text_y, valid_bmps[idx], COLOR_WHITE);
        } else {
            gui_draw_text(screen, 26, text_y, valid_bmps[idx], COLOR_BLACK);
        }
    }

    // Scrollbar Elements
    draw_3d_rect(screen, 185, 45, 20, 210, 0); // Scrollbar track
    draw_3d_rect(screen, 185, 45, 20, 20, 0);  // UP Arrow
    gui_draw_text(screen, 192, 51, "^", COLOR_BLACK);
    draw_3d_rect(screen, 185, 235, 20, 20, 0); // DOWN Arrow
    gui_draw_text(screen, 192, 241, "v", COLOR_BLACK);
    
    // Draw Scroll Thumb
    int thumb_y = 65 + ((scroll_pos * 150) / (bmp_count > 0 ? bmp_count : 1));
    draw_3d_rect(screen, 185, thumb_y, 20, 20, 0); 

    // Action Buttons
    draw_3d_rect(screen, 215, 45, 65, 20, 0);
    gui_draw_text(screen, 230, 51, "LOAD", COLOR_BLACK);
    
    draw_3d_rect(screen, 215, 75, 65, 20, 0);
    gui_draw_text(screen, 230, 81, "EXIT", COLOR_BLACK);

    // ==========================================
    // WINDOW 2: Image Viewer Frame
    // ==========================================
    if (active_img_idx >= 0 && active_img_idx < bmp_count) {
        int viewer_x = 300;
        int viewer_y = 20;
        int viewer_w = screen->width - 310;
        int viewer_h = screen->height - 30;

        draw_3d_rect(screen, viewer_x, viewer_y, viewer_w, viewer_h, 0);
        draw_rect(screen, viewer_x + 2, viewer_y + 2, viewer_w - 4, 14, COLOR_DESKTOP); // Viewer Title Bar
        
        char title[64] = "Viewing: ";
        pluto_strcat(title, valid_bmps[active_img_idx]); 
        gui_draw_text(screen, viewer_x + 6, viewer_y + 5, title, COLOR_WHITE);
        
        // Sunken Canvas for Image
        draw_3d_rect(screen, viewer_x + 10, viewer_y + 25, viewer_w - 20, viewer_h - 35, 1);
        draw_rect(screen, viewer_x + 12, viewer_y + 27, viewer_w - 24, viewer_h - 39, COLOR_BLACK);

        load_and_draw_bmp(screen, valid_bmps[active_img_idx], viewer_x + 14, viewer_y + 29);
    }
    
    pluto_swap_buffers();
}

void handle_image_load(PlutoContext* screen, int idx) {
    if (idx < 0 || idx >= bmp_count) return;
    active_img_idx = idx;
    
    unsigned int size = 0;
    unsigned char* data = (unsigned char*)sys_fat32_load(valid_bmps[idx], &size);
    if (!data || size == 0) return;

    int width = *(int*)(&data[18]);
    int height = *(int*)(&data[22]);
    free(data);

    if (width < 0) width = -width;
    if (height < 0) height = -height;

    // PRE-CALCULATE THE SCALE FOR RESIZING!
    int scale = 1;
    if (width < 100 && height < 100) scale = 3;
    else if (width < 200 && height < 200) scale = 2;

    int new_w = 300 + (width * scale) + 40; // File Picker + Scaled Width + Padding
    int new_h = (height * scale) + 70;      // Scaled Height + Padding
    
    if (new_w < 320) new_w = 320;
    if (new_h < 300) new_h = 300;
    if (new_w > 950) new_w = 950;
    if (new_h > 700) new_h = 700;

    // Because the borders are drawn inside redraw_all, they will naturally hug the new size!
    screen->buffer = (unsigned int*)sys_resize_window(new_w, new_h);
    screen->width = new_w;
    screen->height = new_h;

    redraw_all(screen);
}

// =====================================================================
// MAIN APPLICATION
// =====================================================================
void _start() {
    bmp_count = 0;
    active_img_idx = -1;
    selected_idx = -1;
    scroll_pos = 0;
    for(int i = 0; i < 128; i++) valid_bmps[i][0] = '\0';

    print("\nStarting NoVa OS Desktop Image Viewer...\n");
    scan_filesystem();

    PlutoContext screen;
    pluto_init(&screen, 300, 280); 
    redraw_all(&screen);

    int running = 1;
    int is_dragging = 0;
    int drag_offset_x = 0, drag_offset_y = 0;
    int drag_last_x = 0, drag_last_y = 0;
    int was_mouse_down = 0;

    while (running) {
        if (sys_get_key_state(0x0E)) break; // Backspace to exit

        int mx, my, mbtn;
        sys_get_mouse(&mx, &my, &mbtn);
        int local_mx = mx - screen.x;
        int local_my = my - screen.y;
        int is_mouse_down = mbtn & 1;

        if (is_mouse_down) { 
            // 1. Dragging OS Window (Clicking the new Title Bar!)
            if (!is_dragging && !was_mouse_down && local_mx >= 0 && local_mx <= screen.width && local_my >= 0 && local_my <= 10) {
                is_dragging = 1;
                drag_offset_x = local_mx; drag_offset_y = local_my;
                drag_last_x = screen.x; drag_last_y = screen.y;
                sys_draw_rect_xor(drag_last_x, drag_last_y, screen.width, screen.height);
            }
            
            // --- GUI EVENT PROCESSING ---
            if (!is_dragging && !was_mouse_down) {
                if (local_mx >= 22 && local_mx <= 178 && local_my >= 47 && local_my <= 253) {
                    int clicked_item = scroll_pos + ((local_my - 47) / 10);
                    if (clicked_item < bmp_count) { selected_idx = clicked_item; redraw_all(&screen); }
                }
                
                if (local_mx >= 185 && local_mx <= 205 && local_my >= 45 && local_my <= 65) {
                    if (scroll_pos > 0) { scroll_pos--; redraw_all(&screen); }
                }
                
                if (local_mx >= 185 && local_mx <= 205 && local_my >= 235 && local_my <= 255) {
                    if (scroll_pos < bmp_count - 1) { scroll_pos++; redraw_all(&screen); }
                }
                
                if (local_mx >= 215 && local_mx <= 280 && local_my >= 45 && local_my <= 65) {
                    draw_3d_rect(&screen, 215, 45, 65, 20, 1); 
                    gui_draw_text(&screen, 230, 51, "LOAD", COLOR_BLACK);
                    pluto_swap_buffers();
                    sys_sleep(50);
                    handle_image_load(&screen, selected_idx);
                }
                
                if (local_mx >= 215 && local_mx <= 280 && local_my >= 75 && local_my <= 95) {
                    draw_3d_rect(&screen, 215, 75, 65, 20, 1); 
                    gui_draw_text(&screen, 230, 81, "EXIT", COLOR_BLACK);
                    pluto_swap_buffers();
                    sys_sleep(50);
                    running = 0;
                }
            }

            if (is_dragging) {
                int new_x = mx - drag_offset_x;
                int new_y = my - drag_offset_y;
                if (new_x < 0) new_x = 0; if (new_y < 0) new_y = 0;
                if (new_x > 1024 - screen.width) new_x = 1024 - screen.width;
                if (new_y > 768 - screen.height) new_y = 768 - screen.height;

                if (new_x != drag_last_x || new_y != drag_last_y) {
                    sys_draw_rect_xor(drag_last_x, drag_last_y, screen.width, screen.height);
                    sys_draw_rect_xor(new_x, new_y, screen.width, screen.height);
                    drag_last_x = new_x; drag_last_y = new_y;
                }
            }
        } else { 
            if (is_dragging) {
                is_dragging = 0;
                sys_draw_rect_xor(drag_last_x, drag_last_y, screen.width, screen.height);
                screen.x = drag_last_x; screen.y = drag_last_y;
                sys_set_window_pos(screen.x, screen.y);
                pluto_swap_buffers(); 
            }
        }
        
        was_mouse_down = is_mouse_down;
        sys_yield(); 
    }
    
    sys_resize_window(0, 0); 
    exit(0);
}