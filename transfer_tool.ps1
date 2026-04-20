

# Load the required Windows Forms assembly
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass -Force;
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName PresentationFramework

# 1. Select Destination Disk from List
$disks = Get-PSDrive -PSProvider FileSystem | Where-Object {$_.Name -ne "C" -and $_.Free -ne $null }
Write-Host "`n--- Select Destination Disk (Input Number) ---" -ForegroundColor Cyan
for ($i=0; $i -lt $disks.Count; $i++) { 
    Write-Host "[$i] $($disks[$i].Name): ($($disks[$i].Root))" 
}
$choice = Read-Host "Enter number"
$destDisk = "$($disks[[int]$choice].Name):\"

# Create the Folder Browser Dialog object
$folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
$folderBrowser.Description = "Select the source folder to transfer"
$folderBrowser.ShowNewFolderButton = $false

$title = "Confirmation"
$message = "Any other folder need to be executed?"
$buttons = [System.Windows.MessageBoxButton]::YesNoCancel
$icon = [System.Windows.MessageBoxImage]::Question

$sources=@()
Write-Host "`n--- Select Source folder ---" -ForegroundColor Cyan
while($true){
    $dialogResult = $folderBrowser.ShowDialog()
    if($dialogResult -eq "OK"){
        $sources += $folderBrowser.SelectedPath
        $response = [System.Windows.MessageBox]::Show($message, $title, $buttons, $icon)
        if($response -eq "No") { break } # Stop asking and start testing
        if($response -eq "Cancel") { exit } # Kill script
    } else {
        exit # User clicked Cancel/X on folder browser
    }
}

function clean-recycle($top){
 
 $recyclebin=(get-childitem $top -Directory -filter "*Recycle*").fullname
 if((test-path $recyclebin) -and (Get-ChildItem $recyclebin\*)){
  Write-host "Purging NAS Recycle Bin..." -NoNewline
  try{
  rm $recyclebin\* -Recurse -Force}
  catch{
  $null
  }
  start-sleep -s 2
  while (Get-ChildItem $recyclebin\*){
    remove-item $recyclebin\* -Recurse -Force -ErrorAction SilentlyContinue
    start-sleep -s 2
     }
   Write-host "completed"
  }
}

function Run-Transfer ($src, $dstBase, $type, $sourcename) {
    Write-Host "--- ($($sourcename)) $type Speed (5 Loops) ---" -ForegroundColor Yellow
    $srcFiles = Get-ChildItem $src -Recurse -File
    $totalSize = ($srcFiles | Measure-Object -Property Length -Sum).Sum / 1MB
    $srcCount = $srcFiles.Count

    # Calculate size for speed (MB)
    $files = Get-ChildItem $src -Recurse -File
    $totalSize = ($files | Measure-Object -Property Length -Sum).Sum / 1MB
    
    for ($i=1; $i -le 5; $i++) {
        $targetDir = Join-Path $dstBase "$($type)_$($i)_$(Get-Date -Format 'HHmmss')"
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        
        $start = Get-Date
        Copy-Item -Path "$src\*" -Destination $targetDir -Recurse -Force
        $end = Get-Date
        
        $sampleFile = ($srcFiles | Select-Object -First 1).fullname
        $targetFilePath = Join-Path $targetDir ($sampleFile.Substring($src.Length).TrimStart('\'))
        $dstCount = (Get-ChildItem -LiteralPath $targetDir -Recurse -File).Count
        
        $srcHash = (Get-FileHash -LiteralPath $sampleFile).Hash
        $dstHash = (Get-FileHash -LiteralPath $targetFilePath).Hash

        if ($srcHash -eq $dstHash -and $srcCount -eq $dstCount) {
            $status = "Verified"
        } else {
            $status = "FAILED"
        }

        $sec = [math]::Round(($end - $start).TotalSeconds, 2)
        if ($sec -eq 0) { $sec = 0.01 } # Prevent divide by zero
        $speed = [math]::Round($totalSize / $sec, 2)

        
        # Save to CSV exactly as requested
        "$sourcename,time ($type $i),$sec s" | Out-File -FilePath $csvLog -Append -Encoding utf8
        "$sourcename,speed ($type $i),$speed MB/s" | Out-File -FilePath $csvLog -Append -Encoding utf8
        
        Write-Host "$type Loop $($i): $sec s | $speed MB/s | Result: $status"
        
        # 9. Delete unless it's the last loop
        if ($i -lt 5) { 
            Remove-Item $targetDir -Recurse -Force -ErrorAction SilentlyContinue
            if($type -eq "Write"){
            clean-recycle -top $dstBase
            }

        } else { 
            $global:lastTarget += $targetDir
        }
    }
}

$global:lastTarget=@()
# Setup CSV Logging
$timestamp = Get-Date -Format "yyyyMMdd_HHmm"
$csvLog = Join-Path $PSScriptRoot "WriteReadLog_$timestamp.csv"
"Source,Metric,Result" | Out-File -FilePath $csvLog -Encoding utf8

foreach($source in $sources){

# Run Forward
$sourcename=(Get-item $source).Name
Write-Host "`n--- Starting Write Testing ---" -ForegroundColor Green
Run-Transfer -src $source -dstBase $destDisk -type "Write" -sourcename $sourcename

# Run Reverse (10. Loop 5 times from Destination back to Source)
Write-Host "`n--- Starting Read testing ---" -ForegroundColor Green
$readdest=split-path $source
Run-Transfer -src $global:lastTarget[-1]  -dstBase $readdest -type "Read" -sourcename $sourcename

$global:lastTarget|ForEach-Object{
remove-item $_ -r -Force -ErrorAction SilentlyContinue
}

clean-recycle -top $destDisk
 
}

Write-Host "`nDone! CSV Log: $csvLog" -ForegroundColor Cyan
[System.Media.SystemSounds]::Beep.Play()
Pause
