#!/bin/bash
set -e

if [[ $EUID -ne 0 ]]; then
  echo "❗ This script must be run as root. Try: sudo $0"
  exit 1
fi

# Check dependencies
for cmd in dd pv blockdev numfmt lsblk gzip gunzip; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "❌ Missing required command: $cmd"
    exit 1
  fi
done

choose_drive() {
  read -p "💽 Enter full device path (e.g., /dev/sda): " drive
  if ! lsblk "$drive" &>/dev/null; then
    echo "❌ '$drive' is not a valid block device."
    exit 1
  fi
  echo "$drive"
}

choose_partition() {
  read -p "💽 Enter full partition path (e.g., /dev/sdc1): " part
  if ! lsblk "$part" &>/dev/null; then
    echo "❌ '$part' is not a valid partition."
    exit 1
  fi
  echo "$part"
}

confirm_overwrite() {
  echo "⚠️ WARNING: You are about to overwrite $1"
  read -p "❗ Type YES to confirm: " CONFIRM
  if [ "$CONFIRM" != "YES" ]; then
    echo "❌ Aborted."
    exit 1
  fi
}

get_size() {
  blockdev --getsize64 "$1"
}

clone_with_progress() {
  local SRC="$1"
  local DEST="$2"
  local SIZE=$(get_size "$SRC")
  echo "📦 Source size: $(numfmt --to=iec $SIZE)"
  echo "⏳ Cloning with progress..."
  pv -s "$SIZE" "$SRC" | sudo dd of="$DEST" bs=64K status=progress conv=fsync
  echo "✔️ Done."
}

restore_image() {
  local SRC="$1"
  local DEST="$2"
  confirm_overwrite "$DEST"
  SIZE=$(stat --printf="%s" "$SRC")
  echo "📦 Image size: $(numfmt --to=iec $SIZE)"

  if [[ "$SRC" == *.gz ]]; then
    echo "📀 Decompressing on-the-fly..."
    pv -s "$SIZE" "$SRC" | gunzip -c | sudo dd of="$DEST" bs=64K status=progress conv=fsync
  else
    pv -s "$SIZE" "$SRC" | sudo dd of="$DEST" bs=64K status=progress conv=fsync
  fi
  echo "✔️ Restore complete."
}

# ---------------------- MAIN MENU ----------------------

while true; do
  echo "🧠 Welcome to LazyDD - Disk & Partition Cloner"
  echo "📋 Select an option:"
  echo "1) Clone entire disk to another disk"
  echo "2) Clone disk to image file"
  echo "3) Clone partition to image file"
  echo "4) Restore image file to disk"
  echo "5) Restore image file to partition"
  echo "6) Show available disks (lsblk)"
  echo "0) Exit"
  read -p "➡️ Enter your choice [0-6]: " CHOICE

  case $CHOICE in
  1)
    SRC=$(choose_drive)
    DEST=$(choose_drive)
    confirm_overwrite "$DEST"
    clone_with_progress "$SRC" "$DEST"
    ;;
  2)
    SRC=$(choose_drive)
    read -p "📀 Enter output image file path (e.g., /mnt/backup/disk.img): " DEST
    mkdir -p "$(dirname "$DEST")"
    clone_with_progress "$SRC" "$DEST"
    read -p "❓ Compress image with gzip? (y/n): " COMP
    [[ "$COMP" =~ ^[Yy]$ ]] && gzip -v "$DEST" && echo "🎉 Compressed to: $DEST.gz"
    ;;
  3)
    SRC_PART=$(choose_partition)
    read -p "📀 Enter output image file path (e.g., /mnt/backup/part.img): " DEST
    mkdir -p "$(dirname "$DEST")"
    clone_with_progress "$SRC_PART" "$DEST"
    read -p "❓ Compress image with gzip? (y/n): " COMP
    [[ "$COMP" =~ ^[Yy]$ ]] && gzip -v "$DEST" && echo "🎉 Compressed to: $DEST.gz"
    ;;
  4)
    read -p "📀 Enter image file (e.g., /mnt/backup/disk.img or .gz): " SRC
    DEST=$(choose_drive)
    restore_image "$SRC" "$DEST"
    ;;
  5)
    read -p "📀 Enter image file (e.g., /mnt/backup/part.img or .gz): " SRC
    DEST=$(choose_partition)
    restore_image "$SRC" "$DEST"
    ;;
  6)
    echo "🧮 Available disks and partitions:"
    lsblk -o NAME,SIZE,TYPE,MODEL
    ;;
  0)
    echo "👋 Bye!"
    exit 0
    ;;
  *)
    echo "❌ Invalid choice."
    ;;
  esac

  echo ""
done
