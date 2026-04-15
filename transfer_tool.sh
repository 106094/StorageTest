#!/bin/bash
unalias rm 2>/dev/null

# 1. Cross-Platform Folder Picker
if [[ "$OSTYPE" == "darwin"* ]]; then
    sourcePath=$(osascript -e 'POSIX path of (choose folder with prompt "Select Source Folder")')
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if command -v zenity &> /dev/null; then
        sourcePath=$(zenity --file-selection --directory --title="Select Source Folder")
    else
        read -p "Enter source folder path: " sourcePath
    fi
fi
[[ -z "$sourcePath" ]] && exit 1

# 2. Select Destination Disk
echo -e "\n--- Available External Disks ---"
if [[ "$OSTYPE" == "darwin"* ]]; then
    volumes=($(find /Volumes -maxdepth 1 -mindepth 1 -type d ! -name "Macintosh HD" | grep -Ff <(smbutil statshares -a | awk '/^[A-Za-z]/ && !/SHARE/ && !/===/ {print $1}')))
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    volumes=($(lsblk -p -n -o MOUNTPOINT | grep -E '^/mnt/|^/media/' | grep -vE '^/mnt/(c|wsl|wslg)($|/)'))
    if [ ${#volumes[@]} -eq 0 ]; then
        volumes=($(find /mnt -maxdepth 1 -mindepth 1 -type d ! -path "/mnt/c" ! -path "/mnt/wsl*"))
    fi
fi

if [ ${#volumes[@]} -eq 0 ]; then
    echo "No external volumes found! Check mounting."
    exit 1
fi

for i in "${!volumes[@]}"; do echo "[$i] ${volumes[$i]}"; done
read -p "Select disk number: " choice
destDisk="${volumes[$choice]}"

# Setup CSV
csvLog="./copying_$(date +%Y%m%d_%H%M).csv"
echo "Metric,Result" > "$csvLog"

run_benchmark() {
    local src=$1; local dstBase=$2; local mode=$3
    echo -e "\n>>> STARTING $mode SPEED TEST PHASE <<<" >&2
    sizeMB=$(du -sm "$src" | cut -f1)

    for i in {1..5}; do
        echo -n "  Loop $i: Copying..." >&2
        
        if [[ "$mode" == "Read" ]]; then
            targetDir="/tmp/readtest_$(date +%H%M%S)"
        else
            targetDir="$dstBase/copyfiles_$(date +%H%M%S)"
        fi
        
        mkdir -p "$targetDir"
        
        start=$(date +%s.%N)
        rsync -rlD --no-p --no-o --no-g --size-only --exclude={'@Recycle','@Recently-Snapshot'} "$src/" "$targetDir/"
        end=$(date +%s.%N)
        
        runtime=$(echo "$end - $start" | bc)
        [[ $(echo "$runtime < 0.1" | bc) -eq 1 ]] && runtime=0.1
        
        sec_fmt=$(printf "%.1f" $runtime)
        speed=$(echo "scale=2; $sizeMB / $runtime" | bc)
        
        echo "time ($mode $i),${sec_fmt} s" >> "$csvLog"
        echo "speed ($mode $i),${speed} MB/s" >> "$csvLog"
        echo " DONE. Speed: ${speed} MB/s (${sec_fmt}s)" >&2
        
        if [[ $i -lt 5 ]]; then
            rm -rf "$targetDir"
            if [[ "$mode" == "Write" && -d "$dstBase/@Recycle" ]]; then
                echo -n "  Purging NAS Recycle Bin..." >&2
                attempts=0
                while [ -n "$(ls -A "$dstBase/@Recycle" 2>/dev/null)" ] && [ $attempts -lt 5 ]; do
                    # Corrected spacing and semicolons inside braces
                    { rm -rf "$dstBase"/@Recycle/.[^.]* "$dstBase"/@Recycle/*; } 2>/dev/null
                    ((attempts++))
                    [[ $attempts -lt 5 ]] && sleep 2 && echo -n "." >&2
                    { rm -rf "$destDisk"/@Recycle/.[^.]* "$destDisk"/@Recycle/*; } 2>/dev/null 
                done
                echo " Ready." >&2
            fi
        else 
            echo "$targetDir"
        fi
    done
}

# 4. Execute
lastOnDisk=$(run_benchmark "$sourcePath" "$destDisk" "Write" | tail -n 1)
lastOnSys=$(run_benchmark "$lastOnDisk" "/tmp" "Read" | tail -n 1)

# Cleanup
echo -e "\nCleaning up..."
rm -rf "$lastOnDisk"
rm -rf "$lastOnSys"

# Final Recycle Bin Purge
if [ -d "$destDisk/@Recycle" ]; then
    echo -n "Performing final NAS Recycle Bin purge..."
    attempts=0     
    while [ -n "$(ls -A "$destDisk/@Recycle" 2>/dev/null)" ] && [ $attempts -lt 5 ]; do
        { rm -rf "$destDisk"/@Recycle/.[^.]* "$destDisk"/@Recycle/*; } 2>/dev/null
        ((attempts++))
        [[ $attempts -lt 5 ]] && sleep 2 && echo -n "." >&2
        { rm -rf "$destDisk"/@Recycle/.[^.]* "$destDisk"/@Recycle/*; } 2>/dev/null
    done
    echo " Ready." >&2
fi

echo -e "Done! Results: $csvLog"
