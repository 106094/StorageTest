# autopilot_test.ps1
Add-Type -AssemblyName System.Windows.Forms
#region ── iSCSI Connection Setup ────────────────────────────────────────────────────

function Connect-IscsiNAS {
    param([string]$TargetIP, [string]$TargetIQN)

    Write-Host ""
    Write-Host "Connecting to : $TargetIQN" -ForegroundColor Cyan
    Write-Host "Portal        : $TargetIP"  -ForegroundColor Cyan

    Connect-IscsiTarget `
        -NodeAddress         $TargetIQN `
        -TargetPortalAddress $TargetIP `
        -IsPersistent        $true

    Start-Sleep -Seconds 1

    $startTime = Get-Date
    $state     = $false

    while (-not $state) {
        $timepass = (New-TimeSpan -Start $startTime -End (Get-Date)).TotalSeconds

        if ($timepass -gt 30) {
            Write-Host ""
            Write-Host "ERROR: iSCSI target did not connect within 30 seconds." -ForegroundColor Red
            Write-Host "Target : $TargetIQN" -ForegroundColor Red
            Write-Host "Portal : $TargetIP"  -ForegroundColor Red
            Write-Host "Please check NAS availability and iSCSI configuration." -ForegroundColor Yellow
            exit 1
        }

        Start-Sleep -Seconds 1
        $state = (Get-IscsiTarget |
            Where-Object { $_.NodeAddress -eq $TargetIQN }
        ).IsConnected

        Write-Host "Waiting... $([math]::Round($timepass))s / 30s"
    }

    Write-Host "Connected successfully." -ForegroundColor Green
}

function Select-IscsiTarget {
    param([string]$TargetIP)

    # Discover targets on given IP
    Write-Host "Discovering targets on $TargetIP ..." -ForegroundColor Cyan
    New-IscsiTargetPortal -TargetPortalAddress $TargetIP -ErrorAction SilentlyContinue | Out-Null
    Start-Sleep -Seconds 2

    # Get all targets on this portal
    $targets = Get-IscsiTarget | Where-Object { $_.NodeAddress -ne $null }

    if (-not $targets) {
        Write-Host "ERROR: No iSCSI targets found on $TargetIP" -ForegroundColor Red
        exit 1
    }

    # ── List targets for user to select ──────────────────────────────────
    Write-Host ""
    Write-Host "Available iSCSI targets on $TargetIP :"
    Write-Host ""

    $index      = 1
    $targetList = @()
    foreach ($t in $targets) {
        $status = if ($t.IsConnected) { "[Connected]" } else { "[Not Connected]" }
        Write-Host "  $index. $($t.NodeAddress) $status"
        $targetList += $t
        $index++
    }

    Write-Host ""
    $selection = Read-Host "Enter number to select target"

    if ($selection -notmatch '^\d+$' -or
        [int]$selection -lt 1 -or
        [int]$selection -gt $targetList.Count) {
        Write-Host "ERROR: Invalid selection." -ForegroundColor Red
        exit 1
    }

    return $targetList[[int]$selection - 1].NodeAddress
}

# ── Step 1: Check existing iSCSI connections ──────────────────────────────────
Write-Host ""
Write-Host "========================================================"
Write-Host "iSCSI Connection Check"
Write-Host "========================================================"

$connectedTargets = Get-IscsiSession | Where-Object { $_.IsConnected -eq $true }

if ($connectedTargets) {
    Write-Host ""
    Write-Host "Currently connected iSCSI targets:"
    Write-Host ""
    $index = 1
    foreach ($s in $connectedTargets) {
        Write-Host "  $index. $($s.TargetNodeAddress)"
        $index++
    }
    Write-Host ""
    $confirm = Read-Host "Is this the correct iSCSI target for this test? (Y/N)"
    if ($confirm -eq "Y") {
        Write-Host "Using existing iSCSI connection." -ForegroundColor Green
    } else {
        Write-Host ""
        $TargetIP  = Read-Host "Enter iSCSI NAS IP address"
        $TargetIQN = Select-IscsiTarget -TargetIP $TargetIP
        Connect-IscsiNAS -TargetIP $TargetIP -TargetIQN $TargetIQN
    }
} else {
    Write-Host ""
    Write-Host "No iSCSI targets currently connected."
    $TargetIP  = Read-Host "Enter iSCSI NAS IP address"
    $TargetIQN = Select-IscsiTarget -TargetIP $TargetIP
    Connect-IscsiNAS -TargetIP $TargetIP -TargetIQN $TargetIQN
}

Write-Host ""
Write-Host "iSCSI setup complete." -ForegroundColor Green
Write-Host "========================================================"

#endregion

#region ── set iSCSI disk online and writable then assign letter D
$offlineDisks = Get-Disk | Where-Object { 
    $_.IsOffline -eq $true -and 
    $_.IsReadOnly -eq $true 
}

if ($offlineDisks.Count -eq 0) {
    Write-Host "WARNING: No offline/readonly disks found — iSCSI disk may already be online." -ForegroundColor Yellow
    exit 1
}

if ($offlineDisks.Count -gt 1) {
    Write-Host "WARNING: Multiple offline/readonly disks found — cannot determine which is iSCSI." -ForegroundColor Yellow
    Write-Host ""
    $offlineDisks | Select-Object Number, FriendlyName, OperationalStatus, IsOffline, IsReadOnly,
        @{N='Size_GB';E={[math]::Round($_.Size/1GB,1)}}, PartitionStyle |
        Format-Table -AutoSize
    Write-Host "Please bring the correct disk online manually and re-run." -ForegroundColor Yellow
    exit 1
}

# Exactly one offline+readonly disk found
$iSCSIDisk  = $offlineDisks[0]
$diskNumber = $iSCSIDisk.Number

Write-Host "Found iSCSI disk : $($iSCSIDisk.FriendlyName)  (Disk $diskNumber)" -ForegroundColor Cyan
Write-Host "Size             : $([math]::Round($iSCSIDisk.Size/1GB,1)) GB"      -ForegroundColor Cyan

Set-Disk -Number $diskNumber -IsOffline $false
Set-Disk -Number $diskNumber -IsReadOnly $false
Write-Host "Disk $diskNumber is now online and writable." -ForegroundColor Green

Update-Disk -Number $diskNumber
Start-Sleep -Seconds 2

$disk = Get-Disk -Number $diskNumber
Write-Host "Disk $diskNumber state : PartitionStyle=$($disk.PartitionStyle)  OperationalStatus=$($disk.OperationalStatus)" -ForegroundColor Cyan

# ── Initialize if RAW ─────────────────────────────────────────────────────────
if ($disk.PartitionStyle -eq "RAW") {
    Write-Host "Disk is uninitialized — initializing with GPT..." -ForegroundColor Yellow
    Initialize-Disk -Number $diskNumber -PartitionStyle GPT
    Start-Sleep -Seconds 2
    Write-Host "Disk initialized." -ForegroundColor Green
} else {
    Write-Host "Disk already initialized ($($disk.PartitionStyle)) — skipping initialize." -ForegroundColor Green
}

# ── Check if data partition already exists ────────────────────────────────────
$partition = Get-Partition -DiskNumber $diskNumber -ErrorAction SilentlyContinue |
    Where-Object { $_.Type -ne "Reserved" }
if (-not $partition) {
    Write-Host "Creating data partition..." -ForegroundColor Cyan
    $partition = New-Partition -DiskNumber $diskNumber -UseMaximumSize
    Start-Sleep -Seconds 2
    Write-Host "Partition created." -ForegroundColor Green
} else {
    Write-Host "Data partition already exists — skipping." -ForegroundColor Green
}

# ── Check if formatted ────────────────────────────────────────────────────────
$volume = Get-Volume | Where-Object { $_.Path -like "*$($partition.Guid)*" } 2>$null
if (-not $volume -or $volume.FileSystem -eq "" -or $volume.FileSystem -eq $null) {
    Write-Host "Formatting as NTFS..." -ForegroundColor Cyan
    Format-Volume -Partition $partition `
       -FileSystem NTFS -NewFileSystemLabel "iSCSI_DATA" -Confirm:$false | Out-Null
    Start-Sleep -Seconds 2
    Write-Host "Formatted." -ForegroundColor Green
} else {
    Write-Host "Filesystem already exists ($($volume.FileSystem)) — skipping format." -ForegroundColor Green
}

# ── Assign drive letter D to iSCSI disk ──────────────────────────────────────
$partition = Get-Partition -DiskNumber $diskNumber |
    Where-Object { $_.Type -ne "Reserved" }

# ── Assign drive letter D ─────────────────────────────────────────────────────
if ($partition.DriveLetter -eq "D") {
    Write-Host "Drive letter D already assigned — skipping." -ForegroundColor Green
}
else {
$usedLetters = (Get-Volume | Where-Object { $_.DriveLetter }).DriveLetter

if ("D" -in $usedLetters) {
    Write-Host "Drive letter D is occupied — reassigning existing D to another letter..." -ForegroundColor Yellow

    # Find next available letter (skip A,B,C,D)
    $allLetters = 'E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z'
    $nextLetter = $allLetters | Where-Object { $_ -notin $usedLetters } | Select-Object -First 1

    if (-not $nextLetter) {
        Write-Host "ERROR: No available drive letters to reassign D." -ForegroundColor Red
        exit 1
    }

    $existingD = Get-Partition | Where-Object { $_.DriveLetter -eq "D" }
    Set-Partition -DiskNumber $existingD.DiskNumber `
                  -PartitionNumber $existingD.PartitionNumber `
                  -NewDriveLetter $nextLetter

    Write-Host "Existing D reassigned to ${nextLetter}:\" -ForegroundColor Yellow
}

Set-Partition -DiskNumber $diskNumber `
              -PartitionNumber $partition.PartitionNumber `
              -NewDriveLetter "D"

Write-Host "iSCSI disk assigned to D:\" -ForegroundColor Green
}
# ── Verify ────────────────────────────────────────────────────────────────────
Get-Volume -DriveLetter "D" | 
    Select-Object DriveLetter, FileSystem, FileSystemLabel, HealthStatus,
        @{N='Size_GB';E={[math]::Round($_.Size/1GB,1)}} |
    Format-Table -AutoSize

#endregion

#region copy DB


#endregion

#region HammerDB Testing
$SqlInstance  = "localhost\TPCC"
$DbName       = "tpcc"
$MdfName      = "tpcc.mdf"
$LdfName      = "tpcc_log.ldf"
$HammerDBHome = "C:\Program Files\HammerDB-4.8"
$TclScript    = "./scripts/tcl/mssqls/tprocc/mssqls_tprocc_run_vu.tcl"
$LogStamp     = Get-Date -Format "yyyyMMdd_HHmmss"
$OurLog       = "$env:USERPROFILE\Desktop\hammerdb_${LogStamp}.log"

# ── Functions — ALL defined at top before any code runs ──────────────────────

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts   = (Get-Date -Format "ddd MMM dd HH:mm:ss zzz yyyy") -replace "\+08:00","+0800"
    $line = "Hammerdb Log @ $ts`nAutopilot [$Level] $Message"
    Write-Host $line
    Add-Content -Path $OurLog -Value $line
}

function Write-Plain {
    param([string]$Message)
    Write-Host $Message
    Add-Content -Path $OurLog -Value $Message
}

function Write-HammerLine {
    param([string]$Line)
    Write-Host $Line
    Add-Content -Path $OurLog    -Value $Line
    Add-Content -Path $HammerLog -Value $Line
}

function Get-TestTiming {
    param([int]$VU)
    $multiplier = if ($global:HDD) { 2 } else { 1 }
    if     ($VU -le 5)   { return @{ Rampup = 1; Duration = 3;  SleepSec = 300 * $multiplier } }
    elseif ($VU -le 20)  { return @{ Rampup = 1; Duration = 5;  SleepSec = 420 * $multiplier } }
    elseif ($VU -le 50)  { return @{ Rampup = 2; Duration = 5;  SleepSec = 480 * $multiplier } }
    elseif ($VU -le 100) { return @{ Rampup = 2; Duration = 8;  SleepSec = 660 * $multiplier } }
    else                 { return @{ Rampup = 2; Duration = 10; SleepSec = 780 * $multiplier } }
}

function Run-HammerDB {
    param([int]$VU)

    $timing = Get-TestTiming -VU $VU

    $env:VU_COUNT    = "$VU"
    $env:VU_RAMPUP   = "$($timing.Rampup)"
    $env:VU_DURATION = "$($timing.Duration)"

    Write-Log  "Rampup: $($timing.Rampup) min  |  Duration: $($timing.Duration) min  |  Sleep after: $([math]::Round($timing.SleepSec/60,1)) min"
    Write-Plain "--- HammerDB output start VU $VU ---"

    Push-Location $HammerDBHome

    cmd /c "`"$HammerDBHome\hammerdbcli.bat`" auto $TclScript" 2>&1 |
        ForEach-Object {
            Write-HammerLine $_
        }

    $exit = $LASTEXITCODE
    Pop-Location

    Write-Plain "--- HammerDB output end VU $VU ---"
    return @{ ExitCode = $exit; SleepSec = $timing.SleepSec }
}


# ── Step 1: Check if tpcc database exists ────────────────────────────────────
Write-Log "Checking if database '$DbName' exists on $SqlInstance..."

$dbExists = sqlcmd -S $SqlInstance -E -Q "
SET NOCOUNT ON
SELECT COUNT(*) FROM sys.databases WHERE name = '$DbName'" 2>&1 |
    Where-Object { $_ -match '^\s*\d+\s*$' } |
    ForEach-Object { $_.Trim() }

if ($dbExists -eq "1") {
    Write-Log "Database '$DbName' already exists." "INFO"

    $whCount = sqlcmd -S $SqlInstance -E -Q "
    SET NOCOUNT ON
    SELECT COUNT(*) FROM $DbName.dbo.warehouse" 2>&1 |
        Where-Object { $_ -match '^\s*\d+\s*$' } |
        ForEach-Object { $_.Trim() }

    Write-Log "Warehouse count : $whCount" "INFO"

} 
else {

    Write-Log "Database '$DbName' not found — searching for $MdfName..." "WARN"

    $drives = Get-PSDrive -PSProvider FileSystem |
        Where-Object { $_.Root -match '^[A-Z]:\\$' } |
        Select-Object -ExpandProperty Name

    Write-Log "Searching drives: $($drives -join ', ')"

    $mdfPath = $null
    $ldfPath = $null

    foreach ($drive in $drives) {
        $candidate = "${drive}:\DATA\$MdfName"
        Write-Log "Checking $candidate ..."
        if (Test-Path $candidate) {
            $mdfPath = $candidate
            Write-Log "Found: $mdfPath" "INFO"
            $ldfCandidate = "${drive}:\DATA\$LdfName"
            if (Test-Path $ldfCandidate) {
                $ldfPath = $ldfCandidate
                Write-Log "Found log file: $ldfPath" "INFO"
            } else {
                Write-Log "Log file not found — will rebuild log" "WARN"
            }
            break
        }
    }

    if (-not $mdfPath) {
        Write-Log "ERROR: $MdfName not found in any \DATA folder." "ERROR"
        Write-Log "Please copy tpcc.mdf to a \DATA folder on any drive." "ERROR"
        exit 1
    }

    if ($ldfPath) {
        $attachSql = "
CREATE DATABASE [$DbName] ON
    (FILENAME = '$mdfPath')
LOG ON
    (FILENAME = '$ldfPath')
FOR ATTACH"
    } else {
        $attachSql = "
CREATE DATABASE [$DbName] ON
    (FILENAME = '$mdfPath')
FOR ATTACH_REBUILD_LOG"
    }

    Write-Log "Attaching '$DbName' from $mdfPath ..."
    $attachResult = sqlcmd -S $SqlInstance -E -Q $attachSql 2>&1
    if ($attachResult -match "Error|error|failed|Failed") {
        Write-Log "Attach failed: $attachResult" "ERROR"
        exit 1
    }

    $state = sqlcmd -S $SqlInstance -E -Q "
    SET NOCOUNT ON
    SELECT state_desc FROM sys.databases WHERE name = '$DbName'" 2>&1 |
        Where-Object { $_ -match '[A-Z]' -and $_ -notmatch 'state_desc|---' } |
        ForEach-Object { $_.Trim() }

    if ($state -ne "ONLINE") {
        Write-Log "Database state is '$state' — attach failed." "ERROR"
        exit 1
    }

    $whCount = sqlcmd -S $SqlInstance -E -Q "
    SET NOCOUNT ON
    SELECT COUNT(*) FROM $DbName.dbo.warehouse" 2>&1 |
        Where-Object { $_ -match '^\s*\d+\s*$' } |
        ForEach-Object { $_.Trim() }

    Write-Log "Database '$DbName' attached and ONLINE" "INFO"
    Write-Log "Warehouse count : $whCount" "INFO"
}

# ── Step 2: choose NAS disk type  ─────────────────────────────────────────────────
Write-Host ""
Write-Host "Select storage type for timing adjustment:"
Write-Host "  1. SSD"
Write-Host "  2. HDD"
Write-Host ""

$diskChoice = Read-Host "Enter 1 or 2"

$VUList     = @(1, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 60, 70, 80, 90, 100, 120, 140, 160, 180, 200, 225, 250)

switch ($diskChoice) {
    "1" {
        $global:HDD = $false
        Write-Log "Storage type : SSD — standard timing, single pass" "INFO"
    }
    "2" {
        $global:HDD = $true
        $VUList     = $VUList + $VUList
        Write-Log "Storage type : HDD — 2x intervals, full sequence run twice" "INFO"
        Write-Host ""
        Write-Host "WARNING: HDD mode — 46 steps, estimated ~24 hours." -ForegroundColor Yellow
        Write-Host ""
        $confirm = Read-Host "Continue? (Y/N)"
        if ($confirm -ne "Y") {
            Write-Log "User cancelled." "WARN"
            exit 0
        }
    }
    default {
        $global:HDD = $false
        Write-Log "Invalid selection '$diskChoice' — defaulting to SSD" "WARN"
    }
}
# ── Step 3: Run HammerDB test ─────────────────────────────────────────────────

$totalSteps = $VUList.Count
$stepDone   = 0
$grandStart = Get-Date

Write-Plain "========================================================"
Write-Log   "HammerDB TEST RUN Started"
Write-Plain "TCL Script    : $TclScript"
Write-Plain "Our Log       : $OurLog"
Write-Plain "VU List       : $($VUList -join ', ')"
Write-Plain "Total Steps   : $totalSteps"
Write-Plain "Storage Type  : $(if ($global:HDD) { 'HDD (2x sleep intervals)' } else { 'SSD (standard intervals)' })"
Write-Plain "========================================================"

foreach ($vu in $VUList) {

    $stepDone++
    Write-Plain "+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-"
    Write-Log   "Step $stepDone / $totalSteps  |  VU = $vu"
    Write-Plain "+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-"

    $stepStart = Get-Date
    $result    = Run-HammerDB -VU $vu
    $elapsed   = (Get-Date) - $stepStart

    Write-Log "VU $vu done. Exit: $($result.ExitCode)  |  Elapsed: $($elapsed.ToString('hh\:mm\:ss'))"

    if ($result.ExitCode -ne 0) {
        Write-Log "ERROR: Non-zero exit at VU $vu — stopping." "ERROR"
        exit 1
    }

    $isLastStep = ($stepDone -eq $totalSteps)
    if (-not $isLastStep) {
        $waitMin = [math]::Round($result.SleepSec / 60, 1)
        Write-Log "Sleeping $waitMin min before next step..."
        Start-Sleep -Seconds $result.SleepSec
    }
}

$totalElapsed = (Get-Date) - $grandStart
Write-Plain "+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-"
Write-Log   "All steps complete. Total elapsed : $($totalElapsed.ToString('hh\:mm\:ss'))"
Write-Plain "+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-"

#endregion

# ── Popup completion message ──────────────────────────────────────────────────
$completedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
[System.Windows.Forms.MessageBox]::Show(
    "All HammerDB tests completed successfully.`n`nCompleted at : $completedAt`nTotal elapsed : $($totalElapsed.ToString('hh\:mm\:ss'))",
    "Test Completed",
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information
)
