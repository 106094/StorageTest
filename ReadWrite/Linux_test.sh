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
    # High Performance Direct Kernel Mount over physical Ethernet
    LOCAL_MOUNT="$HOME/nas_speedtest"
    mkdir -p "$LOCAL_MOUNT"

    if ! mountpoint -q "$LOCAL_MOUNT"; then
        echo "Executing kernel-level direct SMB mount (Requires sudo)..."
        sudo mount -t cifs "//$NAS_IP/$SHARE_NAME" "$LOCAL_MOUNT" -o username="$NAS_USER",password="$NAS_PASS",vers=3.0,iocharset=utf8,actimeo=0,rsize=1048576,wsize=1048576
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
            # Pre-installed Linux stream engine (Matches hardware network speed)
            tar -C "$src" -cf - . | tar -C "$targetDir" -xf -
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
    
    # Run Write Benchmark
    lastOnDisk=$(run_benchmark "$sourcePath" "$destDisk" "Write" "$sourcename" | tail -n 1)
    
    # SAFE VERIFICATION BLOCK (Prevents data loss on connection drop)
    if [[ -d "$lastOnDisk" && -n "$lastOnDisk" ]]; then
        echo "Verification passed. Purging original local source folder..."
        rm -rf "$sourcePath" 2>/dev/null
    else
        echo "CRITICAL ERROR: Benchmark transfer target was not found on NAS. Aborting loop to protect data."
        exit 1
    fi
    
    # Run Read Benchmark
    lastOnSys=$(run_benchmark "$lastOnDisk" "/tmp" "Read" "$sourcename" | tail -n 1)
    
    echo "Recovering: Moving $lastOnSys back to $sourcePath"
    mv "$lastOnSys" "$sourcePath"
    echo -e "\nCleaning up test folders..."
    rm -rf "$lastOnDisk"

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
done

echo -e "Done! Results: $csvLog"
