#!/bin/bash

#sed -i '' $'s/\r$//' <file>
# 1. Input Source
read -p "Enter source folder path: " sourcePath

# 2. Select Destination Disk
echo -e "\nAvailable Mounts:"
select destDisk in $(df -h | grep -v "loop" | awk '{print $NF}' | tail -n +2); do
    [[ -n $destDisk ]] && break
done

csvLog="./copying_$(date +%Y%m%d_%H%M).csv"
echo "Metric,Result" > "$csvLog"

run_transfer() {
    local src=$1; local dstBase=$2
    sizeMB=$(du -sm "$src" | cut -f1)

    for i in {1..5}; do
        targetDir="$dstBase/copyfiles_$(date +%H%M%S)"
        mkdir -p "$targetDir"
        
        start=$(date +%s.%N)
        rsync -a "$src/" "$targetDir/"
        end=$(date +%s.%N)
        
        runtime=$(echo "$end - $start" | bc)
        speed=$(echo "scale=2; $sizeMB / $runtime" | bc)
        
        echo "time ($i),${runtime} s" >> "$csvLog"
        echo "speed ($i),${speed} MB/s" >> "$csvLog"
        
        [[ $i -lt 5 ]] && rm -rf "$targetDir" || lastFolder="$targetDir"
    done
}

run_transfer "$sourcePath" "$destDisk"
run_transfer "$lastFolder" "$sourcePath"
echo "Results saved to $csvLog"
