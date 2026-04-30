# NoVa-OS kernel build: "1.6.2", public build: "0.1", codename: "iftoman" (i forgot to make a name)
<img width="64" height="64" alt="NoVa-OS" src="https://github.com/user-attachments/assets/ae8daeb1-f68c-437b-8932-8ff0c7253efb" />

BASIC RUNDOWN:
Nova os is a 32-bit assembly code os, its packed with doom, a custom image renderer and global api windoew rendering called PlutoGL, a full fat 32 file system, RamDISKs, light C application support, full basic Posix style syncalls, full external userspace application support, a hybrid command line interface with PS/2 mouse support, and draggable windows provided by gui applicatons.

Artcitexture:
Nova os is a hobbist 32-bit x86 monolithic OS that can run completely off of ram, and will never have to touch a hard-drive.
Graphics are natively 1024x768 vesa.
Memory Management: Features a Physical Memory Manager (PMM) and Virtual Memory Manager (Paging)
Execution & Multitasking: Includes a custom ELF32 (.elf) executable loader. Applications run safely in Ring 3 User Space, communicating with the kernel via an int 0x80 syscall interface.
File System: Features a robust, from-scratch FAT32 Virtual File System (VFS). It supports Long File Names (LFN) and is loaded entirely into a RAM disk for quite-fast memory-mapped I/O :D
SYSTEM REQUIREMENTS (are to be optimized later in development!):
Any x86 processor, pentuim 1-4 is suspected to run perfectly, but not actually tested on real hardware, thats your job :D, only been tested in qemu and v86 at the momment, you need atleast 128mbs of ram, but 256bs is recomended for fully stable use, this will be optimized in later builds (these dang ram prices!)

How easy is it to fork?:
Well.. good for you to know, because the entire core kernel is ONLY 3763 lines of pure assembly code!, readable to any human wondering!

Can you make custom applications?:
YES! the kernel does support external userspace applications, with full assembly code application support, and basic C support its 100% possible, though currently there is no inhouse code compiler or editor inside the kernel at the momment, they will have to be developed externaly and put on the ram disk :/

Why should you care?:
well, you dont have to, this is just a really great passion project ive had for a very long time, it took me nearly a month in a half of on and off work to finish, and i just want others to see it, ive nearly ripped my hair out so many times, ive wanted to quit and leave this project in the dust so many times i can barely count.

Now.. for the question every one asks.. CAN IT DOOM?
infact, YEAH it can doom!, heres a screenshot of it running natively on NoVa-OS!
<img width="1366" height="768" alt="Screenshot 2026-04-30 12 14 57 PM" src="https://github.com/user-attachments/assets/97731537-4add-4c83-b34b-37facaa6075f" />

What about other applications?:
well we have PlutoGL.elf the custom bmp image renderer:
<img width="1020" height="767" alt="image" src="https://github.com/user-attachments/assets/c8959926-5580-4e3f-9df9-ada259e89b31" />

cube.elf a 3d cpu test:
<img width="1020" height="767" alt="image" src="https://github.com/user-attachments/assets/48b52e2f-0279-4097-8624-769c0d1ccdc5" />



