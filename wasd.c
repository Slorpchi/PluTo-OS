// =====================================================================
// app.c - Testing Live Text Rendering and WASD Polling!
// =====================================================================
#include "nova_libc.h"

// Standard PS/2 Scancodes for our WASD keys
#define KEY_W 0x11
#define KEY_A 0x1E
#define KEY_S 0x1F
#define KEY_D 0x20

void _start() {
    PlutoContext screen;
    pluto_init(&screen, 300, 200);

    int running = 1;
    
    // Player State
    int player_x = 100;
    int player_y = 100;

    // Window Drag State
    int is_dragging = 0;
    int drag_offset_x = 0, drag_offset_y = 0;
    int drag_last_x = 0, drag_last_y = 0;

    while (running) {
        // --- HARDWARE INPUT ---
        int mx, my, mbtn;
        sys_get_mouse(&mx, &my, &mbtn);

        // Check our live keyboard state! (Without blocking the loop!)
        if (sys_get_key_state(KEY_W)) player_y -= 2;
        if (sys_get_key_state(KEY_S)) player_y += 2;
        if (sys_get_key_state(KEY_A)) player_x -= 2;
        if (sys_get_key_state(KEY_D)) player_x += 2;

        // Keep player inside the window content area
        if (player_x < 5) player_x = 5;
        if (player_x > screen.width - 20) player_x = screen.width - 20;
        if (player_y < 15) player_y = 15;
        if (player_y > screen.height - 20) player_y = screen.height - 20;

        // --- WINDOW DRAGGING LOGIC ---
        int local_mx = mx - screen.x;
        int local_my = my - screen.y;

        if (mbtn & 1) { 
            if (!is_dragging && local_mx >= 0 && local_mx <= screen.width && local_my >= 0 && local_my <= 10) {
                is_dragging = 1;
                drag_offset_x = local_mx; drag_offset_y = local_my;
                drag_last_x = screen.x; drag_last_y = screen.y;
                sys_draw_rect_xor(drag_last_x, drag_last_y, screen.width, screen.height);
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
            }
        }

        // --- RENDERING ---
        if (!is_dragging) {
            pluto_clear(&screen, 0x111111); // Dark Gray Background
            
            // Render Text directly using our new C-based font renderer!
            pluto_draw_text(&screen, 5, 15, "DOOM ENGINE PROTOTYPE", 0x00FF00);
            pluto_draw_text(&screen, 5, 30, "Use W, A, S, D to move!", 0xFFFFFF);
            
            // Draw the Player
            pluto_draw_text(&screen, player_x, player_y, "@", 0xFF0000);

            pluto_swap_buffers();
        }

        sys_yield(); 
    }

    exit(0);
}