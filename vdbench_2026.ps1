Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass -Force
$root="$PSScriptRoot/vdbench50407_2"
set-location $root
$transcriptPath = Join-Path $PSScriptRoot "log$(get-date -format "_yyMMdd-HHmm").txt"
Start-Transcript -Path $transcriptPath -Append
$loop=5
$fills=@("25","100")
foreach($fill in $fills){
fio.exe --filename=\\.\PhysicalDrive1 --direct=1 --rw=write --bs=128k --iodepth=32 --randrepeat=0 --thread --name=128k_writefull --numjobs=1 --description="128k_writefull" --group_reporting "--size=$($fill)%" --output="write$($fill)%.txt"
$datetime=get-date -format "_yyMMdd-HHmm"
$resultfmain=(join-path $root "Fill$($fill)-Result$($datetime)" ).ToString()
new-item -ItemType Directory -path $resultfmain|Out-Null
foreach($i in (1..$loop)){
Write-Host "  > Starting Loop: $i" -ForegroundColor Yellow
$oldfolders=Get-ChildItem $root -Directory | Where-Object{$_.name -like "*thread*"}
if($oldfolders){
    $timestamp = Get-Date -Format "HHmm_ss"
    $backupfolder = New-Item -ItemType Directory -Path (Join-Path $root "_Backups_$timestamp") -Force
    Move-Item $oldfolders.FullName -Destination $backupfolder.FullName -ErrorAction SilentlyContinue
}
    Write-Host "  > Starting Random_Read_4k_128_thread Test (Loop: $i)" -ForegroundColor Green
    & "./Maxio_MultiDrive_define_RR4K.cmd" 1 128 max Random_Read_4k_128_thread
    Start-Sleep -Seconds 20
    Write-Host "  > Starting Random_Write_4k_64_thread Test (Loop: $i)" -ForegroundColor Green
    & "./Maxio_MultiDrive_define_RW4K.cmd" 1 64 max Random_Write_4k_64_thread
    Start-Sleep -Seconds 20
    Write-Host "  > Starting Sequential_Read_64k_16_thread Test (Loop: $i)" -ForegroundColor Green
    & "./Maxio_MultiDrive_define_SR64K.cmd" 1 16 max Sequential_Read_64k_16_thread
    Start-Sleep -Seconds 20
    Write-Host "  > Starting Sequential_Write_64k_8_thread (Loop: $i)" -ForegroundColor Green
    & "./Maxio_MultiDrive_define_SW64K.cmd" 1 8 max Sequential_Write_64k_8_thread
    Start-Sleep -Seconds 20

$resultfolders = Get-ChildItem $root -Directory | Where-Object { $_.Name -like "*thread*"}
if ($resultfolders) {       
    $loopfolder = Join-Path $resultfmain "loop$($i)"
    New-Item -ItemType Directory -Path $loopfolder -Force | Out-Null
    Move-Item $resultfolders.FullName -Destination $loopfolder
}
}

}
Stop-Transcript

# Load the assembly for the popup
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.MessageBox]::Show("The VDBench test has completed successfully.", "Test Finished", "OK", "Information")

