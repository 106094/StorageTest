# autopilot_test.ps1

$SqlInstance  = "localhost\TPCC"
$DbName       = "tpcc"
$MdfName      = "tpcc.mdf"
$LdfName      = "tpcc_log.ldf"
$HammerDBHome = "C:\Program Files\HammerDB-4.8"
$TclScript    = "./scripts/tcl/mssqls/tprocc/mssqls_tprocc_run_vu.tcl"
$LogStamp     = Get-Date -Format "yyyyMMdd_HHmmss"
$OurLog       = "$env:USERPROFILE\Desktop\autopilot_${LogStamp}.log"
$HammerLog    = "$env:TEMP\hammerdb.log"

# ── Functions — ALL defined at top before any code runs ──────────────────────

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp][$Level] $Message"
    Write-Host $line
    Add-Content -Path $OurLog -Value $line
}

function Get-TestTiming {
    param([int]$VU)
    if     ($VU -le 5)   { return @{ Rampup = 1; Duration = 3;  SleepSec = 300  } }
    elseif ($VU -le 20)  { return @{ Rampup = 1; Duration = 5;  SleepSec = 420  } }
    elseif ($VU -le 50)  { return @{ Rampup = 2; Duration = 5;  SleepSec = 480  } }
    elseif ($VU -le 100) { return @{ Rampup = 2; Duration = 8;  SleepSec = 660  } }
    else                 { return @{ Rampup = 2; Duration = 10; SleepSec = 780  } }
}

function Run-HammerDB {
    param([int]$VU)

    $timing = Get-TestTiming -VU $VU

    $env:VU_COUNT    = "$VU"
    $env:VU_RAMPUP   = "$($timing.Rampup)"
    $env:VU_DURATION = "$($timing.Duration)"

    Write-Log "Rampup: $($timing.Rampup) min  |  Duration: $($timing.Duration) min  |  Sleep after: $([math]::Round($timing.SleepSec/60,1)) min"
    Write-Log "--- HammerDB output start VU $VU ---"

    Push-Location "$HammerDBHome"

    cmd /c "`"$HammerDBHome\hammerdbcli.bat`" auto $TclScript" 2>&1 |
        ForEach-Object {
            $_ | Add-Content -Path $OurLog
            Write-Host $_
        }

    $exit = $LASTEXITCODE
    Pop-Location

    Write-Log "--- HammerDB output end VU $VU --- Exit: $exit"
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

} else {

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

# ── Step 2: Run HammerDB test ─────────────────────────────────────────────────
$VUList     = @(1,5,10,15)
$totalSteps = $VUList.Count
$stepDone   = 0
$grandStart = Get-Date

Write-Log "========================================================"
Write-Log "HammerDB TEST RUN Started"
Write-Log "TCL Script  : $TclScript"
Write-Log "Our Log     : $OurLog"
Write-Log "Hammer Log  : $HammerLog"
Write-Log "VU List     : $($VUList -join ', ')"
Write-Log "Total Steps : $totalSteps"
Write-Log "========================================================"

foreach ($vu in $VUList) {

    $stepDone++
    Write-Log "--------------------------------------------------------"
    Write-Log "Step $stepDone / $totalSteps  |  VU = $vu"
    Write-Log "--------------------------------------------------------"

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
Write-Log "========================================================"
Write-Log "All steps complete. Total elapsed : $($totalElapsed.ToString('hh\:mm\:ss'))"
Write-Log "========================================================"