Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass -Force

$transcriptPath = Join-Path $PSScriptRoot "log-$(get-date -format "_yyMMdd-HHmm").txt"
Start-Transcript -Path $transcriptPath -Append

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
            Add-Type -AssemblyName System.Windows.Forms
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

start-sleep -s 600

$root=(get-childitem -Directory "$PSScriptRoot/vdbench*").FullName
set-location $root
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
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.MessageBox]::Show("The VDBench test has completed successfully.", "Test Finished", "OK", "Information")

