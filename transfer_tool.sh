#!/bin/bash
# HINT: If script has Windows line endings, run: 
# Mac (BSD):   sed -i '' $'s/\r$//' <file>
# Linux (GNU): sed -i 's/\r$//' <file>
# Universal  : tr -d '\r' < input.txt > output.txt

# 1. Cross-Platform Folder Picker
if [[ "$OSTYPE" == "darwin"* ]]; then
    sourcePath=$(osascript -e 'POSIX path of (choose folder with prompt "Select Source Folder (System)")')
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if command -v zenity &> /dev/null; then
        sourcePath=$(zenity --file-selection --directory --title="Select Source Folder")
    else
        read -p "Enter source folder path: " sourcePath
    fi
fi
[[ -z "$sourcePath" ]] && exit 1

# 2. Select Destination Disk (Filtered for /Volumes)
echo -e "\n--- Available External Disks / NAS ---"

if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS Logic: Look in /Volumes
    volumes=($(find /Volumes -maxdepth 1 -mindepth 1 -type d ! -name "Macintosh HD"))
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux Logic: Check common mount points
    # This combines /media, /run/media/$USER, and /mnt
    volumes=($(find /media /run/media/$USER /mnt -maxdepth 2 -mindepth 1 -type d 2>/dev/null))
fi

# If the list is empty, exit
if [ ${#volumes[@]} -eq 0 ]; then
    echo "No external volumes found! Please ensure your drive is mounted."
    exit 1
fi

# Display the list
for i in "${!volumes[@]}"; do
    echo "[$i] ${volumes[$i]}"
done

read -p "Select disk number: " choice
destDisk="${volumes[$choice]}"

# Setup CSV Logging
csvLog="./copying_$(date +%Y%m%d_%H%M).csv"
echo "Metric,Result" > "$csvLog"

run_benchmark() {
    local src=$1; local dstBase=$2; local mode=$3
    echo -e "\n>>> STARTING $mode SPEED TEST PHASE <<<" >&2
    
    # Calculate size in MB
    sizeMB=$(du -sm "$src" | cut -f1)

    for i in {1..5}; do
        echo -n "  Loop $i: Copying..." >&2
        targetDir="$dstBase/copyfiles_$(date +%H%M%S)"
        mkdir -p "$targetDir"
        
        start=$(date +%s.%N)
        rsync -a --no-o --no-g "$src/" "$targetDir/"
        end=$(date +%s.%N)
        
        runtime=$(echo "$end - $start" | bc)
        [[ $(echo "$runtime < 0.1" | bc) -eq 1 ]] && runtime=0.1
        
        # --- NEW: Format to 1 decimal place ---
        sec_fmt=$(printf "%.1f" $runtime)
        speed=$(echo "scale=2; $sizeMB / $runtime" | bc)
        
        # Save formatted results to CSV
        echo "time ($mode $i),${sec_fmt} s" >> "$csvLog"
        echo "speed ($mode $i),${speed} MB/s" >> "$csvLog"
        
        # Display formatted results to screen
        echo " DONE. Speed: ${speed} MB/s (${sec_fmt}s)" >&2
        
        if [[ $i -lt 5 ]]; then 
            rm -rf "$targetDir"
        else 
            echo "$targetDir" 
        fi
    done
}


# Run Benchmark and Capture last folder paths for cleanup
lastOnDisk=$(run_benchmark "$sourcePath" "$destDisk" "Write" | tail -n 1)
lastOnSys=$(run_benchmark "$lastOnDisk" "$sourcePath" "Read" | tail -n 1)

# 11. Final Cleanup
echo -e "\nCleaning up test folders..."
rm -rf "$lastOnDisk"
rm -rf "$lastOnSys"

echo -e "Done! CSV Results: $csvLog"
