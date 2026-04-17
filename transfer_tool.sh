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
	if [ ${#volumes[@]} -eq 0 ]; then
	    echo "No external volumes found! Check mounting."
	    exit 1
	fi
	for i in "${!volumes[@]}"; do echo "[$i] ${volumes[$i]}"; done
	read -p "Select disk number: " choice
	destDisk="${volumes[$choice]}"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
	MY_UID=$(id -u)
	VIRTUAL_PATH=$(ls -d /run/user/$MY_UID/gvfs/smb-share* 2>/dev/null)
	if [[ -d "$VIRTUAL_PATH" ]]; then
	    echo "NAS found at $VIRTUAL_PATH"
	    rm -f ~/nas_link
	    ln -s "$VIRTUAL_PATH" ~/nas_link
	    destDisk="$HOME/nas_link"
	else
	    echo "Warning: NAS not found! Please click the NAS in your file manager first."
	    exit 1
	fi
fi
# --- NEW: Dynamic Recycle Bin Detection ---
recycleName=""
for name in "@Recycle" "#recycle" "@recycle" "Network Trash Folder"; do
    if [[ -d "$destDisk/$name" ]]; then
        recycleName="$name"
        break
    fi
done
[[ -n "$recycleName" ]] && echo "Detected Recycle Bin: $recycleName"

# Setup CSV
csvLog="./copying_$(date +%Y%m%d_%H%M).csv"
echo "Metric,Result" > "$csvLog"

run_benchmark() {
    local src=$1; local dstBase=$2; local mode=$3
    echo -e "\n>>> STARTING $mode SPEED TEST PHASE <<<" >&2
    sizeMB=$(du -sm "$src" | cut -f1)

    for i in {1..5}; do
        echo -n "  Loop $i: Copying..." >&2
        targetDir=$([[ "$mode" == "Read" ]] && echo "/tmp/readtest_$i" || echo "$dstBase/${mode}Test_$i")       
        mkdir -p "$targetDir"
        start=$(date +%s.%N)
        rsync -rlD --inplace --no-p --no-o --no-g --size-only --exclude={"$recycleName","@Recently-Snapshot"} "$src/" "$targetDir"
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
				 {  rm -rf "$dstBase/$recycleName"/* "$dstBase/$recycleName"/.[^.]*; } 2>/dev/null
                sleep 2 
                attempts=0
                while [ -n "$(ls -A "$dstBase/@Recycle" 2>/dev/null)" ] && [ $attempts -lt 5 ]; do
                    # Corrected spacing and semicolons inside braces
                    ((attempts++))
                    [[ $attempts -lt 5 ]] && sleep 2 && echo -n "." >&2
				     {  rm -rf "$dstBase/$recycleName"/* "$dstBase/$recycleName"/.[^.]*; } 2>/dev/null
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
if [ -d "$destDisk/$recycleName" ]; then
    echo -n "Performing final NAS Recycle Bin purge..."
	{ rm -rf "$destDisk/$recycleName"/* "$destDisk/$recycleName"/.[^.]*; } 2>/dev/null
    sleep 2
    attempts=0     
    while [ -n "$(ls -A "$destDisk/$recycleName" 2>/dev/null)" ] && [ $attempts -lt 5 ]; do
        ((attempts++))
        [[ $attempts -lt 5 ]] && sleep 2 && echo -n "." >&2
	    { rm -rf "$destDisk/$recycleName"/* "$destDisk/$recycleName"/.[^.]*; } 2>/dev/null
    done
    echo " Ready." >&2
fi

echo -e "Done! Results: $csvLog"
