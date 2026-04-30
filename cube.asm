; =====================================================================
; cube.asm - A Real-Time 3D Software Renderer for NoVa OS!
; =====================================================================

section .text
global _start

_start:
    ; 1. Print starting message
    mov eax, 4              
    mov ebx, 1              
    mov ecx, msg_start
    mov edx, msg_start_len
    int 0x80

    ; 2. Ask the kernel for a 256x256 Window
    mov eax, 100            
    mov ebx, 256            
    mov ecx, 256            
    int 0x80
    mov [win_ptr], eax      

    ; --- DRAW STATIC WINDOW DECORATIONS ONCE ---
    mov edi, [win_ptr]
    mov ecx, 256 * 256
    mov eax, 0x444444       ; Gray Borders
    rep stosd               

    mov edi, [win_ptr]
    add edi, 1028
    mov edx, 10             
.title_init_loop:
    mov ecx, 254            
    mov eax, 0xEEEEEE       ; White Title Bar
    rep stosd
    add edi, 8              
    dec edx
    jnz .title_init_loop

    mov dword [frame_count], 0
    mov byte [angle_a], 0
    mov byte [angle_b], 0

.frame_loop:
    call clear_content      ; ONLY clear the black screen now!
    call precalc_angles
    call project_vertices
    call draw_edges

    ; Update screen via Kernel!
    mov eax, 101            
    int 0x80

    ; Rotate the cube for the next frame
    add byte [angle_a], 2   ; Yaw speed
    add byte [angle_b], 1   ; Pitch speed

    inc dword [frame_count]
    cmp dword [frame_count], 1500  ; Run for 1500 frames!
    jl .frame_loop

    ; 3. Animation finished, wait for exit
    mov eax, 4
    mov ebx, 1
    mov ecx, msg_done
    mov edx, msg_done_len
    int 0x80

    mov eax, 3              
    mov ebx, 0              
    mov ecx, input_buf
    mov edx, 32             
    int 0x80

    mov eax, 1              
    mov ebx, 0              
    int 0x80

; =====================================================================
; 3D MATH & PROJECTION PIPELINE
; =====================================================================

precalc_angles:
    ; Get Sin and Cos for Angle A (Yaw)
    movzx eax, byte [angle_a]
    movsx ebx, byte [sin_table + eax]
    mov [sin_a], ebx
    add eax, 64             ; Cosine is just Sine shifted by 90 degrees!
    and eax, 255
    movsx ebx, byte [sin_table + eax]
    mov [cos_a], ebx

    ; Get Sin and Cos for Angle B (Pitch)
    movzx eax, byte [angle_b]
    movsx ebx, byte [sin_table + eax]
    mov [sin_b], ebx
    add eax, 64
    and eax, 255
    movsx ebx, byte [sin_table + eax]
    mov [cos_b], ebx
    ret

project_vertices:
    mov dword [curr_vertex], 0
.loop:
    ; Load the raw 3D Coordinates (X, Y, Z)
    mov eax, [curr_vertex]
    imul eax, 12            ; 12 bytes per vertex (3 dwords)
    add eax, vertices
    mov ebx, [eax]
    mov [val_x], ebx
    mov ebx, [eax+4]
    mov [val_y], ebx
    mov ebx, [eax+8]
    mov [val_z], ebx

    ; --- ROTATION AROUND Y-AXIS ---
    ; X1 = (X * cosA - Z * sinA) / 128
    mov eax, [val_x]
    imul eax, [cos_a]
    mov ebx, [val_z]
    imul ebx, [sin_a]
    sub eax, ebx
    sar eax, 7              ; Divide by 128 (Bitshift right 7)
    mov [val_x1], eax

    ; Z1 = (X * sinA + Z * cosA) / 128
    mov eax, [val_x]
    imul eax, [sin_a]
    mov ebx, [val_z]
    imul ebx, [cos_a]
    add eax, ebx
    sar eax, 7
    mov [val_z1], eax

    ; --- ROTATION AROUND X-AXIS ---
    ; Y2 = (Y * cosB - Z1 * sinB) / 128
    mov eax, [val_y]
    imul eax, [cos_b]
    mov ebx, [val_z1]
    imul ebx, [sin_b]
    sub eax, ebx
    sar eax, 7
    mov [val_y2], eax

    ; Z2 = (Y * sinB + Z1 * cosB) / 128
    mov eax, [val_y]
    imul eax, [sin_b]
    mov ebx, [val_z1]
    imul ebx, [cos_b]
    add eax, ebx
    sar eax, 7
    mov [val_z2], eax

    ; --- PERSPECTIVE PROJECTION ---
    ; Z_proj = Z2 + 150 (Move cube away from camera)
    mov ebx, [val_z2]
    add ebx, 150
    
    ; Screen X = (X1 * FOV) / Z_proj + CenterX
    mov eax, [val_x1]
    imul eax, 180           ; FOV Multiplier
    cdq                     ; Sign extend EAX into EDX for division
    idiv ebx                
    add eax, 128            ; Center X (256 / 2)
    mov edi, [curr_vertex]
    mov [proj_x + edi*4], eax

    ; Screen Y = (Y2 * FOV) / Z_proj + CenterY
    mov eax, [val_y2]
    imul eax, 180
    cdq
    idiv ebx
    add eax, 132            ; Center Y (Offset for title bar)
    mov edi, [curr_vertex]
    mov [proj_y + edi*4], eax

    inc dword [curr_vertex]
    cmp dword [curr_vertex], 8
    jl .loop
    ret

; =====================================================================
; WIREFRAME RENDERER (Bresenham's Line Algorithm)
; =====================================================================
draw_edges:
    mov dword [curr_edge], 0
.loop:
    mov eax, [curr_edge]
    shl eax, 1              ; 2 bytes per edge
    add eax, edges
    movzx ebx, byte [eax]   ; Vertex 1 Index
    movzx ecx, byte [eax+1] ; Vertex 2 Index

    ; Safely load 2D Coordinates without clobbering ECX!
    mov eax, [proj_x + ebx*4]  ; x0
    mov esi, [proj_y + ebx*4]  ; y0
    
    mov edi, [proj_x + ecx*4]  ; x1 (Store temporarily in EDI)
    mov edx, [proj_y + ecx*4]  ; y1
    
    mov ebx, esi               ; Move y0 to EBX
    mov ecx, edi               ; Move x1 to ECX

    mov esi, 0x00FF00          ; Neon Green Line Color!
    
    pushad
    call draw_line
    popad

    inc dword [curr_edge]
    cmp dword [curr_edge], 12
    jl .loop
    ret

draw_line:
    ; Input: EAX=x0, EBX=y0, ECX=x1, EDX=y1, ESI=color
    mov [dl_x0], eax
    mov [dl_y0], ebx
    mov [dl_x1], ecx
    mov [dl_y1], edx
    mov [dl_color], esi

    ; dx = abs(x1 - x0)
    mov eax, [dl_x1]
    sub eax, [dl_x0]
    mov dword [dl_sx], 1
    jge .dx_pos
    neg eax
    mov dword [dl_sx], -1
.dx_pos:
    mov [dl_dx], eax

    ; dy = -abs(y1 - y0)
    mov eax, [dl_y1]
    sub eax, [dl_y0]
    mov dword [dl_sy], 1
    jge .dy_pos
    neg eax
    mov dword [dl_sy], -1
.dy_pos:
    neg eax
    mov [dl_dy], eax

    ; err = dx + dy
    mov eax, [dl_dx]
    add eax, [dl_dy]
    mov [dl_err], eax

.b_loop:
    ; Draw Pixel (with window clipping!)
    mov eax, [dl_x0]
    mov ebx, [dl_y0]
    cmp eax, 1
    jl .skip_pixel
    cmp eax, 254
    jg .skip_pixel
    cmp ebx, 11
    jl .skip_pixel
    cmp ebx, 254
    jg .skip_pixel
    
    ; OPTIMIZATION: Replaced slow 'imul ebx, 256' with fast 'shl ebx, 8'
    shl ebx, 8
    add ebx, eax
    shl ebx, 2
    add ebx, [win_ptr]
    mov eax, [dl_color]
    mov [ebx], eax
.skip_pixel:
    ; Check if done
    mov eax, [dl_x0]
    cmp eax, [dl_x1]
    jne .b_cont
    mov eax, [dl_y0]
    cmp eax, [dl_y1]
    je .b_done
.b_cont:
    mov eax, [dl_err]
    shl eax, 1
    cmp eax, [dl_dy]
    jl .check_dx
    mov ebx, [dl_err]
    add ebx, [dl_dy]
    mov [dl_err], ebx
    mov ebx, [dl_x0]
    add ebx, [dl_sx]
    mov [dl_x0], ebx
.check_dx:
    cmp eax, [dl_dx]
    jg .b_loop
    mov ebx, [dl_err]
    add ebx, [dl_dx]
    mov [dl_err], ebx
    mov ebx, [dl_y0]
    add ebx, [dl_sy]
    mov [dl_y0], ebx
    jmp .b_loop
.b_done:
    ret

clear_content:
    ; Only clear the inside of the window, leaving the borders intact!
    mov edi, [win_ptr]
    add edi, 11268
    mov edx, 244            
.content_loop:
    mov ecx, 254
    mov eax, 0x000000       ; Pitch Black Background
    rep stosd
    add edi, 8              
    dec edx
    jnz .content_loop
    ret

; =====================================================================
; 3D DATA STRUCTURES
; =====================================================================
section .data
    msg_start db 'Starting 3D Software Renderer...', 0x0A, 0
    msg_start_len equ $ - msg_start
    msg_done db '3D Demo complete! Press ENTER to exit...', 0x0A, 0
    msg_done_len equ $ - msg_done

    ; The 8 Vertices of our Cube (Size 50)
    vertices:
        dd -50, -50, -50  ; 0
        dd  50, -50, -50  ; 1
        dd  50,  50, -50  ; 2
        dd -50,  50, -50  ; 3
        dd -50, -50,  50  ; 4
        dd  50, -50,  50  ; 5
        dd  50,  50,  50  ; 6
        dd -50,  50,  50  ; 7

    ; The 12 Edges connecting the Vertices
    edges:
        db 0,1, 1,2, 2,3, 3,0  ; Back face
        db 4,5, 5,6, 6,7, 7,4  ; Front face
        db 0,4, 1,5, 2,6, 3,7  ; Connecting struts

    ; Pre-calculated Sine Wave values for lightning-fast fixed-point math!
    sin_table:
        db 0, 3, 6, 9, 12, 15, 18, 21, 24, 28, 31, 34, 37, 40, 43, 46
        db 48, 51, 54, 57, 60, 63, 65, 68, 71, 73, 76, 78, 81, 83, 85, 88
        db 90, 92, 94, 96, 98, 100, 102, 104, 106, 108, 109, 111, 112, 114, 115, 117
        db 118, 119, 120, 121, 122, 123, 124, 124, 125, 126, 126, 126, 127, 127, 127, 127
        db 127, 127, 127, 127, 126, 126, 126, 125, 124, 124, 123, 122, 121, 120, 119, 118
        db 117, 115, 114, 112, 111, 109, 108, 106, 104, 102, 100, 98, 96, 94, 92, 90
        db 88, 85, 83, 81, 78, 76, 73, 71, 68, 65, 63, 60, 57, 54, 51, 48
        db 46, 43, 40, 37, 34, 31, 28, 24, 21, 18, 15, 12, 9, 6, 3, 0
        db 0, -3, -6, -9, -12, -15, -18, -21, -24, -28, -31, -34, -37, -40, -43, -46
        db -48, -51, -54, -57, -60, -63, -65, -68, -71, -73, -76, -78, -81, -83, -85, -88
        db -90, -92, -94, -96, -98, -100, -102, -104, -106, -108, -109, -111, -112, -114, -115, -117
        db -118, -119, -120, -121, -122, -123, -124, -124, -125, -126, -126, -126, -127, -127, -127, -127
        db -127, -127, -127, -127, -126, -126, -126, -125, -124, -124, -123, -122, -121, -120, -119, -118
        db -117, -115, -114, -112, -111, -109, -108, -106, -104, -102, -100, -98, -96, -94, -92, -90
        db -88, -85, -83, -81, -78, -76, -73, -71, -68, -65, -63, -60, -57, -54, -51, -48
        db -46, -43, -40, -37, -34, -31, -28, -24, -21, -18, -15, -12, -9, -6, -3, 0

section .bss
    win_ptr resd 1
    frame_count resd 1
    input_buf resb 32
    angle_a resb 1
    angle_b resb 1
    sin_a resd 1
    cos_a resd 1
    sin_b resd 1
    cos_b resd 1
    val_x resd 1
    val_y resd 1
    val_z resd 1
    val_x1 resd 1
    val_z1 resd 1
    val_y2 resd 1
    val_z2 resd 1
    curr_vertex resd 1
    curr_edge resd 1
    proj_x resd 8
    proj_y resd 8
    dl_x0 resd 1
    dl_y0 resd 1
    dl_x1 resd 1
    dl_y1 resd 1
    dl_dx resd 1
    dl_dy resd 1
    dl_sx resd 1
    dl_sy resd 1
    dl_err resd 1
    dl_color resd 1