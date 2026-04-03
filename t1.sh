#!/bin/bash

choose_drive() {
    echo "🧮 Disks:"
    lsblk --json -d -o NAME,SIZE,MODEL,TYPE | jq
    echo
    read -p "💽 Enter full device path (e.g., /dev/sda): " drive
    echo "You chose: $drive"
}

choose_drive

