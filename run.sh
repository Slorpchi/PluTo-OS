#!/bin/bash

# 0. Auto-fix KVM permissions if Codespace restarted
if [ -e /dev/kvm ]; then
    sudo chmod 666 /dev/kvm 2>/dev/null
fi

# 1. Check if the user provided a keyword
if [ -z "$1" ]; then
  echo "Usage: ./run.sh <os-keyword>"
  echo "Example: ./run.sh puppy"
  echo "Example: ./run.sh nova"
  exit 1
fi

KEYWORD=$1

# 3. Kill the old OS
echo "Shutting down the current QEMU instance..."
killall qemu-system-x86_64 qemu-system-i386 2>/dev/null
sleep 1 

# =====================================================================
# CUSTOM NoVa OS COMPILE & BOOT ROUTINE
# =====================================================================
if [[ "${KEYWORD,,}" == *"nova"* ]]; then
    echo "NoVa OS detected: Compiling from source..."
    
    # FIX 1: Tell the Makefile to build the full ISO!
    make nova.iso hdd.img
    
    if [ $? -ne 0 ]; then
        echo "Error: Compilation failed. Check your assembly code!"
        exit 1
    fi

    echo "Booting NoVa OS with VESA Graphics and RAM-Disk..."
    # FIX: The RAM-Disk is inside the ISO now! We don't need the -drive flag!
    qemu-system-i386 -cdrom nova.iso -m 128M -boot d -vga std -display vnc=:0 -no-reboot &
# =====================================================================
# STANDARD ISO BOOT ROUTINE
# =====================================================================
else
    # Search for the first matching .iso file in the current directory
    ISO_FILE=$(find . -maxdepth 2 -iname "*${KEYWORD}*.iso" | head -n 1)

    if [ -z "$ISO_FILE" ]; then
      echo "Error: No .iso file found matching '${KEYWORD}'."
      exit 1
    fi

    echo "Found OS: $ISO_FILE"

    # Smart Hardware Settings
    VGA_FLAG="-vga virtio"
    CPU_FLAG="-cpu host -enable-kvm"
    AUDIO_FLAG="-audiodev none,id=ad0"

    if [[ "${ISO_FILE,,}" == *"react"* ]]; then
      echo "ReactOS detected: Switching to standard VGA drivers."
      VGA_FLAG="-vga std"
    elif [[ "${ISO_FILE,,}" == *"temple"* ]]; then
      echo "TempleOS detected: Engaging retro mode (No KVM, Core2Duo CPU, PC Speaker routing)."
      VGA_FLAG="-vga std"
      CPU_FLAG="-cpu core2duo"
      AUDIO_FLAG="-audiodev none,id=ad0 -machine pcspk-audiodev=ad0"
    elif [[ "${ISO_FILE,,}" == *"vib"* ]]; then
      echo "Vib-OS detected: Preparing for AI slop (Switching to standard VGA)."
      VGA_FLAG="-vga std"
    fi

    # Boot the new OS
    echo "Booting up..."
    qemu-system-x86_64 -m 2048 -smp 2 $CPU_FLAG $VGA_FLAG -display vnc=:0 $AUDIO_FLAG -cdrom "$ISO_FILE" -boot d &
fi

# 6. Ensure the noVNC bridge is running
if ! pgrep -x "websockify" > /dev/null; then
    echo "Starting noVNC bridge on port 6080..."
    websockify --web=/usr/share/novnc/ 6080 localhost:5900 > /dev/null 2>&1 &
fi

echo "Success! Refresh your noVNC browser tab to see the new OS."