#!/bin/bash
unalias rm 2>/dev/null

# =================================================================
# DYNAMIC CONFIGURATION LOADER (Reads from nas_config.txt)
# =================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/nas_config.txt"

# Check if configuration file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "================================================================="
    echo "ERROR: Configuration file not found!"
    echo "Please create a file named 'nas_config.txt' in the same folder."
    echo "================================================================="
    exit 1
fi

# Load and parse configuration while ignoring comments and empty lines
while IFS='=' read -r key value; do
    # Trim whitespace, skip comments (#) and empty lines
    [[ "$key" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$key" ]] && continue
    
    # Strip carriage returns (fixes issues if edited on Windows)
    key=$(echo "$key" | tr -d '\r' | xargs)
    value=$(echo "$value" | tr -d '\r' | xargs)
    
    case "$key" in
        NAS_IP) NAS_IP="$value" ;;
        SHARE_NAME) SHARE_NAME="$value" ;;
        NAS_USER) NAS_USER="$value" ;;
        NAS_PASS) NAS_PASS="$value" ;;
    esac
done < "$CONFIG_FILE"

# Validate that all required fields are filled
if [[ -z "$NAS_IP" || -z "$SHARE_NAME" || -z "$NAS_USER" || -z "$NAS_PASS" ]]; then
    echo "ERROR: Missing settings in nas_config.txt. Please check all fields."
    exit 1
fi

echo "Configuration loaded successfully for NAS: $NAS_IP"

# =================================================================
# 1. Select Destination Disk
# =================================================================
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
    # High Performance Direct Kernel Mount over physical Ethernet (Sync & Cache-less)
    LOCAL_MOUNT="$HOME/nas_speedtest"
    mkdir -p "$LOCAL_MOUNT"

    if ! mountpoint -q "$LOCAL_MOUNT"; then
        echo "Executing kernel-level direct SMB mount (Requires sudo)..."
        sudo mount -t cifs "//$NAS_IP/$SHARE_NAME" "$LOCAL_MOUNT" -o username="$NAS_USER",password="$NAS_PASS",sync,cache=none,actimeo=0,vers=3.0,uid=$(id -u),gid=$(id -g),forceuid,forcegid       

    fi

    if mountpoint -q "$LOCAL_MOUNT"; then
        echo "NAS successfully mounted natively at $LOCAL_MOUNT"
        destDisk="$LOCAL_MOUNT"
    else
        echo "Error: High-performance kernel mount failed. Verify network or credentials."
        exit 1
    fi
fi

# --- Dynamic Recycle Bin Detection ---
recycleName=""
for name in "@Recycle" "#recycle" "#Recycle" "@recycle" "Network Trash Folder"; do
    if [[ -d "$destDisk/$name" ]]; then
        recycleName="$name"
        break
    fi
done
[[ -n "$recycleName" ]] && echo "Detected Recycle Bin: $recycleName"

# =================================================================
# 2. Multi-Folder Picker in a Loop
# =================================================================
sources=()
while true; do
    if [[ "$OSTYPE" == "darwin"* ]]; then
        path=$(osascript -e 'POSIX path of (choose folder with prompt "Select Source Folder")')
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v zenity &> /dev/null; then
            path=$(zenity --file-selection --directory --title="Select Source Folder")
        else
            read -p "Enter source folder path: " path
        fi
    fi
    [[ -z "$path" ]] && break
    sources+=("$path")
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        res=$(osascript -e 'button returned of (display dialog "Add another folder?" buttons {"No", "Yes"} default button "Yes")')
    else
        if command -v zenity &> /dev/null; then
            zenity --question --text="Add another folder?" --ok-label="Yes" --cancel-label="No" 2>/dev/null
            res=$([[ $? -eq 0 ]] && echo "Yes" || echo "No")
        else
            read -p "Add another folder? (y/n): " choice
            res=$([[ "$choice" == "y" || "$choice" == "Y" ]] && echo "Yes" || echo "No")
        fi
    fi
    [[ "$res" == "No" ]] && break
done

[[ ${#sources[@]} -eq 0 ]] && exit 1

# Setup CSV
csvLog="./WriteReadLog_$(date +%Y%m%d_%H%M).csv"
echo "Source,Metric,Result" > "$csvLog"

# =================================================================
# 3. Benchmark Logic
# =================================================================
run_benchmark() {
    local src=$1; local dstBase=$2; local mode=$3; local sName=$4
    echo -e "\n>>> STARTING $mode SPEED TEST ($sName) <<<" >&2
    
    sizeMB=$(du -sm "$src" | cut -f1)

    for i in {1..5}; do
        echo -n "  Loop $i: Copying..." >&2
        targetDir=$([[ "$mode" == "Read" ]] && echo "/tmp/readtest_$i" || echo "$dstBase/${mode}Test_$i")       
        mkdir -p "$targetDir"
        
        start=$(date +%s.%N)
        
        # --- High Compatibility Optimized Copy Logic ---
        if [[ "$OSTYPE" == "darwin"* ]]; then
            ditto "$src" "$targetDir"
        else
            # Human Action Mimicking Engine (rsync closely matches File Explorer overhead)
             rsync -aHAX --no-compress "$src/" "$targetDir/"
            #cp -r "$src/." "$targetDir/"
            #tar -C "$src" -cf - . | tar -xf - -C "$targetDir"
        fi
        
        # Force flush physical hardware and network pipe buffers
        sync 
        # ----------------------------

        end=$(date +%s.%N)
        runtime=$(echo "$end - $start" | bc)
        [[ $(echo "$runtime < 0.01" | bc) -eq 1 ]] && runtime=0.01
        speed=$(echo "scale=2; $sizeMB / $runtime" | bc)
        
        echo "$sName,time ($mode $i),$(printf "%.2f" $runtime) s" >> "$csvLog"
        echo "$sName,speed ($mode $i),${speed} MB/s" >> "$csvLog"
        echo " DONE: ${speed} MB/s" >&2
        
        if [[ $i -lt 5 ]]; then
            rm -rf "$targetDir"
            if [[ "$mode" == "Write" ]]; then
                local local_recycle=""
                for r_name in "@Recycle" "#recycle" "#Recycle" "@recycle" "Network Trash Folder"; do
                    if [[ -d "$dstBase/$r_name" ]]; then
                        local_recycle="$dstBase/$r_name"
                        break
                    fi
                done
                if [[ -n "$local_recycle" ]]; then
                    echo -n "    [Loop $i] Force Purging NAS Recycle Bin..." >&2
                    { rm -rf "$local_recycle"/* "$local_recycle"/.[^.]*; } 2>/dev/null
                    sync
                    
                    local p_attempts=0
                    while [ -n "$(ls -A "$local_recycle" 2>/dev/null)" ] && [ $p_attempts -lt 3 ]; do
                        ((p_attempts++))
                        sleep 1 && echo -n "." >&2
                        { rm -rf "$local_recycle"/* "$local_recycle"/.[^.]*; } 2>/dev/null
                        sync
                    done
                    echo " Cleared." >&2
                fi
            fi
        else 
            echo "$targetDir"
        fi

    done
}

# =================================================================
# 4. Main Execution Loop
# =================================================================
for sourcePath in "${sources[@]}"; do
    sourcename=$(basename "$sourcePath")
    
    lastOnDisk=$(run_benchmark "$sourcePath" "$destDisk" "Write" "$sourcename" | tail -n 1)
    
    srcCount=$(find "$sourcePath" | wc -l)
    dstCount=0
    if [[ -d "$lastOnDisk" && -n "$lastOnDisk" ]]; then
        dstCount=$(find "$lastOnDisk" | wc -l)
    fi

    if [ "$dstCount" -eq "$srcCount" ] && [ "$dstCount" -gt 0 ]; then
        echo "Verification passed (File count matched: $dstCount). Purging original local source folder..."
        rm -rf "$sourcePath" 2>/dev/null
    else
        echo "CRITICAL ERROR: File count mismatch or transfer failed (Local: $srcCount, NAS: $dstCount). Aborting loop."
        exit 1
    fi
    
    lastOnSys=$(run_benchmark "$lastOnDisk" "/tmp" "Read" "$sourcename" | tail -n 1)
    
    echo "Recovering: Moving $lastOnSys back to $sourcePath"
    mv "$lastOnSys" "$sourcePath"
    
    echo -e "\nCleaning up test folders on NAS..."
    rm -rf "$lastOnDisk"

    if [ -n "$recycleName" ] && [ -d "$destDisk/$recycleName" ]; then
        echo -n "Performing final NAS Recycle Bin purge..."
        { rm -rf "$destDisk/$recycleName"/* "$destDisk/$recycleName"/.[^.]*; } 2>/dev/null
        sync
        echo " Ready." >&2
    fi
     
done

# =================================================================
# 5. Unmount
# =================================================================
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if mountpoint -q "$LOCAL_MOUNT"; then
        echo -e "\nAll benchmarks completed. Unmounting NAS natively..."
        sudo umount -l "$LOCAL_MOUNT"
    fi
fi

echo -e "\nDone! Results: $csvLog"
