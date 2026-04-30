// =====================================================================
// doomgeneric_nova.c - NoVa OS Implementation for DoomGeneric!
// =====================================================================
#include "doomgeneric.h"
#include "doomkeys.h"
#include "doom_libc.h"

PlutoContext doom_window;
static int last_state[128] = {0};

void DG_Init() {
    print("Initializing Doom Engine via PlutoGL...\n");
    
    // --- PERFECT NOVA OS WINDOW MATH ---
    // Width: 640 (Doom's internal 2x scale) + 3 (Left Gray) + 3 (Right Gray) = 646
    // Height: 400 (Doom's internal 2x scale) + 10 (Title Bar) + 3 (Bottom Gray) = 413
    pluto_init(&doom_window, 646, 413);
    
    // 1. Fill the entire window with the 3px Gray Outline color
    for(int i = 0; i < doom_window.width * doom_window.height; i++) {
        doom_window.buffer[i] = 0x888888; // Classic NoVa OS Gray
    }
    
    // 2. Draw the 10px White Title Bar at the top!
    for (int y = 0; y < 10; y++) {
        for (int x = 0; x < doom_window.width; x++) {
            doom_window.buffer[(y * doom_window.width) + x] = 0xFFFFFF; // Pure White
        }
    }
}

void DG_DrawFrame() {
    // DoomGeneric already scaled the buffer to 640x400 for us!
    unsigned int* src = (unsigned int*)DG_ScreenBuffer;
    
    // We do a direct 1:1 copy into our window's safe area.
    for (int y = 0; y < 400; y++) {
        for (int x = 0; x < 640; x++) {
            // Map the pixels perfectly into the frame:
            // Offset X by 3px to bypass the left gray border
            // Offset Y by 10px to bypass the top white title bar
            doom_window.buffer[((y + 10) * doom_window.width) + (x + 3)] = src[(y * 640) + x];
        }
    }
    
    pluto_swap_buffers();
    sys_yield(); // Let the OS breathe so the keyboard doesn't lag!
}

void DG_SleepMs(uint32_t ms) {
    sys_sleep(ms);
}

uint32_t DG_GetTicksMs() {
    return sys_get_ticks();
}

// Map NoVa OS hardware scancodes to Doom keys
int get_doom_key(int scancode) {
    switch(scancode) {
        // --- NUMBERS (Weapon Switching) ---
        case 0x02: return '1';
        case 0x03: return '2';
        case 0x04: return '3';
        case 0x05: return '4';
        case 0x06: return '5';
        case 0x07: return '6';
        case 0x08: return '7';
        
        // --- ALPHABET (For typing, cheats, Y/N, and custom bindings) ---
        case 0x10: return 'q';
        case 0x11: return 'w';
        case 0x12: return 'e';
        case 0x13: return 'r';
        case 0x14: return 't';
        case 0x15: return 'y';
        case 0x16: return 'u';
        case 0x17: return 'i';
        case 0x18: return 'o';
        case 0x19: return 'p';
        
        case 0x1E: return 'a';
        case 0x1F: return 's';
        case 0x20: return 'd';
        case 0x21: return 'f';
        case 0x22: return 'g';
        case 0x23: return 'h';
        case 0x24: return 'j';
        case 0x25: return 'k';
        case 0x26: return 'l';
        
        case 0x2C: return 'z';
        case 0x2D: return 'x';
        case 0x2E: return 'c';
        case 0x2F: return 'v';
        case 0x30: return 'b';
        case 0x31: return 'n';
        case 0x32: return 'm';
        
        // --- SPECIAL MODIFIERS & ACTIONS ---
        case 0x1C: return KEY_ENTER;
        case 0x39: return ' ';           // Spacebar (Use)
        case 0x01: return KEY_ESCAPE;
        case 0x1D: return KEY_RCTRL;     // Left/Right Ctrl (Fire)
        case 0x2A: return KEY_RSHIFT;    // Left Shift (Sprint)
        case 0x36: return KEY_RSHIFT;    // Right Shift (Sprint)
        case 0x38: return KEY_RALT;      // Alt (Strafe)
        case 0x0E: return KEY_BACKSPACE;
        case 0x0F: return KEY_TAB;
        
        // --- ARROWS ---
        case 0x4B: return KEY_LEFTARROW;
        case 0x4D: return KEY_RIGHTARROW;
        case 0x48: return KEY_UPARROW;
        case 0x50: return KEY_DOWNARROW;
    }
    return 0;
}

int DG_GetKey(int* pressed, unsigned char* doomKey) {
    // Scan every single key on the keyboard (0 to 127) instead of a hardcoded array!
    for(int sc = 1; sc < 128; sc++) {
        int current = sys_get_key_state(sc);
        
        if (current != last_state[sc]) {
            last_state[sc] = current;    
            
            int dk = get_doom_key(sc);
            if (dk != 0) { // Only send recognized keys to Doom
                *pressed = current;          
                *doomKey = dk; 
                return 1;
            }
        }
    }
    return 0; // No key events right now
}

int main(int argc, char **argv) {
    doomgeneric_Create(argc, argv);
    while (1) {
        doomgeneric_Tick();
    }
    return 0;
}