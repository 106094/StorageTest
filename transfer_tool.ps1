# 1. Input Source
# Load the required Windows Forms assembly
Add-Type -AssemblyName System.Windows.Forms

# Create the Folder Browser Dialog object
$folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
$folderBrowser.Description = "Select the source folder to transfer"
$folderBrowser.ShowNewFolderButton = $false

# Show the popup and check if the user clicked 'OK'
$dialogResult = $folderBrowser.ShowDialog()

if ($dialogResult -eq "OK") {
    $source = $folderBrowser.SelectedPath
    Write-Host "Source selected: $source" -ForegroundColor Green
} else {
    Write-Host "No folder selected. Exiting..." -ForegroundColor Red
    exit
}


# 2. Select Destination Disk from List
$disks = Get-PSDrive -PSProvider FileSystem | Where-Object {$_.Name -ne "C" -and $_.Free -ne $null }
Write-Host "`n--- Select Destination Disk (Input Number) ---" -ForegroundColor Cyan
for ($i=0; $i -lt $disks.Count; $i++) { 
    Write-Host "[$i] $($disks[$i].Name): ($($disks[$i].Root))" 
}
$choice = Read-Host "Enter number"
$destDisk = "$($disks[[int]$choice].Name):\"


# Setup CSV Logging
$timestamp = Get-Date -Format "yyyyMMdd_HHmm"
$csvLog = Join-Path $PSScriptRoot "copying_$timestamp.csv"
"Metric,Result" | Out-File -FilePath $csvLog -Encoding utf8

function Run-Transfer ($src, $dstBase, $type) {
    # Calculate size for speed (MB)
    $files = Get-ChildItem $src -Recurse -File
    $totalSize = ($files | Measure-Object -Property Length -Sum).Sum / 1MB
    
    for ($i=1; $i -le 5; $i++) {
        $targetDir = Join-Path $dstBase "copyfiles_$(Get-Date -Format 'HHmmss')"
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        
        $start = Get-Date
        Copy-Item -Path "$src\*" -Destination $targetDir -Recurse -Force
        $end = Get-Date
        
        # PowerShell 5.1 Compatible Verification (Sample File)
        $srcFile = (Get-ChildItem $src -File | Select-Object -First 1).FullName
        $dstFile = (Get-ChildItem $targetDir -File | Select-Object -First 1).FullName
        $srcHash = (Get-FileHash $srcFile).Hash
        $dstHash = (Get-FileHash $dstFile).Hash
        
        if ($srcHash -eq $dstHash) { $status = "Verified" } else { $status = "FAILED" }
        
        $sec = [math]::Round(($end - $start).TotalSeconds, 2)
        $speed = [math]::Round($totalSize / $sec, 2)
        
        # Save to CSV exactly as requested
        "$type time ($i),$sec s" | Out-File -FilePath $csvLog -Append -Encoding utf8
        "$type speed ($i),$speed MB/s" | Out-File -FilePath $csvLog -Append -Encoding utf8
        
        Write-Host "$type Loop $($i): $sec s | $speed MB/s | Result: $status"
        
        # 9. Delete unless it's the last loop
        if ($i -lt 5) { 
            Remove-Item $targetDir -Recurse -Force 
        } else { 
            $global:lastTarget = $targetDir 
        }
    }
}

# Run Forward
Write-Host "`n--- Starting Forward Transfer ---" -ForegroundColor Green
Run-Transfer $source $destDisk "Write"

# Run Reverse (10. Loop 5 times from Destination back to Source)
Write-Host "`n--- Starting Reverse Transfer ---" -ForegroundColor Yellow
Run-Transfer $global:lastTarget $source "Read"

Write-Host "`nDone! CSV Log: $csvLog" -ForegroundColor Cyan
remove-item $global:lastTarget -r -Force
