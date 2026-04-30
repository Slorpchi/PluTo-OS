; =====================================================================
; NoVa OS - Advanced 32-bit Monolithic Kernel (v1.6.0 "Doom Ready")
; Includes PMM, Paging, Tasking, FAT32 VFS, LFN, Ring 3 Execution, Mouse,
; Window Manager, XOR Renderer, 1000Hz PIT, and Live Keyboard Polling!
; =====================================================================

; --- Multiboot Header ---
MBALIGN  equ  1 << 0
MEMINFO  equ  1 << 1
VIDMODE  equ  1 << 2  
FLAGS    equ  MBALIGN | MEMINFO | VIDMODE
MAGIC    equ  0x1BADB002
CHECKSUM equ -(MAGIC + FLAGS)

section .multiboot
align 4
multiboot_header:
    dd MAGIC
    dd FLAGS
    dd CHECKSUM
    dd 0, 0, 0, 0, 0 
    dd 0             
    dd 1024          
    dd 768           
    dd 32            

; =====================================================================
; TEXT SECTION (Executable Code - Read Only)
; =====================================================================
section .text
global _start

_start:
    cli
    cld                     
    mov esp, stack_top

    mov eax, [ebx + 88]          
    mov [vbe_framebuffer], eax
    mov eax, [ebx + 96]          
    mov [vbe_pitch], eax
    mov eax, [ebx + 100]         
    mov [vbe_width], eax
    mov eax, [ebx + 104]         
    mov [vbe_height], eax
    mov cl, [ebx + 108]          
    mov [vbe_bpp], cl

    mov eax, [ebx]          
    test eax, 1 << 3        
    jz .no_ramdisk
    mov eax, [ebx + 20]     
    test eax, eax
    jz .no_ramdisk
    mov eax, [ebx + 24]     
    mov edx, [eax]          
    mov [ramdisk_start], edx
    mov ecx, [eax + 4]      
    mov [ramdisk_end], ecx
.no_ramdisk:

    mov byte [command_ready], 0
    mov byte [fat32_mounted], 0
    mov byte [in_user_space], 0   
    mov byte [mouse_is_drawn], 0

    call init_pmm
    call init_gdt
    call init_idt           
    call init_pic
    call init_paging
    call init_vesa_terminal 
    call init_scheduler
    call init_mouse         

    mov eax, isr_timer_scheduler
    mov ebx, 32
    call set_idt_gate
    
    mov eax, isr_keyboard
    mov ebx, 33
    call set_idt_gate

    mov eax, isr_mouse      
    mov ebx, 44
    call set_idt_gate

    mov eax, isr_syscall
    mov ebx, 128
    call set_idt_gate

    sti

    mov eax, vfs_root
    mov [current_dir_ptr], eax

    mov esi, msg_welcome
    mov ah, 0x0B
    call print_string

    call bin_f32mount       

    call shell_main

.kernel_halt:
    hlt
    jmp .kernel_halt

; =====================================================================
; PMM - PHYSICAL MEMORY MANAGER
; =====================================================================
init_pmm:
    mov dword [mem_heap_ptr], 0x5000000 ; Heap at 80MB to protect RAM Disk
    mov dword [mem_total_used], 0
    ret

k_malloc:
    push ebx
    push ecx
    push edx
    push edi

    ; Force strict 16-byte alignment
    add eax, 15
    and eax, ~15
    add eax, 16                  
    mov ecx, eax
    mov ebx, 0x5000000           
.search_loop:
    cmp ebx, [mem_heap_ptr]
    jae .grow_heap
    cmp dword [ebx + 4], 1
    jne .next_block
    mov edx, [ebx]
    cmp edx, ecx
    jb .next_block
    mov dword [ebx + 4], 0
    add [mem_total_used], edx
    mov eax, ebx
    add eax, 16                  
    jmp .zero_and_done
.next_block:
    add ebx, [ebx]
    jmp .search_loop
.grow_heap:
    mov [ebx], ecx
    mov dword [ebx + 4], 0
    mov eax, ebx
    add eax, 16                  
    add [mem_heap_ptr], ecx
    add [mem_total_used], ecx

.zero_and_done:
    push eax
    push ecx
    mov edi, eax
    sub ecx, 16                  
    shr ecx, 2                   
    push eax
    xor eax, eax
    rep stosd                    
    pop eax
    pop ecx
    pop eax

    pop edi
    pop edx
    pop ecx
    pop ebx
    ret

k_free:
    push ebx
    test eax, eax
    jz .done
    sub eax, 16                  
    mov dword [eax + 4], 1
    mov ebx, [eax]
    sub [mem_total_used], ebx
.done:
    pop ebx
    ret

; =====================================================================
; VIRTUAL MEMORY MANAGER (Paging)
; =====================================================================
init_paging:
    mov edi, page_directory
    mov ecx, 1024
    xor eax, eax
    rep stosd
    
    mov edi, page_tables
    mov ecx, 65536          
    xor eax, eax
.map_loop:
    mov edx, eax
    shl edx, 12             
    or edx, 7               
    mov [edi], edx
    add edi, 4
    inc eax
    loop .map_loop

    mov edi, page_directory
    mov eax, page_tables
    mov ecx, 64
.pd_loop:
    mov edx, eax
    or edx, 7
    mov [edi], edx
    add edi, 4
    add eax, 4096
    loop .pd_loop

    mov eax, [vbe_framebuffer]
    shr eax, 22                 
    mov edi, page_directory
    mov ebx, page_table_vesa
    or ebx, 7
    mov [edi + eax * 4], ebx    
    
    mov edi, page_table_vesa
    mov eax, [vbe_framebuffer]
    and eax, 0xFFC00000         
    mov ecx, 1024               
.map_vesa_loop:
    mov edx, eax
    or edx, 7                   
    mov [edi], edx
    add eax, 4096
    add edi, 4
    loop .map_vesa_loop

    mov eax, page_directory
    mov cr3, eax
    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax
    ret

vmm_create_dir:
    pushad
    mov eax, 4096
    call k_malloc 
    mov edi, eax
    mov [current_pd], eax
    
    push edi
    mov ecx, 1024
    xor eax, eax
    rep stosd
    pop edi
    
    mov esi, page_directory
    mov edi, [current_pd]
    mov ecx, 64
    rep movsd
    
    mov edi, [current_pd]
    mov eax, [vbe_framebuffer]
    shr eax, 22
    mov edx, [page_directory + eax * 4]
    mov [edi + eax * 4], edx
    
    popad
    mov eax, [current_pd]
    ret

; =====================================================================
; SCHEDULER ENGINE
; =====================================================================
init_scheduler:
    mov dword [current_task], 0
    mov eax, task1_stack_top
    sub eax, 4
    mov dword [eax], 0x202 
    sub eax, 4
    mov dword [eax], 0x08
    sub eax, 4
    mov dword [eax], idle_task    
    sub eax, 32
    mov [task_esp + 4], eax
    ret

isr_timer_scheduler:
    pushad
    mov eax, [current_task]
    mov edx, esp
    mov [task_esp + eax*4], edx
    inc eax
    and eax, 1
    mov [current_task], eax
    mov esp, [task_esp + eax*4]
    inc dword [timer_ticks]
    mov al, 0x20
    out 0x20, al
    popad
    iretd

idle_task:
.loop:
    hlt                     
    jmp .loop

; =====================================================================
; INTEGRATED SHELL (sh)
; =====================================================================
shell_main:
    call shell_prompt
.loop:
    cmp byte [command_ready], 1
    je .run_cmd
    hlt 
    jmp .loop

.run_cmd:
    mov byte [command_ready], 0
    call process_command
    call shell_prompt
    jmp .loop

shell_prompt:
    mov dword [kb_buffer_pos], 0
    mov esi, msg_user
    mov ah, 0x0B
    call print_string
    mov esi, [current_dir_ptr]
    mov ah, 0x0E
    call print_string
    mov esi, msg_prompt_sym
    mov ah, 0x0F
    call print_string
    ret

process_command:
    mov esi, kb_buffer
.trim_trailing:
    mov ebx, [kb_buffer_pos]
    test ebx, ebx
    jz .check_empty
    dec ebx
    cmp byte [kb_buffer + ebx], ' '
    jne .check_empty
    mov byte [kb_buffer + ebx], 0    
    mov [kb_buffer_pos], ebx
    jmp .trim_trailing
    
.check_empty:
    cmp byte [kb_buffer], 0
    je .done

    mov edi, cmd_cd
    mov ecx, 2
    call strncmp
    je .try_cd

    mov edi, cmd_cat
    mov ecx, 3
    call strncmp
    je .try_cat

    mov edi, cmd_run
    mov ecx, 4
    call strncmp
    je .try_run

    mov edi, cmd_f32read
    mov ecx, 7
    call strncmp
    je .try_f32read
    
    mov edi, cmd_f32write
    mov ecx, 8
    call strncmp
    je .try_f32write

    mov edi, cmd_f32cd
    mov ecx, 5
    call strncmp
    je .try_f32cd

    mov edi, cmd_f32rm
    mov ecx, 5
    call strncmp
    je .try_f32rm

    mov edi, cmd_f32mkdir
    mov ecx, 8
    call strncmp
    je .try_f32mkdir

    mov edi, cmd_clear
    call strcmp
    je sys_do_clear

    mov edi, cmd_help
    call strcmp
    je sys_do_help

    jmp .search_bin

.try_cd:
    mov al, [kb_buffer + 2]
    cmp al, ' '
    je sys_do_cd
    cmp al, 0
    je sys_do_cd
    cmp al, '.'
    jne .search_bin
    jmp .search_bin

.try_cat:
    mov al, [kb_buffer + 3]
    cmp al, ' '
    je sys_do_cat
    cmp al, 0
    je sys_do_cat
    jmp .search_bin

.try_run:
    jmp bin_run

.try_f32read:
    mov al, [kb_buffer + 7]
    cmp al, ' '
    je bin_f32read
    cmp al, 0
    je bin_f32read
    jmp .search_bin

.try_f32write:
    mov al, [kb_buffer + 8]
    cmp al, ' '
    je bin_f32write
    cmp al, 0
    je bin_f32write
    jmp .search_bin

.try_f32cd:
    mov al, [kb_buffer + 5]
    cmp al, ' '
    je bin_f32cd
    cmp al, 0
    je bin_f32cd
    jmp .search_bin

.try_f32rm:
    mov al, [kb_buffer + 5]
    cmp al, ' '
    je bin_f32rm
    cmp al, 0
    je bin_f32rm
    jmp .search_bin

.try_f32mkdir:
    mov al, [kb_buffer + 8]
    cmp al, ' '
    je bin_f32mkdir
    cmp al, 0
    je bin_f32mkdir
    jmp .search_bin

.search_bin:
    call find_in_bin
    test eax, eax
    jz .not_found
    cmp eax, bin_test_syscall
    je execute_ring3
    call eax
    jmp .done
.not_found:
    mov esi, msg_unknown
    mov ah, 0x0C
    call print_string
    mov esi, kb_buffer
    mov ah, 0x0C        
    call print_string
    mov esi, msg_newline
    call print_string
.done:
    ret

find_in_bin:
    mov esi, vfs_table
.loop:
    cmp byte [esi], 0
    je .fail
    mov eax, [esi + 16]
    cmp eax, vfs_bin
    jne .next
    push esi
    mov edi, kb_buffer
    call strcmp
    pop esi
    je .match
.next:
    add esi, 32
    jmp .loop
.match:
    mov eax, [esi + 28]
    ret
.fail:
    xor eax, eax
    ret

; =====================================================================
; ADVANCED FAT32 ENGINE
; =====================================================================

lba_from_cluster:
    push ebx
    sub eax, 2                          
    movzx ebx, byte [fat32_sectors_per_clust]
    imul eax, ebx                       
    add eax, [fat32_data_start_lba]     
    pop ebx
    ret

bin_f32format:
    mov esi, msg_formatting
    mov ah, 0x0E
    call print_string
    
    mov edi, sector_buffer
    mov ecx, 128            
    xor eax, eax
    rep stosd
    
    mov byte [sector_buffer + 0], 0xEB
    mov byte [sector_buffer + 1], 0x58
    mov byte [sector_buffer + 2], 0x90
    mov dword [sector_buffer + 3], 'NoVa'
    mov dword [sector_buffer + 7], ' OS '
    mov word [sector_buffer + 11], 512    
    mov byte [sector_buffer + 13], 1      
    mov word [sector_buffer + 14], 32     
    mov byte [sector_buffer + 16], 2      
    mov dword [sector_buffer + 36], 1000  
    mov dword [sector_buffer + 44], 2     
    mov dword [sector_buffer + 71], 'NOVA'
    mov dword [sector_buffer + 82], 'FAT3'
    mov dword [sector_buffer + 86], '2   '
    mov word [sector_buffer + 510], 0xAA55
    
    mov eax, 0
    mov esi, sector_buffer
    call ata_write_sector

    mov edi, sector_buffer
    mov ecx, 128
    xor eax, eax
    rep stosd
    mov dword [sector_buffer + 0], 0x0FFFFFF8 
    mov dword [sector_buffer + 4], 0xFFFFFFFF 
    mov dword [sector_buffer + 8], 0x0FFFFFFF 
    mov eax, 32
    mov esi, sector_buffer
    call ata_write_sector

    mov edi, sector_buffer
    mov ecx, 128
    xor eax, eax
    rep stosd
    mov eax, 2032
    mov esi, sector_buffer
    call ata_write_sector
    
    mov esi, msg_format_ok
    mov ah, 0x0A
    call print_string

    mov byte [fm_needs_update], 1 
    call bin_f32mount
    ret

bin_f32mount:
    mov eax, 0
    mov edi, sector_buffer
    call ata_read_sector
    mov ax, [sector_buffer + 510]
    cmp ax, 0xAA55
    jne .no_fs

    mov eax, [sector_buffer + 82]
    cmp eax, 'FAT3'
    jne .no_fs

    mov ax, [sector_buffer + 11]
    mov [fat32_bytes_per_sector], ax
    mov al, [sector_buffer + 13]
    mov [fat32_sectors_per_clust], al
    mov ax, [sector_buffer + 14]
    mov [fat32_reserved_sectors], ax
    mov al, [sector_buffer + 16]
    mov [fat32_num_fats], al
    mov eax, [sector_buffer + 36]
    mov [fat32_sectors_per_fat], eax
    mov eax, [sector_buffer + 44]
    mov [fat32_root_cluster], eax
    mov [fat32_current_cluster], eax

    movzx eax, word [fat32_reserved_sectors]
    mov [fat32_fat_start_lba], eax

    movzx ebx, byte [fat32_num_fats]
    mov ecx, [fat32_sectors_per_fat]
    imul ebx, ecx
    add eax, ebx
    mov [fat32_data_start_lba], eax

    mov byte [fat32_mounted], 1
    mov byte [fm_needs_update], 1 

    mov esi, msg_f32_found
    mov ah, 0x0A
    call print_string
    ret
.no_fs:
    mov esi, msg_no_mbr
    mov ah, 0x0C
    call print_string
    ret

bin_f32ls:
    cmp byte [fat32_mounted], 1
    jne .not_mounted

    mov esi, msg_fat_root
    mov ah, 0x0A                         
    call print_string

    push edi
    push ecx
    mov edi, lfn_buffer
    mov ecx, 64
    xor eax, eax
    rep stosd
    pop ecx
    pop edi

    mov byte [lfn_buffer], 0    
    mov eax, [fat32_current_cluster]
    call lba_from_cluster
    movzx edx, byte [fat32_sectors_per_clust]

.read_next_sector:
    push eax
    push edx

    mov edi, sector_buffer
    call ata_read_sector

    mov esi, sector_buffer
    mov ecx, 16                 
.parse_loop:
    cmp byte [esi], 0           
    je .done_early
    cmp byte [esi], 0xE5        
    je .next_entry
    
    mov al, [esi + 11]          
    cmp al, 0x0F                
    je .process_lfn

    mov ah, 0x0F                         
    test al, 0x10               
    jz .check_lfn
    mov ah, 0x09                
.check_lfn:
    push eax
    mov al, ' '
    call print_char
    pop eax

    cmp byte [lfn_buffer], 0
    je .print_83

    push esi
    mov esi, lfn_buffer
    call print_string
    pop esi
    
    push edi
    push ecx
    mov edi, lfn_buffer
    mov ecx, 64
    xor eax, eax
    rep stosd
    pop ecx
    pop edi
    
    jmp .newline

.print_83:
    push esi
    push ecx
    mov ecx, 11
    call print_n_chars                   
    pop ecx
    pop esi
.newline:
    push eax
    push esi                    
    mov esi, msg_newline
    call print_string
    pop esi                     
    pop eax
    jmp .next_entry

.process_lfn:
    push eax
    push ebx
    push edx
    push edi

    xor eax, eax                
    mov al, [esi]               
    and al, 0x3F                
    jz .skip_lfn                
    cmp al, 20                  
    ja .skip_lfn

    dec eax                     
    imul eax, eax, 13           
    
    mov edi, lfn_buffer
    add edi, eax                

    mov al, [esi + 1]
    mov [edi + 0], al
    mov al, [esi + 3]
    mov [edi + 1], al
    mov al, [esi + 5]
    mov [edi + 2], al
    mov al, [esi + 7]
    mov [edi + 3], al
    mov al, [esi + 9]
    mov [edi + 4], al
    mov al, [esi + 14]
    mov [edi + 5], al
    mov al, [esi + 16]
    mov [edi + 6], al
    mov al, [esi + 18]
    mov [edi + 7], al
    mov al, [esi + 20]
    mov [edi + 8], al
    mov al, [esi + 22]
    mov [edi + 9], al
    mov al, [esi + 24]
    mov [edi + 10], al
    mov al, [esi + 28]
    mov [edi + 11], al
    mov al, [esi + 30]
    mov [edi + 12], al
    
.skip_lfn:
    pop edi
    pop edx
    pop ebx
    pop eax

.next_entry:
    add esi, 32                          
    dec ecx
    jnz .parse_loop

    pop edx
    pop eax
    inc eax
    dec edx
    jnz .read_next_sector
    ret

.done_early:
    pop edx
    pop eax
    ret

.not_mounted:
    mov esi, msg_not_mounted
    mov ah, 0x0C
    call print_string
    ret

bin_f32read:
    cmp byte [fat32_mounted], 1
    jne bin_f32ls.not_mounted

    cmp byte [kb_buffer + 8], 0
    je .no_arg

    mov esi, kb_buffer + 8
    mov edi, fat_target_name
    call format_fat_name

    mov eax, [fat32_current_cluster]
    call lba_from_cluster
    mov edi, sector_buffer
    call ata_read_sector

    mov esi, sector_buffer
    mov ecx, 16                 
.search_loop:
    cmp byte [esi], 0           
    je .not_found
    cmp byte [esi], 0xE5        
    je .next_entry
    mov al, [esi + 11]          
    cmp al, 0x0F                
    je .next_entry

    push esi
    mov edi, fat_target_name
    push ecx
    mov ecx, 11
    repe cmpsb
    pop ecx
    pop esi
    je .read_file

.next_entry:
    add esi, 32
    dec ecx
    jnz .search_loop

.not_found:
    mov esi, msg_file_miss
    mov ah, 0x0C
    call print_string
    ret

.read_file:
    movzx eax, word [esi + 20]
    shl eax, 16
    mov ax, word [esi + 26]
    
    call lba_from_cluster
    mov edi, sector_buffer
    call ata_read_sector
    
    mov byte [sector_buffer + 511], 0
    mov esi, sector_buffer
    mov ah, 0x0F
    call print_string
    mov esi, msg_newline
    call print_string
    ret

.no_arg:
    mov esi, msg_fatr_err
    mov ah, 0x0C
    call print_string
    ret

bin_f32write:
    cmp byte [fat32_mounted], 1
    jne bin_f32ls.not_mounted

    cmp byte [kb_buffer + 9], 0
    je .no_arg

    mov esi, kb_buffer + 9
    mov edi, fat_target_name
    call format_fat_name

    mov esi, kb_buffer
.search_flag:
    cmp byte [esi], 0
    je .use_default_text
    push esi
    mov edi, str_text_touch
    mov ecx, 14
    repe cmpsb
    pop esi
    je .found_flag
    inc esi
    jmp .search_flag
.found_flag:
    add esi, 14
    mov [custom_text_ptr], esi
    jmp .start_write
.use_default_text:
    mov dword [custom_text_ptr], msg_write_data

.start_write:
    mov eax, [fat32_current_cluster]
    call lba_from_cluster
    mov edi, sector_buffer
    call ata_read_sector

    mov esi, sector_buffer
    mov edx, 16
.check_exists:
    cmp byte [esi], 0
    je .file_is_new
    cmp byte [esi], 0xE5
    je .check_next
    mov al, [esi + 11]
    cmp al, 0x0F
    je .check_next

    push esi
    mov edi, fat_target_name
    mov ecx, 11
    repe cmpsb
    pop esi
    je .overwrite_existing

.check_next:
    add esi, 32
    dec edx
    jnz .check_exists

.file_is_new:
    mov eax, [fat32_fat_start_lba]
    mov edi, fat_buffer
    call ata_read_sector

    mov ecx, 3                  
.find_cluster:
    mov eax, ecx
    shl eax, 2                  
    cmp dword [fat_buffer + eax], 0
    je .found_cluster
    inc ecx
    cmp ecx, 128
    jl .find_cluster

    mov esi, msg_disk_full
    mov ah, 0x0C
    call print_string
    ret

.found_cluster:
    push ecx
    mov eax, ecx
    shl eax, 2
    mov dword [fat_buffer + eax], 0x0FFFFFFF
    mov eax, [fat32_fat_start_lba]
    mov esi, fat_buffer
    call ata_write_sector

    pop ecx                     
    push ecx
    jmp .write_data_to_cluster

.overwrite_existing:
    mov ax, [esi + 20]
    shl eax, 16
    mov ax, [esi + 26]
    mov ecx, eax
    push ecx                    

.write_data_to_cluster:
    mov edi, sector_buffer
    push ecx
    mov ecx, 128
    xor eax, eax
    rep stosd
    pop ecx

    mov esi, [custom_text_ptr]
    mov edi, sector_buffer
.copy_str:
    lodsb
    stosb
    test al, al
    jnz .copy_str

    mov eax, edi
    sub eax, sector_buffer
    dec eax                     
    push eax                    

    mov eax, ecx
    call lba_from_cluster
    mov esi, sector_buffer
    call ata_write_sector

    mov eax, [fat32_current_cluster]
    call lba_from_cluster
    mov edi, sector_buffer
    call ata_read_sector

    pop ebx                     
    pop ecx                     

    mov esi, sector_buffer
    mov edx, 16
.find_dir_slot_edit:
    mov al, [esi]
    test al, al
    jz .make_new_entry
    cmp al, 0xE5
    je .make_new_entry

    push esi
    mov edi, fat_target_name
    push ecx
    mov ecx, 11
    repe cmpsb
    pop ecx
    pop esi
    je .update_size_only
    
    add esi, 32
    dec edx
    jnz .find_dir_slot_edit

.make_new_entry:
    mov edi, esi
    push edi
    mov esi, fat_target_name
    push ecx
    mov ecx, 11
    rep movsb
    pop ecx
    pop edi

    mov byte [edi + 11], 0x20   

    push edi
    add edi, 12
    push ecx
    mov ecx, 20
    xor al, al
    rep stosb
    pop ecx
    pop edi

    mov eax, ecx
    shr eax, 16
    mov word [edi + 20], ax     
    mov word [edi + 26], cx     
    
.update_size_only:
    mov dword [esi + 28], ebx   

    mov eax, [fat32_current_cluster]
    call lba_from_cluster
    mov esi, sector_buffer
    call ata_write_sector

    mov byte [fm_needs_update], 1 
    mov esi, msg_write_ok
    mov ah, 0x0A
    call print_string
    ret

.no_arg:
    mov esi, msg_fatw_err
    mov ah, 0x0C
    call print_string
    ret

bin_f32cd:
    cmp byte [fat32_mounted], 1
    jne bin_f32ls.not_mounted

    cmp byte [kb_buffer + 6], 0    
    je .go_root

    cmp word [kb_buffer + 6], '..'
    je .handle_parent

    mov esi, kb_buffer + 6
    mov edi, fat_target_name
    call format_fat_name
    jmp .read_current_dir

.handle_parent:
    mov esi, dot_dot_name
    mov edi, fat_target_name
    mov ecx, 11
    rep movsb

.read_current_dir:
    mov eax, [fat32_current_cluster]
    call lba_from_cluster
    mov edi, sector_buffer
    call ata_read_sector

    mov esi, sector_buffer
    mov edx, 16                 
.find_dir:
    mov al, [esi]
    test al, al                 
    jz .not_found
    cmp al, 0xE5                
    je .next_entry

    mov al, [esi + 11]
    and al, 0x10
    jz .next_entry              

    push esi
    mov edi, fat_target_name
    mov ecx, 11
    repe cmpsb
    pop esi
    je .found

.next_entry:
    add esi, 32
    dec edx
    jnz .find_dir

.not_found:
    mov esi, msg_dir_not_found
    mov ah, 0x0C
    call print_string
    ret

.found:
    mov ax, [esi + 20]          
    shl eax, 16
    mov ax, [esi + 26]          

    test eax, eax
    jnz .set_cluster
    mov eax, [fat32_root_cluster]
    
.set_cluster:
    mov [fat32_current_cluster], eax

    cmp eax, [fat32_root_cluster]
    je .go_root_prompt
    cmp eax, 0
    je .go_root_prompt

    mov esi, fat_target_name
    mov edi, fat32_path_str
    mov byte [edi], '/'
    inc edi
    mov ecx, 11
.copy_name:
    lodsb
    cmp al, ' '
    je .skip_space
    stosb
.skip_space:
    loop .copy_name
    mov byte [edi], 0
    mov dword [current_dir_ptr], fat32_path_str
    jmp .done_cd

.go_root_prompt:
    mov dword [current_dir_ptr], vfs_root

.done_cd:
    mov byte [fm_needs_update], 1 
    mov esi, msg_dir_changed
    mov ah, 0x0A
    call print_string
    ret

.go_root:
    mov eax, [fat32_root_cluster]
    mov [fat32_current_cluster], eax
    mov dword [current_dir_ptr], vfs_root
    mov byte [fm_needs_update], 1 
    mov esi, msg_dir_changed
    mov ah, 0x0A
    call print_string
    ret

bin_f32rm:
    cmp byte [fat32_mounted], 1
    jne bin_f32ls.not_mounted

    cmp byte [kb_buffer + 6], 0
    je .no_arg

    mov esi, kb_buffer + 6
    mov edi, fat_target_name
    call format_fat_name

    mov eax, [fat32_current_cluster]
    call lba_from_cluster
    mov edi, sector_buffer
    call ata_read_sector

    mov esi, sector_buffer
    mov ecx, 16
.search_loop:
    cmp byte [esi], 0
    je .not_found
    cmp byte [esi], 0xE5
    je .next_entry
    mov al, [esi + 11]
    cmp al, 0x0F
    je .next_entry

    push esi
    mov edi, fat_target_name
    push ecx
    mov ecx, 11
    repe cmpsb
    pop ecx
    pop esi
    je .delete_entry

.next_entry:
    add esi, 32
    dec ecx
    jnz .search_loop

.not_found:
    mov esi, msg_file_miss
    mov ah, 0x0C
    call print_string
    ret

.delete_entry:
    mov byte [esi], 0xE5
    movzx eax, word [esi + 20]
    shl eax, 16
    mov ax, word [esi + 26]
    push eax

    mov eax, [fat32_current_cluster]
    call lba_from_cluster
    mov esi, sector_buffer
    call ata_write_sector

    pop ecx                     
    mov eax, [fat32_fat_start_lba]
    mov edi, fat_buffer
    call ata_read_sector

.free_chain:
    and ecx, 0x0FFFFFFF         
    cmp ecx, 0x0FFFFFF8         
    jae .done_freeing
    cmp ecx, 0                  
    je .done_freeing

    mov eax, ecx
    shl eax, 2                  
    mov edx, [fat_buffer + eax] 
    mov dword [fat_buffer + eax], 0 
    mov ecx, edx                
    jmp .free_chain

.done_freeing:
    mov eax, [fat32_fat_start_lba]
    mov esi, fat_buffer
    call ata_write_sector

    mov byte [fm_needs_update], 1 
    mov esi, msg_deleted
    mov ah, 0x0A
    call print_string
    ret

.no_arg:
    mov esi, msg_rm_err
    mov ah, 0x0C
    call print_string
    ret

bin_f32mkdir:
    cmp byte [fat32_mounted], 1
    jne bin_f32ls.not_mounted

    cmp byte [kb_buffer + 9], 0
    je .no_arg

    mov esi, kb_buffer + 9
    mov edi, fat_target_name
    call format_fat_name

    mov eax, [fat32_fat_start_lba]
    mov edi, fat_buffer
    call ata_read_sector

    mov ecx, 3                  
.find_cluster:
    mov eax, ecx
    shl eax, 2                  
    cmp dword [fat_buffer + eax], 0
    je .found_cluster
    inc ecx
    cmp ecx, 128
    jl .find_cluster

    mov esi, msg_disk_full
    mov ah, 0x0C
    call print_string
    ret

.found_cluster:
    mov eax, ecx
    shl eax, 2
    mov dword [fat_buffer + eax], 0x0FFFFFFF 
    mov eax, [fat32_fat_start_lba]
    mov esi, fat_buffer
    call ata_write_sector

    mov edi, sector_buffer
    push ecx
    mov ecx, 128
    xor eax, eax
    rep stosd
    pop ecx

    mov esi, dot_name
    mov edi, sector_buffer
    push ecx
    mov ecx, 11
    rep movsb
    pop ecx
    mov byte [sector_buffer + 11], 0x10 
    mov eax, ecx
    shr eax, 16
    mov word [sector_buffer + 20], ax
    mov word [sector_buffer + 26], cx

    mov esi, dot_dot_name
    mov edi, sector_buffer + 32
    push ecx
    mov ecx, 11
    rep movsb
    pop ecx
    mov byte [sector_buffer + 32 + 11], 0x10
    mov eax, [fat32_current_cluster]
    cmp eax, [fat32_root_cluster]
    jne .not_root_parent
    xor eax, eax 
.not_root_parent:
    mov ebx, eax
    shr eax, 16
    mov word [sector_buffer + 32 + 20], ax
    mov word [sector_buffer + 32 + 26], bx

    mov eax, ecx
    call lba_from_cluster
    mov esi, sector_buffer
    call ata_write_sector

    mov eax, [fat32_current_cluster]
    call lba_from_cluster
    mov edi, sector_buffer
    call ata_read_sector

    mov esi, sector_buffer
    mov edx, 16
.find_dir_slot:
    mov al, [esi]
    test al, al
    jz .make_entry
    cmp al, 0xE5
    je .make_entry
    add esi, 32
    dec edx
    jnz .find_dir_slot

    mov esi, msg_dir_full
    mov ah, 0x0C
    call print_string
    ret

.make_entry:
    mov edi, esi
    push edi                    
    mov esi, fat_target_name
    push ecx
    mov ecx, 11
    rep movsb
    pop ecx
    pop edi                     

    mov byte [edi + 11], 0x10   
    
    push edi
    add edi, 12
    push ecx
    mov ecx, 20
    xor al, al
    rep stosb
    pop ecx
    pop edi

    mov eax, ecx
    shr eax, 16
    mov word [edi + 20], ax     
    mov word [edi + 26], cx     
    mov dword [edi + 28], 0     

    mov eax, [fat32_current_cluster]
    call lba_from_cluster
    mov esi, sector_buffer
    call ata_write_sector

    mov byte [fm_needs_update], 1 
    mov esi, msg_mkdir_ok
    mov ah, 0x0A
    call print_string
    ret

.no_arg:
    mov esi, msg_mkdir_err
    mov ah, 0x0C
    call print_string
    ret

bin_run:
    cmp byte [fat32_mounted], 1
    jne bin_f32ls.not_mounted

    cmp byte [kb_buffer + 4], 0
    je .no_arg

    mov esi, kb_buffer + 4
    mov edi, fat_target_name
    call format_fat_name

    mov eax, [fat32_current_cluster]
    call lba_from_cluster
    mov edi, sector_buffer
    call ata_read_sector

    mov esi, sector_buffer
    mov ecx, 16                 
.search_loop:
    cmp byte [esi], 0           
    je .not_found
    cmp byte [esi], 0xE5        
    je .next_entry
    mov al, [esi + 11]          
    cmp al, 0x0F                
    je .next_entry
    test al, 0x10               
    jnz .next_entry

    push esi
    mov edi, fat_target_name
    push ecx
    mov ecx, 11
    repe cmpsb
    pop ecx
    pop esi
    je .load_file

.next_entry:
    add esi, 32
    dec ecx
    jnz .search_loop

.not_found:
    mov esi, msg_file_miss
    mov ah, 0x0C
    call print_string
    ret

.load_file:
    movzx eax, word [esi + 20]
    shl eax, 16
    mov ax, word [esi + 26]
    mov ecx, eax                

    mov eax, [esi + 28]         
    test eax, eax
    jz .empty_file

    ; === CRITICAL KERNEL HEAP FIX ===
    ; Add 64KB padding to the ELF loader allocation
    add eax, 65536
    call k_malloc
    mov [current_app_ptr], eax  
    mov ebx, eax                
    push eax                    

.load_cluster:
    mov eax, ecx
    push ecx                    
    call lba_from_cluster
    
    movzx edx, byte [fat32_sectors_per_clust]
.read_sectors:
    push eax                    
    push edx                    
    
    mov edi, sector_buffer
    call ata_read_sector
    
    mov esi, sector_buffer
    mov edi, ebx
    push ecx
    mov ecx, 128                
    rep movsd                   
    mov ebx, edi                
    pop ecx
    
    pop edx
    pop eax
    inc eax                     
    dec edx
    jnz .read_sectors

    pop ecx                     
    
    mov eax, ecx
    shr eax, 7                  
    add eax, [fat32_fat_start_lba]
    
    push ecx
    mov edi, fat_buffer
    call ata_read_sector
    pop ecx
    
    mov eax, ecx
    and eax, 127                
    shl eax, 2                  
    mov ecx, [fat_buffer + eax] 
    
    and ecx, 0x0FFFFFFF         
    
    cmp ecx, 0x0FFFFFF8         
    jae .execute_it
    cmp ecx, 0                  
    je .execute_it
    jmp .load_cluster           

.execute_it:
    pop ebx                     
    push ebx                    
    
    mov esi, msg_executing
    mov ah, 0x0A
    call print_string
    
    pop ebx                     
    jmp load_elf                

.empty_file:
    mov esi, msg_file_miss
    mov ah, 0x0C
    call print_string
    ret

.no_arg:
    mov esi, msg_run_err
    mov ah, 0x0C
    call print_string
    ret

format_fat_name:
    push ecx
    mov ecx, 11
    mov al, ' '
    push edi
    rep stosb           
    pop edi
    pop ecx
    mov ecx, 8          
.name_loop:
    mov al, [esi]
    cmp al, '.'
    je .do_ext
    cmp al, 0
    je .done
    cmp al, ' '
    je .done
    cmp al, 'a'
    jl .skip_up
    cmp al, 'z'
    jg .skip_up
    sub al, 32
.skip_up:
    mov [edi], al
    inc esi
    inc edi
    dec ecx
    jnz .name_loop
.find_dot:
    mov al, [esi]
    cmp al, '.'
    je .do_ext
    cmp al, 0
    je .done
    cmp al, ' '
    je .done
    inc esi
    jmp .find_dot
.do_ext:
    inc esi
    mov edi, fat_target_name + 8
    mov ecx, 3
.ext_loop:
    mov al, [esi]
    cmp al, 0
    je .done
    cmp al, ' '
    je .done
    cmp al, 'a'
    jl .skip_up2
    cmp al, 'z'
    jg .skip_up2
    sub al, 32
.skip_up2:
    mov [edi], al
    inc esi
    inc edi
    dec ecx
    jnz .ext_loop
.done:
    ret


; =====================================================================
; BASIC OS BINARIES
; =====================================================================
bin_ls:
    mov ebx, [current_dir_ptr]
    mov esi, vfs_table
.loop:
    cmp byte [esi], 0
    je .done
    mov eax, [esi + 16]
    cmp eax, ebx
    jne .skip
    push esi
    mov al, [esi + 20]
    cmp al, 1
    je .dir
    mov ah, 0x0F
    jmp .print
.dir:
    mov ah, 0x09
.print:
    call print_string
    mov al, ' '
    call print_char
    pop esi
.skip:
    add esi, 32
    jmp .loop
.done:
    mov esi, msg_newline
    call print_string
    ret

bin_free:
    mov esi, msg_mem_info
    mov ah, 0x0E
    call print_string
    mov eax, [mem_total_used]
    mov edi, itoa_buffer
    call itoa
    mov esi, itoa_buffer
    mov ah, 0x0F
    call print_string
    mov esi, msg_bytes
    mov ah, 0x0E
    call print_string
    ret

bin_uptime:
    mov eax, [timer_ticks]
    mov edi, itoa_buffer
    call itoa
    mov esi, msg_uptime_pre
    mov ah, 0x0B
    call print_string
    mov esi, itoa_buffer
    mov ah, 0x0F
    call print_string
    mov esi, msg_newline
    call print_string
    ret

bin_lookie:
    ret

execute_ring3:
    cli
    mov byte [in_user_space], 1 
    mov dword [user_heap_end], 0xA000000 
    
    mov bx, 0x23            
    mov ds, bx
    mov es, bx
    mov fs, bx
    mov gs, bx
    push 0x23               
    push user_stack_top     
    push 0x202              
    push 0x1B               
    push eax                
    iretd                   

; =====================================================================
; ELF32 PARSER!
; =====================================================================
load_elf:
    mov eax, [ebx]
    cmp eax, 0x464C457F     
    jne .not_elf
    
    mov esi, msg_elf_found
    mov ah, 0x0A
    call print_string

    mov edi, [ebx + 24]     
    mov [current_app_entry], edi

    movzx ecx, word [ebx + 44] 
    mov esi, [ebx + 28]     
    add esi, ebx            

.ph_loop:
    cmp dword [esi], 1      
    jne .next_ph

    push ecx
    push esi
    mov edi, [esi + 8]      
    mov ecx, [esi + 16]     
    mov eax, [esi + 4]      
    add eax, ebx            
    
    push esi
    mov esi, eax
    rep movsb
    pop esi

    mov ecx, [esi + 20]     
    sub ecx, [esi + 16]     
    jz .no_bss
    xor al, al
    rep stosb               
.no_bss:
    pop esi
    pop ecx

.next_ph:
    movzx eax, word [ebx + 42] 
    add esi, eax            
    dec ecx
    jnz .ph_loop

    mov eax, [current_app_entry]
    jmp execute_ring3       

.not_elf:
    mov eax, ebx
    jmp execute_ring3

bin_test_syscall:
    mov eax, 4                  
    mov ebx, 1                  
    mov ecx, msg_sys_prompt   
    mov edx, 23                 
    int 0x80                    
    
    mov eax, 3                  
    mov ebx, 0                  
    mov ecx, user_input_buf   
    mov edx, 32                 
    int 0x80                    
    
    push eax                    

    mov eax, 4                  
    mov ebx, 1                  
    mov ecx, msg_sys_reply   
    mov edx, 14                 
    int 0x80                    

    mov eax, 4                  
    mov ebx, 1                  
    mov ecx, user_input_buf   
    pop edx                     
    int 0x80                    
    
    mov eax, 1                  
    mov ebx, 0                  
    int 0x80                    
    hlt

sys_do_cd:
    cmp byte [kb_buffer + 2], 0  
    je .done
    mov edi, kb_buffer + 3
    cmp byte [edi], '.'
    jne .search
    cmp byte [edi+1], '.'
    jne .search
    cmp byte [edi+2], 0
    jne .search
    jmp sys_do_cd_up
.search:
    mov esi, vfs_table
.loop:
    cmp byte [esi], 0
    je .no_dir
    push esi
    call strcmp
    pop esi
    je .found
    add esi, 32
    jmp .loop
.found:
    cmp byte [esi+20], 1   
    jne .not_dir
    mov [current_dir_ptr], esi
    ret
.no_dir:
    mov esi, msg_no_dir
    mov ah, 0x0C
    call print_string
    ret
.not_dir:
    mov esi, msg_not_dir
    mov ah, 0x0C
    call print_string
.done:
    ret

sys_do_cd_up:
    mov ebx, [current_dir_ptr]
    mov eax, [ebx + 16]
    test eax, eax
    jz .done_up
    mov [current_dir_ptr], eax
.done_up:
    ret

sys_do_cat:
    cmp byte [kb_buffer + 3], 0  
    je .cat_no_file
    mov edi, kb_buffer + 4      
    mov ebx, [current_dir_ptr]
    mov esi, vfs_table
.cat_loop:
    cmp byte [esi], 0
    je .cat_no_file
    mov eax, [esi + 16]         
    cmp eax, ebx
    jne .cat_next
    push esi
    call strcmp                 
    pop esi
    je .cat_found
.cat_next:
    add esi, 32
    jmp .cat_loop
.cat_found:
    cmp byte [esi+20], 1        
    je .cat_is_dir
    mov esi, [esi+28]           
    mov ah, 0x0F                
    call print_string
    mov esi, msg_newline
    call print_string
    ret
.cat_no_file:
    mov esi, msg_no_file
    mov ah, 0x0C
    call print_string
    ret
.cat_is_dir:
    mov esi, msg_is_dir
    mov ah, 0x0C
    call print_string
    ret

sys_do_clear:
    call clear_screen
    ret

sys_do_help:
    mov esi, msg_help_text
    mov ah, 0x0E
    call print_string
    ret

; =====================================================================
; HARDWARE DRIVERS & UTILS
; =====================================================================
init_vesa_terminal:
    mov dword [cursor_x], 0
    mov dword [cursor_y], 0
    call clear_screen
    ret
    
clear_screen:
    pushad
    call hide_mouse             ; SAFELY HIDE MOUSE
    mov edi, [vbe_framebuffer]
    mov eax, [vbe_height]
    imul eax, [vbe_pitch]
    mov ecx, eax
    shr ecx, 2          
    mov eax, 0x000000   
    rep stosd
    mov dword [cursor_x], 0
    mov dword [cursor_y], 0
    call draw_mouse             ; REDRAW MOUSE
    popad
    ret
    
put_pixel:
    pushad
    imul ebx, [vbe_pitch]
    mov edx, eax
    shl edx, 2          
    add ebx, edx
    add ebx, [vbe_framebuffer]
    mov [ebx], ecx
    popad
    ret
    
print_string:
.loop:
    lodsb
    test al, al
    jz .done
    call print_char
    jmp .loop
.done:
    ret
    
print_n_chars:
.loop:
    test ecx, ecx
    jz .done
    lodsb
    call print_char
    dec ecx
    jmp .loop
.done:
    ret

print_char:
    pushad
    call hide_mouse             ; SAFELY HIDE MOUSE
    cmp al, 0x0A
    je .newline
    cmp al, 0x08
    je .backspace
    
    movzx ebx, al
    shl ebx, 3
    add ebx, font_8x8
    
    mov edi, eax
    shr edi, 8
    and edi, 0x0F
    shl edi, 2
    add edi, vga_colors
    mov edi, [edi]
    
    mov edx, 0          
.draw_y:
    mov cl, [ebx + edx] 
    mov esi, 0          
.draw_x:
    mov eax, 128
    push ecx
    mov ecx, esi        
    shr eax, cl
    pop ecx
    test cl, al
    jz .skip_pixel
    
    mov eax, [cursor_x]
    shl eax, 3
    add eax, esi
    push ebx
    mov ebx, [cursor_y]
    shl ebx, 3
    add ebx, edx
    push ecx
    mov ecx, edi
    call put_pixel
    pop ecx
    pop ebx
.skip_pixel:
    inc esi
    cmp esi, 8
    jl .draw_x
    inc edx
    cmp edx, 8
    jl .draw_y
    
    inc dword [cursor_x]
    mov eax, [vbe_width]
    shr eax, 3          
    cmp [cursor_x], eax
    jl .done
.newline:
    mov dword [cursor_x], 0
    inc dword [cursor_y]
    mov eax, [vbe_height]
    shr eax, 3          
    cmp [cursor_y], eax
    jl .done
    call scroll_screen
    jmp .done
.backspace:
    cmp dword [cursor_x], 0
    je .done
    dec dword [cursor_x]
    mov edx, 0
.bs_y:
    mov esi, 0
.bs_x:
    mov eax, [cursor_x]
    shl eax, 3
    add eax, esi
    push ebx
    mov ebx, [cursor_y]
    shl ebx, 3
    add ebx, edx
    push ecx
    mov ecx, 0x000000
    call put_pixel
    pop ecx
    pop ebx
    inc esi
    cmp esi, 8
    jl .bs_x
    inc edx
    cmp edx, 8
    jl .bs_y
.done:
    call draw_mouse             ; REDRAW MOUSE
    popad
    ret

scroll_screen:
    pushad
    call hide_mouse             ; SAFELY HIDE MOUSE
    mov edi, [vbe_framebuffer]
    mov esi, [vbe_framebuffer]
    mov eax, [vbe_pitch]
    shl eax, 3          
    add esi, eax
    
    mov ecx, [vbe_height]
    sub ecx, 8          
    imul ecx, [vbe_pitch]
    shr ecx, 2          
    rep movsd
    
    mov ecx, [vbe_pitch]
    shl ecx, 3          
    shr ecx, 2          
    mov eax, 0x000000
    rep stosd
    
    dec dword [cursor_y]
    call draw_mouse             ; REDRAW MOUSE
    popad
    ret
    
ata_read_sector:
    pushad
    mov ebx, eax
    shl ebx, 9              
    add ebx, [ramdisk_start]
    mov esi, ebx
    mov ecx, 128            
    rep movsd
    popad
    ret

ata_write_sector:
    pushad
    mov ebx, eax
    shl ebx, 9
    add ebx, [ramdisk_start]
    mov edi, ebx
    mov ecx, 128
    rep movsd
    popad
    ret

; =====================================================================
; NEW: PS/2 MOUSE DRIVER + HARDWARE RENDERING
; =====================================================================
init_mouse:
    pushad
    
    mov eax, [vbe_width]
    shr eax, 1
    mov [mouse_x], eax
    mov eax, [vbe_height]
    shr eax, 1
    mov [mouse_y], eax
    
    call mouse_wait_write
    mov al, 0xA8        
    out 0x64, al

    call mouse_wait_write
    mov al, 0x20        
    out 0x64, al
    
    call mouse_wait_read
    in al, 0x60
    or al, 2            
    push eax

    call mouse_wait_write
    mov al, 0x60        
    out 0x64, al
    call mouse_wait_write
    pop eax
    out 0x60, al

    call mouse_write
    mov al, 0xF6
    out 0x60, al
    call mouse_read     

    call mouse_write
    mov al, 0xF4
    out 0x60, al
    call mouse_read     

    call draw_mouse     
    popad
    ret

mouse_wait_write:
    in al, 0x64
    test al, 2
    jnz mouse_wait_write
    ret

mouse_wait_read:
    in al, 0x64
    test al, 1
    jz mouse_wait_read
    ret

mouse_write:
    call mouse_wait_write
    mov al, 0xD4
    out 0x64, al
    call mouse_wait_write
    ret

mouse_read:
    call mouse_wait_read
    in al, 0x60
    ret

hide_mouse:
    pushad
    cmp byte [mouse_is_drawn], 0
    je .hm_done
    mov ebx, 0 
.hm_y:
    mov ecx, 0 
.hm_x:
    mov eax, [mouse_saved_x]
    add eax, ecx
    cmp eax, [vbe_width]
    jge .hm_skip
    mov edi, [mouse_saved_y]
    add edi, ebx
    cmp edi, [vbe_height]
    jge .hm_skip
    mov esi, ebx
    imul esi, 5
    add esi, ecx
    mov edx, [mouse_saved_pixels + esi*4]
    imul edi, [vbe_pitch]
    shl eax, 2
    add edi, eax
    add edi, [vbe_framebuffer]
    mov [edi], edx
.hm_skip:
    inc ecx
    cmp ecx, 5
    jl .hm_x
    inc ebx
    cmp ebx, 5
    jl .hm_y
    mov byte [mouse_is_drawn], 0
.hm_done:
    popad
    ret

draw_mouse:
    pushad
    cmp byte [mouse_is_drawn], 1
    je .dm_done
    mov eax, [mouse_x]
    mov [mouse_saved_x], eax
    mov eax, [mouse_y]
    mov [mouse_saved_y], eax
    mov ebx, 0 
.dm_y:
    mov ecx, 0 
.dm_x:
    mov eax, [mouse_saved_x]
    add eax, ecx
    cmp eax, [vbe_width]
    jge .dm_skip
    mov edi, [mouse_saved_y]
    add edi, ebx
    cmp edi, [vbe_height]
    jge .dm_skip
    push edi
    imul edi, [vbe_pitch]
    shl eax, 2
    add edi, eax
    add edi, [vbe_framebuffer]
    mov edx, [edi]
    mov esi, ebx
    imul esi, 5
    add esi, ecx
    mov [mouse_saved_pixels + esi*4], edx
    mov dword [edi], 0x00FF00
    pop edi
.dm_skip:
    inc ecx
    cmp ecx, 5
    jl .dm_x
    inc ebx
    cmp ebx, 5
    jl .dm_y
    mov byte [mouse_is_drawn], 1
.dm_done:
    popad
    ret

isr_mouse:
    pushad
    push ds
    push es
    
    mov ax, 0x10
    mov ds, ax
    mov es, ax

    in al, 0x60             
    mov bl, al          

    movzx eax, byte [mouse_cycle]
    cmp eax, 0
    je .cycle_0
    cmp eax, 1
    je .cycle_1
    cmp eax, 2
    je .cycle_2
    jmp .done

.cycle_0:
    test bl, 0x08           
    jz .done
    mov [mouse_packet], bl
    inc byte [mouse_cycle]
    jmp .done

.cycle_1:
    mov [mouse_packet + 1], bl
    inc byte [mouse_cycle]
    jmp .done

.cycle_2:
    mov [mouse_packet + 2], bl
    mov byte [mouse_cycle], 0
    
    mov al, [mouse_packet]
    and eax, 7
    mov [mouse_buttons], eax

    mov al, [mouse_packet + 1]
    movsx eax, al           
    mov bl, [mouse_packet]
    test bl, 0x10           
    jz .x_pos
    or eax, 0xFFFFFF00      
.x_pos:
    add [mouse_x], eax

    mov al, [mouse_packet + 2]
    movsx eax, al
    mov bl, [mouse_packet]
    test bl, 0x20           
    jz .y_pos
    or eax, 0xFFFFFF00
.y_pos:
    sub [mouse_y], eax      

    cmp dword [mouse_x], 0
    jge .check_x_max
    mov dword [mouse_x], 0
.check_x_max:
    mov eax, [vbe_width]
    dec eax
    cmp [mouse_x], eax
    jle .clamp_y
    mov [mouse_x], eax

.clamp_y:
    cmp dword [mouse_y], 0
    jge .check_y_max
    mov dword [mouse_y], 0
.check_y_max:
    mov eax, [vbe_height]
    dec eax
    cmp [mouse_y], eax
    jle .update_cursor
    mov [mouse_y], eax

.update_cursor:
    call hide_mouse
    call draw_mouse

.done:
    mov al, 0x20
    out 0xA0, al
    out 0x20, al

    pop es
    pop ds
    popad
    iretd

; =====================================================================
; GDT / IDT / PIC
; =====================================================================
init_gdt:
    mov eax, tss_entry
    mov word [gdt_tss], 103      
    mov word [gdt_tss+2], ax     
    shr eax, 16
    mov byte [gdt_tss+4], al     
    mov byte [gdt_tss+5], 0x89   
    mov byte [gdt_tss+6], 0      
    mov byte [gdt_tss+7], ah     
    mov dword [tss_entry + 4], stack_top 
    mov dword [tss_entry + 8], 0x10      
    lgdt [gdt_descriptor]
    jmp 0x08:.reload
.reload:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov ax, 0x28                 
    ltr ax
    ret

init_idt:
    pushad
    mov eax, isr_dummy
    mov ebx, 0
.fill_loop:
    call set_idt_gate
    inc ebx
    cmp ebx, 256
    jl .fill_loop
    
    mov eax, isr_page_fault
    mov ebx, 14
    call set_idt_gate
    
    popad
    lidt [idt_descriptor]
    ret
    
set_idt_gate:
    pushad                   
    mov ecx, idt_start
    mov edx, ebx             
    shl edx, 3               
    add ecx, edx             
    mov word [ecx], ax       
    mov word [ecx+2], 0x08   
    cmp ebx, 128             
    je .user_gate
    mov word [ecx+4], 0x8E00 
    jmp .finish
.user_gate:
    mov word [ecx+4], 0xEE00 
.finish:
    shr eax, 16
    mov word [ecx+6], ax     
    popad                    
    ret
    
init_pic:
    mov al, 0x11
    out 0x20, al
    out 0xA0, al
    mov al, 0x20
    out 0x21, al
    mov al, 0x28
    out 0xA1, al
    mov al, 0x04
    out 0x21, al
    mov al, 0x02
    out 0xA1, al
    mov al, 0x01
    out 0x21, al
    out 0xA1, al
    
    mov al, 0xF8            
    out 0x21, al
    mov al, 0xEF            
    out 0xA1, al

    ; --- Reprogram PIT (Timer) to 1000Hz (1ms per tick) ---
    mov al, 0x36
    out 0x43, al
    mov ax, 1193      
    out 0x40, al      
    mov al, ah
    out 0x40, al      
    ret

isr_dummy:
    iretd

isr_page_fault:
    cli
    add esp, 4              
    mov esi, msg_pf
    mov ah, 0x0C            
    call print_string
    hlt
    jmp $

isr_keyboard:
    pushad
    in al, 0x60
    
    movzx ebx, al
    and ebx, 0x7F           
    test al, 0x80           
    jnz .set_key_up
    mov byte [key_state_map + ebx], 1
    jmp .check_shift
.set_key_up:
    mov byte [key_state_map + ebx], 0
.check_shift:
    
    cmp al, 0x2A        
    je .shift_down
    cmp al, 0x36        
    je .shift_down
    cmp al, 0xAA        
    je .shift_up
    cmp al, 0xB6        
    je .shift_up
    
    test al, 0x80
    jnz .done
    
    movzx ebx, al
    cmp byte [shift_pressed], 1
    je .use_shift
    mov al, [scancode_map + ebx]
    jmp .got_char
    
.use_shift:
    mov al, [scancode_map_shift + ebx]
    
.got_char:
    test al, al
    jz .done
    
    cmp byte [in_user_space], 1
    je .route_ring_buffer
    
.route_terminal:
    cmp al, 0x0A
    je .enter
    cmp al, 0x08
    je .back
    mov ah, 0x0F
    call print_char
    mov ebx, [kb_buffer_pos]
    cmp ebx, 255
    jge .done
    mov [kb_buffer + ebx], al
    inc dword [kb_buffer_pos]
    jmp .done

.back:
    mov ebx, [kb_buffer_pos]
    test ebx, ebx
    jz .done
    dec dword [kb_buffer_pos]
    mov ah, 0x0F
    mov al, 0x08
    call print_char
    jmp .done

.enter:
    mov ebx, [kb_buffer_pos]
    mov byte [kb_buffer + ebx], 0
    mov ah, 0x0F
    mov al, 0x0A
    call print_char
    mov byte [command_ready], 1
    jmp .done

.route_ring_buffer:
    mov ebx, [kb_ring_tail]
    mov [kb_ring_buf + ebx], al
    inc ebx
    and ebx, 255                 
    mov [kb_ring_tail], ebx
    jmp .done

.shift_down:
    mov byte [shift_pressed], 1
    jmp .done
.shift_up:
    mov byte [shift_pressed], 0
    
.done:
    mov al, 0x20
    out 0x20, al
    popad
    iretd

isr_syscall:
    pushad                  
    push ds                 
    push es                 
    
    push eax
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    pop eax
    
    cmp eax, 1
    je .sys_exit
    cmp eax, 3
    je .sys_read
    cmp eax, 4
    je .sys_write
    cmp eax, 5          
    je .sys_open
    cmp eax, 6          
    je .sys_close
    
    cmp eax, 45         
    je .sys_brk
    
    cmp eax, 90
    je .sys_malloc
    cmp eax, 91
    je .sys_free
    
    cmp eax, 100        
    je .sys_create_window
    cmp eax, 101        
    je .sys_update_window
    
    cmp eax, 102
    je .sys_set_window_pos
    cmp eax, 103
    je .sys_get_mouse
    cmp eax, 104
    je .sys_clear_background
    cmp eax, 105
    je .sys_resize_window
    cmp eax, 106             
    je .sys_yield
    cmp eax, 107             
    je .sys_draw_rect_xor
    cmp eax, 108             
    je .sys_get_key_state
    cmp eax, 109             
    je .sys_get_ticks
    cmp eax, 110             
    je .sys_sleep
    cmp eax, 111             
    je .sys_fat32_load
    
    jmp .sys_done           

; --- Floating Window Manager Syscalls ---
.sys_create_window:
    cmp byte [win_active], 1
    jne .do_window_alloc
    
    ; --- FIX: ZOMBIE WINDOW CLEANUP ---
    mov eax, [win_bg_buffer]
    call k_free
    mov eax, [win_buffer]
    call k_free
    
.do_window_alloc:
    ; Allocate the front buffer
    mov eax, ebx
    imul eax, ecx
    shl eax, 2
    push ebx
    push ecx
    call k_malloc
    mov [win_buffer], eax
    pop ecx
    pop ebx
    
    ; Allocate the background save buffer
    mov eax, ebx
    imul eax, ecx
    shl eax, 2
    push ebx
    push ecx
    call k_malloc
    mov [win_bg_buffer], eax
    pop ecx
    pop ebx
    
    mov [win_width], ebx
    mov [win_height], ecx
    mov byte [win_active], 1
    mov byte [win_bg_saved], 0
    
    mov eax, [win_buffer]
    mov [esp + 36], eax 
    
    jmp .sys_done

.sys_update_window:
    cmp byte [win_active], 1
    jne .sys_done
    call hide_mouse
    
    cmp byte [win_bg_saved], 1
    jne .do_bg_update
    mov eax, [win_x]
    cmp eax, [win_bg_x]
    jne .do_bg_update
    mov eax, [win_y]
    cmp eax, [win_bg_y]
    je .draw_window         
    
.do_bg_update:
    cmp byte [win_bg_saved], 1
    jne .save_new_bg
    mov esi, [win_bg_buffer]
    mov edi, [vbe_framebuffer]
    mov eax, [win_bg_y]
    imul eax, [vbe_pitch]
    mov ebx, [win_bg_x]
    shl ebx, 2
    add eax, ebx
    add edi, eax
    mov ecx, [win_height]
.restore_bg_row:
    push ecx
    push edi
    mov ecx, [win_width]
    rep movsd
    pop edi
    add edi, [vbe_pitch]
    pop ecx
    loop .restore_bg_row

.save_new_bg:
    mov esi, [vbe_framebuffer]
    mov eax, [win_y]
    imul eax, [vbe_pitch]
    mov ebx, [win_x]
    shl ebx, 2
    add eax, ebx
    add esi, eax
    mov edi, [win_bg_buffer]
    mov ecx, [win_height]
.save_bg_row:
    push ecx
    push esi
    mov ecx, [win_width]
    rep movsd
    pop esi
    add esi, [vbe_pitch]
    pop ecx
    loop .save_bg_row
    
    mov eax, [win_x]
    mov [win_bg_x], eax
    mov eax, [win_y]
    mov [win_bg_y], eax
    mov byte [win_bg_saved], 1

.draw_window:
    mov esi, [win_buffer]
    mov edi, [vbe_framebuffer]
    mov eax, [win_y]
    imul eax, [vbe_pitch]
    mov ebx, [win_x]
    shl ebx, 2
    add eax, ebx
    add edi, eax            
    mov ecx, [win_height]
.blit_row_loop:
    push ecx
    push edi
    mov ecx, [win_width]
    rep movsd               
    pop edi
    add edi, [vbe_pitch]    
    pop ecx
    loop .blit_row_loop

    call draw_mouse
    jmp .sys_done

.sys_set_window_pos:
    cmp ebx, 0
    jge .check_x_max
    mov ebx, 0
.check_x_max:
    mov eax, [vbe_width]
    sub eax, [win_width]
    cmp ebx, eax
    jle .set_y
    mov ebx, eax
.set_y:
    cmp ecx, 0
    jge .check_y_max
    mov ecx, 0
.check_y_max:
    mov eax, [vbe_height]
    sub eax, [win_height]
    cmp ecx, eax
    jle .do_set
    mov ecx, eax
.do_set:
    mov [win_x], ebx
    mov [win_y], ecx
    jmp .sys_done

.sys_get_mouse:
    mov eax, [mouse_x]
    mov [esp + 36], eax      
    mov ebx, [mouse_y]
    mov [esp + 24], ebx      
    mov ecx, [mouse_buttons]
    mov [esp + 32], ecx      
    jmp .sys_done

.sys_clear_background:
    call clear_screen
    jmp .sys_done

.sys_resize_window:
    cmp byte [win_active], 1
    jne .sys_done
    
    ; --- Erase the old window ghost before allocating the new one ---
    cmp byte [win_bg_saved], 1
    jne .skip_ghost_erase
    pushad
    call hide_mouse
    mov esi, [win_bg_buffer]
    mov edi, [vbe_framebuffer]
    mov eax, [win_y]
    imul eax, [vbe_pitch]
    mov ebx, [win_x]
    shl ebx, 2
    add eax, ebx
    add edi, eax
    mov ecx, [win_height]
.erase_ghost_row:
    push ecx
    push edi
    mov ecx, [win_width]
    rep movsd
    pop edi
    add edi, [vbe_pitch]
    pop ecx
    loop .erase_ghost_row
    call draw_mouse
    popad
.skip_ghost_erase:

    mov eax, [win_bg_buffer]
    call k_free
    mov eax, [win_buffer]    
    call k_free

    ; --- Zero-Size Destruction Check ---
    cmp ebx, 0
    je .destroy_window
    cmp ecx, 0
    je .destroy_window

    ; --- FIX: RE-ALLOCATE FRONT BUFFER ---
    mov eax, ebx
    imul eax, ecx
    shl eax, 2
    push ebx
    push ecx
    call k_malloc
    mov [win_buffer], eax
    pop ecx
    pop ebx

    ; --- RE-ALLOCATE BACKGROUND BUFFER ---
    mov eax, ebx
    imul eax, ecx
    shl eax, 2
    push ebx
    push ecx
    call k_malloc            
    mov [win_bg_buffer], eax
    pop ecx
    pop ebx

    mov [win_width], ebx
    mov [win_height], ecx
    mov byte [win_bg_saved], 0

    mov eax, [win_buffer]    
    mov [esp + 36], eax      

    jmp .sys_done

.destroy_window:
    mov byte [win_active], 0
    jmp .sys_done

.sys_yield:
    mov ebx, [timer_ticks]
.yield_loop:
    sti
    hlt
    cli
    mov ecx, [timer_ticks]
    cmp ecx, ebx
    je .yield_loop
    jmp .sys_done

.sys_get_key_state:
    movzx eax, byte [key_state_map + ebx]
    mov [esp + 36], eax      
    jmp .sys_done

.sys_get_ticks:
    mov eax, [timer_ticks]   
    mov [esp + 36], eax
    jmp .sys_done

.sys_sleep:
    mov eax, [timer_ticks]
    add eax, ebx             
.sleep_loop2:
    sti
    hlt                      
    cli
    mov ecx, [timer_ticks]
    cmp ecx, eax             
    jl .sleep_loop2          
    jmp .sys_done

.sys_fat32_load:
    mov esi, ebx
    mov edi, fat_target_name
    call format_fat_name

    mov eax, [fat32_root_cluster]
    call lba_from_cluster
    mov edi, sector_buffer
    call ata_read_sector

    mov esi, sector_buffer
    mov ecx, 16
.s32_search:
    cmp byte [esi], 0
    je .s32_fail
    cmp byte [esi], 0xE5
    je .s32_next
    mov al, [esi + 11]
    cmp al, 0x0F
    je .s32_next
    test al, 0x10
    jnz .s32_next

    push esi
    mov edi, fat_target_name
    push ecx
    mov ecx, 11
    repe cmpsb
    pop ecx
    pop esi
    je .s32_found
.s32_next:
    add esi, 32
    dec ecx
    jnz .s32_search
.s32_fail:
    mov dword [esp + 36], 0  
    mov dword [esp + 32], 0  
    jmp .sys_done

.s32_found:
    movzx eax, word [esi + 20]
    shl eax, 16
    mov ax, word [esi + 26]
    mov ecx, eax            

    mov eax, [esi + 28]     
    mov [esp + 32], eax     
    test eax, eax
    jz .s32_fail

    ; --- CRITICAL FIX: FAT32 HEAP PADDING ---
    add eax, 65536          
    push ecx
    call k_malloc
    pop ecx
    mov ebx, eax            
    mov [esp + 36], eax     

.s32_ld_clust:
    mov eax, ecx
    push ecx
    call lba_from_cluster
    movzx edx, byte [fat32_sectors_per_clust]
.s32_ld_sec:
    push eax
    push edx

    mov edi, sector_buffer
    call ata_read_sector

    mov esi, sector_buffer
    mov edi, ebx
    push ecx
    mov ecx, 128
    rep movsd
    mov ebx, edi
    pop ecx

    pop edx
    pop eax
    inc eax
    dec edx
    jnz .s32_ld_sec
    pop ecx

    mov eax, ecx
    shr eax, 7
    add eax, [fat32_fat_start_lba]

    push ecx
    mov edi, fat_buffer
    call ata_read_sector
    pop ecx

    mov eax, ecx
    and eax, 127
    shl eax, 2
    mov ecx, [fat_buffer + eax]

    and ecx, 0x0FFFFFFF         

    cmp ecx, 0x0FFFFFF8
    jae .sys_done
    cmp ecx, 0
    je .sys_done
    jmp .s32_ld_clust

.sys_draw_rect_xor:
    call hide_mouse
    mov edi, edx
    shr edi, 16      ; w
    mov esi, edx
    and esi, 0xFFFF  ; h

    pushad
    mov eax, ebx
    mov ebx, ecx
    mov ecx, edi
    call .xor_hline
    popad

    pushad
    mov eax, ebx
    mov ebx, ecx
    add ebx, esi
    dec ebx
    mov ecx, edi
    call .xor_hline
    popad

    pushad
    mov eax, ebx
    mov ebx, ecx
    mov ecx, esi
    call .xor_vline
    popad

    pushad
    mov eax, ebx
    add eax, edi
    dec eax
    mov ebx, ecx
    mov ecx, esi
    call .xor_vline
    popad

    call draw_mouse
    jmp .sys_done

.xor_hline:
    cmp ebx, 0
    jl .xh_done
    cmp ebx, [vbe_height]
    jge .xh_done
    cmp eax, 0
    jge .xh_check_right
    add ecx, eax
    mov eax, 0
.xh_check_right:
    cmp ecx, 0
    jle .xh_done
    mov edx, eax
    add edx, ecx
    cmp edx, [vbe_width]
    jle .xh_draw
    mov ecx, [vbe_width]
    sub ecx, eax
.xh_draw:
    push edi
    imul ebx, [vbe_pitch]
    shl eax, 2
    add ebx, eax
    add ebx, [vbe_framebuffer]
    mov edi, ebx
.xh_loop:
    xor dword [edi], 0xFFFFFF  
    add edi, 4
    dec ecx
    jnz .xh_loop
    pop edi
.xh_done:
    ret

.xor_vline:
    cmp eax, 0
    jl .xv_done
    cmp eax, [vbe_width]
    jge .xv_done
    cmp ebx, 0
    jge .xv_check_bottom
    add ecx, ebx
    mov ebx, 0
.xv_check_bottom:
    cmp ecx, 0
    jle .xv_done
    mov edx, ebx
    add edx, ecx
    cmp edx, [vbe_height]
    jle .xv_draw
    mov ecx, [vbe_height]
    sub ecx, ebx
.xv_draw:
    push edi
    imul ebx, [vbe_pitch]
    shl eax, 2
    add ebx, eax
    add ebx, [vbe_framebuffer]
    mov edi, ebx
    mov edx, [vbe_pitch]
.xv_loop:
    xor dword [edi], 0xFFFFFF  
    add edi, edx
    dec ecx
    jnz .xv_loop
    pop edi
.xv_done:
    ret

; --- File Descriptor Syscalls ---
.sys_open:
    mov edi, ebx
    call find_in_vfs_sys    
    test eax, eax
    jz .open_fail
    mov ebx, 3
.find_fd:
    cmp ebx, 256
    jge .open_fail
    mov ecx, ebx
    shl ecx, 4              
    add ecx, fd_table_ext
    cmp dword [ecx], 0      
    je .found_fd
    inc ebx
    jmp .find_fd
.found_fd:
    mov dword [ecx], 1       
    mov dword [ecx + 4], eax 
    mov dword [ecx + 8], 0   
    mov [esp + 36], ebx      
    jmp .sys_done
.open_fail:
    mov dword [esp + 36], -1 
    jmp .sys_done

.sys_close:
    cmp ebx, 3
    jl .sys_done            
    cmp ebx, 256
    jge .sys_done
    shl ebx, 4
    add ebx, fd_table_ext
    mov dword [ebx], 0      
    jmp .sys_done

; --- I/O Syscalls ---
.sys_write:
    cmp ebx, 1          
    jne .sys_done       
    mov esi, ecx        
    mov ecx, edx        
.write_loop:
    test ecx, ecx
    jz .sys_done
    lodsb
    mov ah, 0x0F        
    call print_char     
    dec ecx
    jmp .write_loop

.sys_read:
    cmp ebx, 0          
    je .read_stdin      
    cmp ebx, 3
    jl .sys_done        
    cmp ebx, 256
    jge .sys_done
    
    mov eax, ebx
    shl eax, 4
    add eax, fd_table_ext
    cmp dword [eax], 1  
    jne .sys_done
    
    mov esi, [eax + 4]  
    add esi, [eax + 8]  
    mov edi, ecx        
    
    xor ecx, ecx        
.vfs_read_loop:
    cmp ecx, edx
    jge .vfs_read_done
    push ebx
    mov bl, [esi]
    test bl, bl         
    jz .vfs_read_early
    mov [edi], bl
    pop ebx
    inc esi
    inc edi
    inc ecx
    jmp .vfs_read_loop
.vfs_read_early:
    pop ebx
.vfs_read_done:
    add [eax + 8], ecx  
    mov [esp + 36], ecx 
    jmp .sys_done

.read_stdin:
    sti                 
    mov edi, ecx        
    xor esi, esi        
.wait_key:
    mov eax, [kb_ring_head]
    cmp eax, [kb_ring_tail]
    je .halt_wait       
    mov al, [kb_ring_buf + eax]
    mov ebx, [kb_ring_head]
    inc ebx
    and ebx, 255
    mov [kb_ring_head], ebx
    stosb               
    inc esi             
    push eax
    mov ah, 0x0F
    call print_char
    pop eax
    cmp al, 0x0A 
    je .done_read
    cmp esi, edx 
    je .done_read
    jmp .wait_key
.halt_wait:
    hlt                 
    jmp .wait_key
.done_read:
    cli                 
    mov [esp + 36], esi 
    jmp .sys_done

; --- Memory & Control Syscalls ---

.sys_brk:
    cmp ebx, 0
    je .return_brk
    mov [user_heap_end], ebx

.return_brk:
    mov eax, [user_heap_end]
    mov [esp + 36], eax      
    jmp .sys_done

.sys_malloc:
    mov eax, ebx            
    call k_malloc
    mov [esp + 36], eax     
    jmp .sys_done

.sys_free:
    mov eax, ebx            
    call k_free
    jmp .sys_done

.sys_exit:
    mov byte [in_user_space], 0 

    cmp byte [win_active], 1
    jne .skip_win_cleanup
    call hide_mouse
    cmp byte [win_bg_saved], 1
    jne .no_bg_restore
    mov esi, [win_bg_buffer]
    mov edi, [vbe_framebuffer]
    mov eax, [win_bg_y]
    imul eax, [vbe_pitch]
    mov ebx, [win_bg_x]
    shl ebx, 2
    add eax, ebx
    add edi, eax
    mov ecx, [win_height]
.exit_bg_row:
    push ecx
    push edi
    mov ecx, [win_width]
    rep movsd
    pop edi
    add edi, [vbe_pitch]
    pop ecx
    loop .exit_bg_row
.no_bg_restore:
    mov eax, [win_buffer]
    call k_free                 
    mov eax, [win_bg_buffer]
    call k_free
    mov byte [win_active], 0
    call draw_mouse
.skip_win_cleanup:

    mov eax, [current_app_ptr]
    test eax, eax               
    jz .skip_app_free
    call k_free                 
    mov dword [current_app_ptr], 0 
.skip_app_free:
    mov ax, 0x10
    mov ds, ax          
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov esp, stack_top      
    sti
    jmp shell_main        

.sys_done:
    pop es
    pop ds
    popad                   
    iretd                   

; NEW HELPER: For sys_open to search files without using kb_buffer
find_in_vfs_sys:
    mov esi, vfs_table
.vfs_loop:
    cmp byte [esi], 0
    je .vfs_fail
    push esi
    push edi
    call strcmp
    pop edi
    pop esi
    je .vfs_match
    add esi, 32
    jmp .vfs_loop
.vfs_match:
    mov eax, [esi + 28] 
    ret
.vfs_fail:
    xor eax, eax
    ret

strcmp:
    push esi
    push edi
    push ebx
.loop:
    mov al, [esi]
    mov bl, [edi]
    cmp al, bl
    jne .no
    test al, al
    jz .yes
    inc esi
    inc edi
    jmp .loop
.no: 
    pop ebx
    pop edi
    pop esi
    clc
    ret
.yes: 
    pop ebx
    pop edi
    pop esi
    cmp eax, eax
    ret
    
strncmp:
    push esi
    push edi
    push ecx
    push ebx
.loop:
    test ecx, ecx
    jz .yes
    mov al, [esi]
    mov bl, [edi]
    cmp al, bl
    jne .no
    inc esi
    inc edi
    dec ecx
    jmp .loop
.no: 
    pop ebx
    pop ecx
    pop edi
    pop esi
    clc
    ret
.yes: 
    pop ebx
    pop ecx
    pop edi
    pop esi
    cmp eax, eax
    ret
    
itoa:
    pusha
    mov ecx, 10
    mov ebx, edi
    add ebx, 15
    mov byte [ebx], 0
    dec ebx
.l: 
    xor edx, edx
    div ecx
    add dl, '0'
    mov [ebx], dl
    dec ebx
    test eax, eax
    jnz .l
    inc ebx
.c: 
    mov al, [ebx]
    mov [edi], al
    inc edi
    inc ebx
    test al, al
    jnz .c
    popa
    ret

; =====================================================================
; DATA SECTION (Read/Write Memory For Initialized Variables & Strings)
; =====================================================================
section .data
align 8
gdt_start: dq 0
gdt_code:  dq 0x00CF9A000000FFFF 
gdt_data:  dq 0x00CF92000000FFFF 
gdt_ucode: dq 0x00CFFA000000FFFF 
gdt_udata: dq 0x00CFF2000000FFFF 
gdt_tss:   dq 0                  
gdt_end:

gdt_descriptor: 
    dw gdt_end - gdt_start - 1
    dd gdt_start

idt_descriptor: 
    dw 2047
    dd idt_start

scancode_map:
    db 0, 0, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', 0x08, 0
    db 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', 0x0A, 0, 'a', 's'
    db 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', "'", '`', 0, '\', 'z', 'x', 'c', 'v'
    db 'b', 'n', 'm', ',', '.', '/', 0, '*', 0, ' ', 0
    times 128 db 0

scancode_map_shift:
    db 0, 0, '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '_', '+', 0x08, 0
    db 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{', '}', 0x0A, 0, 'A', 'S'
    db 'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', '"', '~', 0, '|', 'Z', 'X', 'C', 'V'
    db 'B', 'N', 'M', '<', '>', '?', 0, '*', 0, ' ', 0
    times 128 db 0

msg_welcome   db 'NoVa Monolithic Kernel v1.6 [Doom Engine Ready]', 0x0A, 'Type "help" for commands.', 0x0A, 0
msg_user      db 'root@nova:', 0
msg_prompt_sym db '# ', 0
msg_unknown   db 'sh: command not found: ', 0
msg_newline   db 0x0A, 0
msg_uptime_pre db 'Ticks: ', 0
msg_mem_info  db 'Kernel Heap Usage: ', 0
msg_bytes     db ' bytes used.', 0x0A, 0
msg_no_dir    db 'cd: no such directory', 0x0A, 0
msg_not_dir   db 'cd: not a directory', 0x0A, 0
msg_no_file   db 'cat: file not found (in VFS)', 0x0A, 0
msg_is_dir    db 'cat: is a directory', 0x0A, 0
msg_help_text db 'Commands: ls, cd, cat, free, uptime, test, clear, lookie.me', 0x0A, 'FAT32 Tools: f32format, f32mount, f32ls, f32read, f32write, f32cd, f32rm, f32mkdir', 0x0A, 'App Loader: run <filename.bin/elf>', 0x0A, 0
msg_pf        db 'CRITICAL KERNEL PANIC: Page Fault! (Memory Access Violation)', 0x0A, 0
msg_syscall_test db 'Hello from User Space via int 0x80 Syscall!', 0x0A, 0
msg_sys_prompt db 'Enter your name (FD0): ', 0
msg_sys_reply  db 'Hello there, ', 0
msg_no_mbr    db 'FAIL: No valid boot signature found on sector 0. (Run "f32format" first!)', 0x0A, 0
msg_fat_root  db 'FAT32 Directory Contents:', 0x0A, 0
msg_formatting db 'Formatting Drive with pure FAT32 Structures...', 0x0A, 0
msg_format_ok  db 'Format Complete! FAT32 Root Directory built at LBA 2032.', 0x0A, 0
msg_fatr_err   db 'Usage: f32read <filename.ext>', 0x0A, 0
msg_file_miss  db 'Error: File/Folder not found.', 0x0A, 0

cmd_cd        db 'cd ', 0
cmd_cat       db 'cat ', 0
cmd_run       db 'run ', 0
cmd_f32read   db 'f32read', 0
cmd_f32write  db 'f32write', 0
cmd_f32cd     db 'f32cd', 0
cmd_f32rm     db 'f32rm', 0
cmd_f32mkdir  db 'f32mkdir', 0
cmd_clear     db 'clear', 0
cmd_help      db 'help', 0

str_text_touch db '--text_touch: ', 0

msg_elf_found   db 'Valid ELF32 executable detected! Parsing segments...', 0x0A, 0
msg_f32_found   db 'Drive successfully mounted! FAT32 Variables initialized.', 0x0A, 0
msg_not_mounted db 'Error: Run "f32mount" first to initialize the disk variables!', 0x0A, 0
msg_disk_full   db 'Error: Disk full (or FAT sector 0 full).', 0x0A, 0
msg_dir_full    db 'Error: Directory full.', 0x0A, 0
msg_write_data  db 'SUCCESS! You have mastered the FAT32 Write Sequence!', 0x0A, 'This text is physically stored on the drive.', 0x0A, 0
msg_write_ok    db 'File successfully written/updated on disk!', 0x0A, 0
msg_fatw_err    db 'Usage: f32write <filename.ext> [--text_touch: data]', 0x0A, 0
msg_deleted     db 'Target successfully deleted. FAT chains freed.', 0x0A, 0
msg_rm_err      db 'Usage: f32rm <filename.ext>', 0x0A, 0
msg_mkdir_ok    db 'Directory created successfully!', 0x0A, 0
msg_mkdir_err   db 'Usage: f32mkdir <dirname>', 0x0A, 0
msg_executing   db 'Loading binary into memory... Jumping to User Space (Ring 3)!', 0x0A, 0
msg_run_err     db 'Usage: run <filename.bin>', 0x0A, 0
msg_not_elf     db 'Error: File is not a valid ELF32 executable!', 0x0A, 0
dot_name          db '.          '
dot_dot_name      db '..         '
msg_dir_not_found db 'Error: Directory not found.', 0x0A, 0
msg_dir_changed   db 'Directory changed.', 0x0A, 0

msg_lk_n1     db '    //   //  ', 0
msg_lk_v1     db '\ \  / /     ', 0
msg_lk_key_os db 'OS: ', 0
msg_lk_val_os db 'NoVa OS v1.5', 0
msg_lk_n2     db '   ///  //   ', 0
msg_lk_v2     db ' \ \/ /      ', 0
msg_lk_key_kr db 'Kernel: ', 0
msg_lk_val_kr db 'Monolithic Core', 0
msg_lk_n3     db '  //  ///    ', 0
msg_lk_v3     db '  \  /       ', 0
msg_lk_i3     db 'Uptime: ', 0
msg_lk_n4     db ' //   // .   ', 0
msg_lk_v4     db '   \/        ', 0
msg_lk_i4     db 'Memory: ', 0
msg_lk_n5     db '                          ', 0 
msg_lk_key_sh db 'Shell: ', 0
msg_lk_val_sh db 'Integrated sh', 0
msg_lk_ticks  db ' ticks', 0

msg_readme      db 'NoVa OS v1.6. DOOM Ready!', 0
str_not_mounted db 'FAT32 Not Mounted.', 0

align 4
vga_colors:
    dd 0x000000 ; 0 = Black
    dd 0x0000AA ; 1 = Blue
    dd 0x00AA00 ; 2 = Green
    dd 0x00AAAA ; 3 = Cyan
    dd 0xAA0000 ; 4 = Red
    dd 0xAA00AA ; 5 = Magenta
    dd 0xAA5500 ; 6 = Brown
    dd 0xAAAAAA ; 7 = Light Gray
    dd 0x555555 ; 8 = Dark Gray
    dd 0x5555FF ; 9 = Light Blue
    dd 0x55FF55 ; A = Light Green
    dd 0x55FFFF ; B = Light Cyan
    dd 0xFF5555 ; C = Light Red
    dd 0xFF55FF ; D = Light Magenta
    dd 0xFFFF55 ; E = Yellow
    dd 0xFFFFFF ; F = White

align 4
font_8x8:
    times 256 db 0 ; 0-31 control chars
    db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 ; Space
    db 0x18,0x3C,0x3C,0x18,0x18,0x00,0x18,0x00 ; !
    db 0x66,0x66,0x22,0x00,0x00,0x00,0x00,0x00 ; "
    db 0x36,0x36,0x7F,0x36,0x7F,0x36,0x36,0x00 ; #
    db 0x18,0x3E,0x60,0x3C,0x06,0x7C,0x18,0x00 ; $
    db 0x63,0x66,0x0C,0x18,0x30,0x66,0xC6,0x00 ; %
    db 0x38,0x6C,0x6C,0x38,0x6D,0x66,0x3B,0x00 ; &
    db 0x18,0x18,0x30,0x00,0x00,0x00,0x00,0x00 ; '
    db 0x0C,0x18,0x30,0x30,0x30,0x18,0x0C,0x00 ; (
    db 0x30,0x18,0x0C,0x0C,0x0C,0x18,0x30,0x00 ; )
    db 0x00,0x66,0x3C,0xFF,0x3C,0x66,0x00,0x00 ; *
    db 0x00,0x18,0x18,0x7E,0x18,0x18,0x00,0x00 ; +
    db 0x00,0x00,0x00,0x00,0x00,0x18,0x18,0x30 ; ,
    db 0x00,0x00,0x00,0x7E,0x00,0x00,0x00,0x00 ; -
    db 0x00,0x00,0x00,0x00,0x00,0x18,0x18,0x00 ; .
    db 0x06,0x0C,0x18,0x30,0x60,0xC0,0x80,0x00 ; /
    db 0x3C,0x66,0x6E,0x76,0x66,0x66,0x3C,0x00 ; 0
    db 0x18,0x38,0x18,0x18,0x18,0x18,0x7E,0x00 ; 1
    db 0x3C,0x66,0x06,0x0C,0x18,0x30,0x7E,0x00 ; 2
    db 0x3C,0x66,0x06,0x1C,0x06,0x66,0x3C,0x00 ; 3
    db 0x0C,0x1C,0x3C,0x6C,0x7E,0x0C,0x0C,0x00 ; 4
    db 0x7E,0x60,0x7C,0x06,0x06,0x66,0x3C,0x00 ; 5
    db 0x3C,0x60,0x7C,0x66,0x66,0x66,0x3C,0x00 ; 6
    db 0x7E,0x06,0x0C,0x18,0x30,0x30,0x30,0x00 ; 7
    db 0x3C,0x66,0x66,0x3C,0x66,0x66,0x3C,0x00 ; 8
    db 0x3C,0x66,0x66,0x66,0x3E,0x06,0x3C,0x00 ; 9
    db 0x00,0x18,0x18,0x00,0x00,0x18,0x18,0x00 ; :
    db 0x00,0x18,0x18,0x00,0x00,0x18,0x18,0x30 ; ;
    db 0x06,0x0C,0x18,0x30,0x18,0x0C,0x06,0x00 ; <
    db 0x00,0x00,0x7E,0x00,0x7E,0x00,0x00,0x00 ; =
    db 0x60,0x30,0x18,0x0C,0x18,0x30,0x60,0x00 ; >
    db 0x3C,0x66,0x06,0x0C,0x18,0x00,0x18,0x00 ; ?
    db 0x3C,0x66,0x6E,0x6E,0x60,0x66,0x3C,0x00 ; @
    db 0x3C,0x66,0x66,0x7E,0x66,0x66,0x66,0x00 ; A
    db 0x7C,0x66,0x66,0x7C,0x66,0x66,0x7C,0x00 ; B
    db 0x3C,0x66,0x60,0x60,0x60,0x66,0x3C,0x00 ; C
    db 0x78,0x6C,0x66,0x66,0x66,0x6C,0x78,0x00 ; D
    db 0x7E,0x60,0x60,0x7C,0x60,0x60,0x7E,0x00 ; E
    db 0x7E,0x60,0x60,0x7C,0x60,0x60,0x60,0x00 ; F
    db 0x3C,0x66,0x60,0x6E,0x66,0x66,0x3E,0x00 ; G
    db 0x66,0x66,0x66,0x7E,0x66,0x66,0x66,0x00 ; H
    db 0x3C,0x18,0x18,0x18,0x18,0x18,0x3C,0x00 ; I
    db 0x1E,0x0C,0x0C,0x0C,0x0C,0x6C,0x38,0x00 ; J
    db 0x66,0x6C,0x78,0x70,0x78,0x6C,0x66,0x00 ; K
    db 0x60,0x60,0x60,0x60,0x60,0x60,0x7E,0x00 ; L
    db 0x63,0x77,0x7F,0x6B,0x63,0x63,0x63,0x00 ; M
    db 0x66,0x76,0x7E,0x7E,0x6E,0x66,0x66,0x00 ; N
    db 0x3C,0x66,0x66,0x66,0x66,0x66,0x3C,0x00 ; O
    db 0x7C,0x66,0x66,0x7C,0x60,0x60,0x60,0x00 ; P
    db 0x3C,0x66,0x66,0x66,0x6A,0x6C,0x36,0x00 ; Q
    db 0x7C,0x66,0x66,0x7C,0x78,0x6C,0x66,0x00 ; R
    db 0x3C,0x66,0x60,0x3C,0x06,0x66,0x3C,0x00 ; S
    db 0x7E,0x18,0x18,0x18,0x18,0x18,0x18,0x00 ; T
    db 0x66,0x66,0x66,0x66,0x66,0x66,0x3C,0x00 ; U
    db 0x66,0x66,0x66,0x66,0x66,0x3C,0x18,0x00 ; V
    db 0x63,0x63,0x63,0x6B,0x7F,0x77,0x63,0x00 ; W
    db 0x66,0x66,0x3C,0x18,0x3C,0x66,0x66,0x00 ; X
    db 0x66,0x66,0x66,0x3C,0x18,0x18,0x18,0x00 ; Y
    db 0x7E,0x06,0x0C,0x18,0x30,0x60,0x7E,0x00 ; Z
    db 0x3C,0x30,0x30,0x30,0x30,0x30,0x3C,0x00 ; [
    db 0x80,0xC0,0x60,0x30,0x18,0x0C,0x06,0x00 ; backslash
    db 0x3C,0x0C,0x0C,0x0C,0x0C,0x0C,0x3C,0x00 ; ]
    db 0x18,0x3C,0x66,0x00,0x00,0x00,0x00,0x00 ; ^
    db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xFF ; _
    db 0x30,0x18,0x0C,0x00,0x00,0x00,0x00,0x00 ; `
    db 0x00,0x00,0x3C,0x06,0x3E,0x66,0x3E,0x00 ; a
    db 0x60,0x60,0x7C,0x66,0x66,0x66,0x7C,0x00 ; b
    db 0x00,0x00,0x3C,0x60,0x60,0x60,0x3C,0x00 ; c
    db 0x06,0x06,0x3E,0x66,0x66,0x66,0x3E,0x00 ; d
    db 0x00,0x00,0x3C,0x66,0x7E,0x60,0x3C,0x00 ; e
    db 0x1C,0x30,0x7C,0x30,0x30,0x30,0x30,0x00 ; f
    db 0x00,0x00,0x3E,0x66,0x66,0x3E,0x06,0x3C ; g
    db 0x60,0x60,0x7C,0x66,0x66,0x66,0x66,0x00 ; h
    db 0x18,0x00,0x38,0x18,0x18,0x18,0x3C,0x00 ; i
    db 0x06,0x00,0x06,0x06,0x06,0x06,0x06,0x3C ; j
    db 0x60,0x60,0x66,0x6C,0x78,0x6C,0x66,0x00 ; k
    db 0x38,0x18,0x18,0x18,0x18,0x18,0x3C,0x00 ; l
    db 0x00,0x00,0x66,0x7F,0x7F,0x6B,0x63,0x00 ; m
    db 0x00,0x00,0x7C,0x66,0x66,0x66,0x66,0x00 ; n
    db 0x00,0x00,0x3C,0x66,0x66,0x66,0x3C,0x00 ; o
    db 0x00,0x00,0x7C,0x66,0x66,0x7C,0x60,0x60 ; p
    db 0x00,0x00,0x3E,0x66,0x66,0x3E,0x06,0x06 ; q
    db 0x00,0x00,0x7C,0x66,0x60,0x60,0x60,0x00 ; r
    db 0x00,0x00,0x3E,0x60,0x3C,0x06,0x7C,0x00 ; s
    db 0x30,0x30,0x7C,0x30,0x30,0x30,0x1C,0x00 ; t
    db 0x00,0x00,0x66,0x66,0x66,0x66,0x3E,0x00 ; u
    db 0x00,0x00,0x66,0x66,0x66,0x3C,0x18,0x00 ; v
    db 0x00,0x00,0x63,0x6B,0x7F,0x7F,0x36,0x00 ; w
    db 0x00,0x00,0x66,0x3C,0x18,0x3C,0x66,0x00 ; x
    db 0x00,0x00,0x66,0x66,0x66,0x3E,0x06,0x3C ; y
    db 0x00,0x00,0x7E,0x0C,0x18,0x30,0x7E,0x00 ; z
    db 0x0E,0x18,0x18,0x70,0x18,0x18,0x0E,0x00 ; {
    db 0x18,0x18,0x18,0x00,0x18,0x18,0x18,0x00 ; |
    db 0x70,0x18,0x18,0x0E,0x18,0x18,0x70,0x00 ; }
    db 0x76,0xDC,0x00,0x00,0x00,0x00,0x00,0x00 ; ~
    times (256-127)*8 db 0 

align 4
%macro VFS_ENTRY 5
%%start:
    db %1
    times 16 - ($ - %%start) db 0    
    dd %2, %3, %4, %5
%endmacro

vfs_table:
vfs_root:   VFS_ENTRY '/', 0, 1, 0, 0
vfs_bin:    VFS_ENTRY 'bin', vfs_root, 1, 0, 0
vfs_dev:    VFS_ENTRY 'dev', vfs_root, 1, 0, 0
vfs_ls:     VFS_ENTRY 'ls', vfs_bin, 0, 0, bin_ls
vfs_free:   VFS_ENTRY 'free', vfs_bin, 0, 0, bin_free
vfs_uptime: VFS_ENTRY 'uptime', vfs_bin, 0, 0, bin_uptime
vfs_test:   VFS_ENTRY 'test', vfs_bin, 0, 0, bin_test_syscall
vfs_f32fmt: VFS_ENTRY 'f32format', vfs_bin, 0, 0, bin_f32format
vfs_f32mnt: VFS_ENTRY 'f32mount', vfs_bin, 0, 0, bin_f32mount
vfs_f32ls:  VFS_ENTRY 'f32ls', vfs_bin, 0, 0, bin_f32ls
vfs_f32rd:  VFS_ENTRY 'f32read', vfs_bin, 0, 0, bin_f32read
vfs_f32wr:  VFS_ENTRY 'f32write', vfs_bin, 0, 0, bin_f32write
vfs_f32cd:  VFS_ENTRY 'f32cd', vfs_bin, 0, 0, bin_f32cd
vfs_f32rm:  VFS_ENTRY 'f32rm', vfs_bin, 0, 0, bin_f32rm
vfs_f32mk:  VFS_ENTRY 'f32mkdir', vfs_bin, 0, 0, bin_f32mkdir
vfs_lookie: VFS_ENTRY 'lookie.me', vfs_bin, 0, 0, bin_lookie
vfs_readme: VFS_ENTRY 'readme.txt', vfs_root, 0, 0, msg_readme
    db 0   

; =====================================================================
; KERNEL STRUCTURES & BSS (Uninitialized Memory)
; =====================================================================
section .bss
alignb 16                   
stack_bottom:
    resb 32768
stack_top:

alignb 8
idt_start: resq 256
idt_end:

task0_stack_res resb 4096
task0_stack_top:
task1_stack_res resb 4096
task1_stack_top:

alignb 4096                 
user_stack resb 4194304     
user_stack_top:
alignb 4                    
tss_entry resb 104

cursor_x resd 1
cursor_y resd 1
kb_buffer resb 256
kb_buffer_pos resd 1

key_state_map resb 128      

in_user_space resb 1        
kb_ring_buf   resb 256
kb_ring_head  resd 1
kb_ring_tail  resd 1

timer_ticks resd 1
itoa_buffer resb 16
current_dir_ptr resd 1
command_ready resb 1
shift_pressed resb 1
current_app_ptr resd 1      
current_app_entry resd 1      

user_heap_end resd 1        

fd_table_ext resb 4096      
current_pd resd 1           

win_active resb 1
win_x resd 1
win_y resd 1
win_width resd 1
win_height resd 1
win_buffer resd 1

win_bg_buffer resd 1
win_bg_saved  resb 1
win_bg_x      resd 1
win_bg_y      resd 1

mouse_x resd 1
mouse_y resd 1
mouse_buttons resd 1
mouse_cycle resb 1
mouse_packet resb 3

mouse_saved_pixels resd 25
mouse_saved_x resd 1
mouse_saved_y resd 1
mouse_is_drawn resb 1

vbe_framebuffer resd 1
vbe_pitch resd 1
vbe_width resd 1
vbe_height resd 1
vbe_bpp resb 1

fm_needs_update resb 1

current_task resd 1
task_esp     resd 2

mem_heap_ptr  resd 1
mem_total_used resd 1

sector_buffer resb 512
fat_buffer    resb 512
fat_target_name resb 11
lfn_buffer    resb 256        
user_input_buf resb 32      

fat32_bytes_per_sector  resw 1
fat32_sectors_per_clust resb 1
fat32_reserved_sectors  resw 1
fat32_num_fats          resb 1
fat32_sectors_per_fat   resd 1
fat32_root_cluster      resd 1
fat32_current_cluster   resd 1
fat32_fat_start_lba     resd 1
fat32_data_start_lba    resd 1
fat32_mounted           resb 1
fat32_path_str          resb 64
custom_text_ptr         resd 1

ramdisk_start           resd 1
ramdisk_end             resd 1

alignb 4096                 
page_directory resb 4096
page_tables    resb 262144  
page_table_vesa resb 4096