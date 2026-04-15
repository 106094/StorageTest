# 1. Input Source
# Load the required Windows Forms assembly
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass -Force;
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

 $global:lastTarget=@()
# Setup CSV Logging
$timestamp = Get-Date -Format "yyyyMMdd_HHmm"
$csvLog = Join-Path $PSScriptRoot "copying_$timestamp.csv"
"Metric,Result" | Out-File -FilePath $csvLog -Encoding utf8

function clean-recycle($top){
 $recyclebin=join-path $top "@Recycle"
 if((test-path $recyclebin) -and (Get-ChildItem $recyclebin\*)){
  Write-host "Purging NAS Recycle Bin..."
  try{
  rm $recyclebin\* -Recurse -Force}
  catch{
  $null
  }
  start-sleep -s 2
  while (Get-ChildItem $recyclebin\*){
    remove-item $recyclebin\* -Recurse -Force
    start-sleep -s 2
     }
   Write-host "completed" -NoNewline
  }
}


function Run-Transfer ($src, $dstBase, $type) {
    Write-Host "`n--- Testing $mode Speed (5 Loops) ---" -ForegroundColor Yellow
    $srcFiles = Get-ChildItem $src -Recurse -File
    $totalSize = ($srcFiles | Measure-Object -Property Length -Sum).Sum / 1MB
    $srcCount = $srcFiles.Count

    # Calculate size for speed (MB)
    $files = Get-ChildItem $src -Recurse -File
    $totalSize = ($files | Measure-Object -Property Length -Sum).Sum / 1MB
    
    for ($i=1; $i -le 5; $i++) {
        $targetDir = Join-Path $dstBase "copyfiles_$(Get-Date -Format 'HHmmss')"
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        
        $start = Get-Date
        Copy-Item -Path "$src\*" -Destination $targetDir -Recurse -Force
        $end = Get-Date
        
        $sampleFile = ($srcFiles | Select-Object -First 1).fullname
        $targetFilePath = $sampleFile.Replace($src,$targetDir)
        $dstCount = (Get-ChildItem $targetDir -Recurse -File).Count
        
        $srcHash = (Get-FileHash $sampleFile).Hash
        $dstHash = (Get-FileHash $targetFilePath).Hash

        if ($srcHash -eq $dstHash -and $srcCount -eq $dstCount) {
            $status = "Verified"
        } else {
            $status = "FAILED"
        }

        $sec = [math]::Round(($end - $start).TotalSeconds, 2)
        if ($sec -eq 0) { $sec = 0.01 } # Prevent divide by zero
        $speed = [math]::Round($totalSize / $sec, 2)

        
        # Save to CSV exactly as requested
        "time ($type $i),$sec s" | Out-File -FilePath $csvLog -Append -Encoding utf8
        "speed ($type $i),$speed MB/s" | Out-File -FilePath $csvLog -Append -Encoding utf8
        
        Write-Host "$type Loop $($i): $sec s | $speed MB/s | Result: $status"
        
        # 9. Delete unless it's the last loop
        if ($i -lt 5) { 
            Remove-Item $targetDir -Recurse -Force
            if($type -eq "Write"){
            clean-recycle -top $dstBase
            }

        } else { 
            $global:lastTarget+= $targetDir 
        }
    }
}

# Run Forward
Write-Host "`n--- Starting Forward Transfer ---" -ForegroundColor Green
Run-Transfer $source $destDisk "Write"

# Run Reverse (10. Loop 5 times from Destination back to Source)
Write-Host "`n--- Starting Reverse Transfer ---" -ForegroundColor Yellow
$readdest=split-path $source
Run-Transfer $global:lastTarget[0] $readdest "Read"

$global:lastTarget|ForEach-Object{
remove-item $_ -r -Force
}

clean-recycle -top $destDisk
 
Write-Host "`nDone! CSV Log: $csvLog" -ForegroundColor Cyan
[System.Media.SystemSounds]::Beep.Play()
Pause
