#!/bin/bash
set -e

# Check required commands
for cmd in dd pv blockdev numfmt lsblk gzip gunzip; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "❌ Required command '$cmd' not found. Please install it."
        exit 1
    fi
done

list_drives() {
    echo "Available drives:"
    lsblk -dno NAME,SIZE,MODEL | awk '{print "/dev/"$1, $2, $3}'
}

list_partitions() {
    local drive=$1
    echo "Partitions on $drive:"
    lsblk -lnpo NAME,SIZE,TYPE "$drive" | awk '$3=="part" {print $1, $2}'
}

choose_drive() {
    mapfile -t drives < <(lsblk -dno NAME,SIZE,MODEL | awk '{print "/dev/"$1" "$2" "$3}')
    echo "Available drives:"
    for i in "${!drives[@]}"; do
        printf "%d) %s\n" $((i+1)) "${drives[$i]}"
    done
    read -p "💽 Select a drive by number or enter device path: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        if ((choice < 1 || choice > ${#drives[@]})); then
            echo "❌ Invalid selection."
            exit 1
        fi
        echo "${drives[$((choice-1))]}" | awk '{print $1}'
    else
        if [ ! -b "$choice" ]; then
            echo "❌ Invalid device path."
            exit 1
        fi
        echo "$choice"
    fi
}

choose_partition() {
    local drive=$1
    mapfile -t parts < <(lsblk -lnpo NAME,SIZE,TYPE "$drive" | awk '$3=="part" {print $1" "$2}')
    if [ ${#parts[@]} -eq 0 ]; then
        echo "❌ No partitions found on $drive"
        exit 1
    fi
    echo "Partitions on $drive:"
    for i in "${!parts[@]}"; do
        printf "%d) %s\n" $((i+1)) "${parts[$i]}"
    done
    read -p "💽 Select a partition by number or enter partition path: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        if ((choice < 1 || choice > ${#parts[@]})); then
            echo "❌ Invalid selection."
            exit 1
        fi
        echo "${parts[$((choice-1))]}" | awk '{print $1}'
    else
        if [ ! -b "$choice" ]; then
            echo "❌ Invalid partition path."
            exit 1
        fi
        echo "$choice"
    fi
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
    local SRC=$1
    local DEST=$2
    confirm_overwrite "$DEST"
    SIZE=$(stat --printf="%s" "$SRC")
    echo "📦 Image size: $(numfmt --to=iec $SIZE)"

    if [[ "$SRC" == *.gz ]]; then
        echo "📀 Detected compressed image, decompressing on the fly..."
        pv -s "$SIZE" "$SRC" | gunzip -c | sudo dd of="$DEST" bs=64K status=progress conv=fsync
    else
        pv -s "$SIZE" "$SRC" | sudo dd of="$DEST" bs=64K status=progress conv=fsync
    fi

    echo "✔️ Restore complete."
}

echo "📀 Welcome to LazyDD - Disk & Partition Cloner"
echo "📋 Select an option:"
echo "1) Clone entire disk to another disk"
echo "2) Clone disk to image file"
echo "3) Clone partition to image file"
echo "4) Restore image file to disk"
echo "5) Restore image file to partition"
read -p "➡️ Enter your choice [1-5]: " CHOICE

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
    read -p "❓ Do you want to compress the image with gzip? (y/n): " COMP
    if [[ "$COMP" =~ ^[Yy]$ ]]; then
        echo "📚 Compressing..."
        gzip -v "$DEST"
        echo "🎉 Compressed to: $DEST.gz"
    fi
    ;;
  3)
    SRC_DRIVE=$(choose_drive)
    SRC=$(choose_partition "$SRC_DRIVE")
    read -p "📀 Enter output image file path (e.g., /mnt/backup/part.img): " DEST
    mkdir -p "$(dirname "$DEST")"
    clone_with_progress "$SRC" "$DEST"
    read -p "❓ Do you want to compress the image with gzip? (y/n): " COMP
    if [[ "$COMP" =~ ^[Yy]$ ]]; then
        echo "📚 Compressing..."
        gzip -v "$DEST"
        echo "🎉 Compressed to: $DEST.gz"
    fi
    ;;
  4)
    read -p "📀 Enter input image file (e.g., /mnt/backup/disk.img or disk.img.gz): " SRC
    DEST=$(choose_drive)
    restore_image "$SRC" "$DEST"
    ;;
  5)
    read -p "📀 Enter input image file (e.g., /mnt/backup/part.img or part.img.gz): " SRC
    SRC_DRIVE=$(choose_drive)
    DEST=$(choose_partition "$SRC_DRIVE")
    restore_image "$SRC" "$DEST"
    ;;
  *)
    echo "❌ Invalid option."
    exit 1
    ;;
esac
