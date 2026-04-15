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
    volumes=($(find /Volumes -maxdepth 1 -mindepth 1 -type d ! -name "Macintosh HD" | grep -Ff <(smbutil statshares -a | awk '/^[A-Za-z]/ && !/SHARE/ && !/===/ {print $1}')
))
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

# 3. Cache Clearing Logic (Crucial for Read Speed) User Experience without clearing the cache,
#clear_cache() {
#    echo -n "  Clearing RAM Cache..." >&2
#    if [[ "$OSTYPE" == "darwin"* ]]; then
#        sudo purge
#   elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
#        sync && echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
#   fi
#   echo " Done." >&2
#}
run_benchmark() {
    local src=$1; local dstBase=$2; local mode=$3
    echo -e "\n>>> STARTING $mode SPEED TEST PHASE <<<" >&2
    sizeMB=$(du -sm "$src" | cut -f1)

    for i in {1..5}; do
        echo -n "  Loop $i: Copying..." >&2
        
        # For Read phase, use /tmp to avoid permission issues
        if [[ "$mode" == "Read" ]]; then
            targetDir="/tmp/readtest_$(date +%H%M%S)"
        else
            targetDir="$dstBase/copyfiles_$(date +%H%M%S)"
        fi
        
        mkdir -p "$targetDir"
        
        start=$(date +%s.%N)
        # Using rsync without sync for maximum "User Experience" speed
        rsync -rlD --no-p --no-o --no-g --size-only "$src/" "$targetDir/"
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
              {rm -rf "$dstBase"/@Recycle/*} 2>/dev/null
            fi
        else echo "$targetDir"
        fi
    done
}

# 4. Execute
# Write: System -> USB
lastOnDisk=$(run_benchmark "$sourcePath" "$destDisk" "Write" | tail -n 1)

# Read: USB -> System (/tmp)
lastOnSys=$(run_benchmark "$lastOnDisk" "/tmp" "Read" | tail -n 1)

# Cleanup
echo -e "\nCleaning up..."
rm -rf "$lastOnDisk"
rm -rf "$lastOnSys"

# Final Recycle Bin Purge
if [ -d "$destDisk/@Recycle" ]; then
    echo "Performing final NAS Recycle Bin purge..."
    {rm -rf "$destDisk"/@Recycle/*} 2>/dev/null
fi
echo -e "Done! Results: $csvLog"
