Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass -Force
Add-Type -AssemblyName System.Windows.Forms
$transcriptPath = Join-Path $PSScriptRoot "log$(get-date -format "_yyMMdd-HHmm").txt"
Start-Transcript -Path $transcriptPath -Append
$TargetDiskNumber = 1
try {
$disk = Get-Disk -Number $TargetDiskNumber -ErrorAction Stop
Write-Host "Checking Disk $TargetDiskNumber ($($disk.Model))..." -ForegroundColor Cyan
Write-Host "Disk 1 type is: $drivetype" -ForegroundColor Cyan
if ($disk.BusType -eq "USB" -or $disk.BusType -eq "SD") {
 [System.Windows.Forms.MessageBox]::Show("CRITICAL ERROR: Disk $TargetDiskNumber is a removable device ($($disk.BusType)). Script aborted to prevent data loss.", "Safety Block", "OK", "Error")
exit
}
Write-Host "Preparing disk attributes..." -ForegroundColor Yellow
$disk | Set-Disk -IsOffline $False
$disk | Set-Disk -IsReadonly $False
$disk | Set-Disk -IsOffline $True
#final check
$finalState = Get-Disk -Number $TargetDiskNumber
    Write-Host "`n--- Disk $($TargetDiskNumber) Status Report ---"
    Write-Host "Model: $($finalState.Model)"
    Write-Host "Operational Status: $($finalState.OperationalStatus)" # Should be Offline
    Write-Host "Read-Only: $($finalState.IsReadOnly)"              # Should be False
    Write-Host "--------------------------"

    if ($finalState.OperationalStatus -eq "Offline" -and $finalState.IsReadOnly -eq $False) {
        Write-Host "SUCCESS: Disk $TargetDiskNumber is ready for VDBench." -ForegroundColor Green
    } else {
        Write-Host "FAILURE: Disk states are not correct. Please check manually." -ForegroundColor Red
    }

} 
catch {
    [System.Windows.Forms.MessageBox]::Show("Error: Disk $TargetDiskNumber not found or Access Denied. Make sure to run as Administrator.", "Error", "OK", "HandledError")
    exit
}
 
#region get ready fio tool
if (-not (Get-Command fio -ErrorAction SilentlyContinue)) {
    Write-Host "fio not found. Starting quiet installation..." -ForegroundColor Yellow    
    $installerPath = Join-Path $PSScriptRoot "fio-3.42-x64.msi"   
    if (Test-Path $installerPath) {
        Start-Process -FilePath $installerPath -ArgumentList "/quiet" -Wait
        $fioDefaultPath = "C:\Program Files\fio"
        if (Test-Path $fioDefaultPath) {
            $env:Path += ";$fioDefaultPath"
            Write-Host "fio installed and added to session path." -ForegroundColor Green
        }
        $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($currentPath -notlike "*$fioDefaultPath*") {
            [Environment]::SetEnvironmentVariable("Path", $currentPath + ";$fioDefaultPath", "User")
            Write-Host "fio added to permanent User Environment Path." -ForegroundColor Cyan
        }
        #double check fio ready
        if (-not (Get-Command fio -ErrorAction SilentlyContinue)) {
            Write-Host "ERROR: Installation finished but 'fio' is still not recognized." -ForegroundColor Red
            Write-Host "Please restart PowerShell or manually add '$fioDefaultPath' to your PATH." -ForegroundColor Red
            # Notify before quitting
            [System.Windows.Forms.MessageBox]::Show("fio installation failed or path not recognized. Script will exit.", "Critical Error", "OK", "Error")
            exit
          } 
          else {
            Write-Host "fio verified successfully!" -ForegroundColor Green
           }

    } 
    else{
        Write-Error "Installer not found at $installerPath. Please check the filename."
        exit
    }
}
#endregion
#region unzip vdbench folder
$vdpath=Get-ChildItem  -Directory "$PSScriptRoot\vdbench*"
if(!$vdpath){
$vdbenchzip=Get-ChildItem "$PSScriptRoot\vdbench*zip"
if($vdbenchzip){
Expand-Archive -Path $vdbenchzip.FullName -DestinationPath "$PSScriptRoot\VDbench50407" -Force
while(!$vdpath){
$vdpath=Get-ChildItem "$PSScriptRoot\vdbench*\vdbench.bat"
start-sleep -s 1
}
start-sleep -s 1
Write-Output "VDBench tool folder unzip completed"
}else{
[System.Windows.Forms.MessageBox]::Show("No VDBench tool zip file found, please check", "Test Finished", "OK", "Warning")
exit
}
}
#endregion

$root=(get-childitem -Directory "$PSScriptRoot/vdbench*").FullName
set-location $root
$loop=1
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

    & "./Maxio_MultiDrive_define_RR4K.cmd" 1 128 max Random_Read_4k_128_thread
    Start-Sleep -Seconds 20

    & "./Maxio_MultiDrive_define_RW4K.cmd" 1 64 max Random_Write_4k_64_thread
    Start-Sleep -Seconds 20

    & "./Maxio_MultiDrive_define_SR64K.cmd" 1 16 max Sequential_Read_64k_16_thread
    Start-Sleep -Seconds 20

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

[System.Windows.Forms.MessageBox]::Show("The VDBench test has completed successfully.", "Test Finished", "OK", "Information")

