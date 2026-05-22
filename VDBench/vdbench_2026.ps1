Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass -Force
Add-Type -AssemblyName System.Windows.Forms
$transcriptPath = Join-Path $PSScriptRoot "log$(get-date -format "_yyMMdd-HHmm").txt"
Start-Transcript -Path $transcriptPath -Append
#region UI
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

[xml]$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="VDBench Settings"
    Width="420"
    Height="500"
    WindowStartupLocation="CenterScreen"
    ResizeMode="NoResize"
    Background="#1E1E2E">

    <Window.Resources>
        <!-- TextBox Style -->
        <Style x:Key="InputBox" TargetType="TextBox">
            <Setter Property="Background" Value="#2A2A3E"/>
            <Setter Property="Foreground" Value="#CDD6F4"/>
            <Setter Property="BorderBrush" Value="#45475A"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,5"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontFamily" Value="Consolas"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="Height" Value="32"/>
            <Setter Property="CaretBrush" Value="#89B4FA"/>
            <Style.Triggers>
                <Trigger Property="IsFocused" Value="True">
                    <Setter Property="BorderBrush" Value="#89B4FA"/>
                    <Setter Property="Background" Value="#313244"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Label Style -->
        <Style x:Key="FieldLabel" TargetType="TextBlock">
            <Setter Property="Foreground" Value="#A6ADC8"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontFamily" Value="Segoe UI"/>
            <Setter Property="Margin" Value="0,0,0,4"/>
        </Style>

        <!-- CheckBox Style -->
        <Style x:Key="ModernCheck" TargetType="CheckBox">
            <Setter Property="Foreground" Value="#CDD6F4"/>
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="FontFamily" Value="Consolas"/>
            <Setter Property="Margin" Value="0,4,0,4"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>

        <!-- Primary Button Style -->
        <Style x:Key="DoneBtn" TargetType="Button">
            <Setter Property="Background" Value="#89B4FA"/>
            <Setter Property="Foreground" Value="#1E1E2E"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontFamily" Value="Segoe UI"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="24,8"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                CornerRadius="6"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#B4CDFF"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="Background" Value="#6A9FEA"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Cancel Button Style -->
        <Style x:Key="CancelBtn" TargetType="Button">
            <Setter Property="Background" Value="#313244"/>
            <Setter Property="Foreground" Value="#CDD6F4"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontFamily" Value="Segoe UI"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="BorderBrush" Value="#45475A"/>
            <Setter Property="Padding" Value="24,8"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#45475A"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="Background" Value="#585B70"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid Margin="28,24,28,24">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="16"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="16"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="16"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Title -->
        <StackPanel Grid.Row="0">
            <TextBlock Text="VDBench Settings"
                       Foreground="#CDD6F4"
                       FontSize="20"
                       FontWeight="Bold"
                       FontFamily="Segoe UI"/>
            <Rectangle Height="1" Fill="#313244" Margin="0,10,0,0"/>
        </StackPanel>

        <!-- Loop -->
        <StackPanel Grid.Row="2">
            <TextBlock Text="Loop" Style="{StaticResource FieldLabel}"/>
            <TextBox x:Name="TxtLoop"
                     Text="1"
                     Style="{StaticResource InputBox}"
                     Width="120"
                     HorizontalAlignment="Left"
                     ToolTip="Number of loops to run"/>
        </StackPanel>

        <!-- Wait Time -->
        <StackPanel Grid.Row="4">
            <TextBlock Text="Wait Time (min) after FIO" Style="{StaticResource FieldLabel}"/>
            <TextBox x:Name="TxtWaitTime"
                     Text="240"
                     Style="{StaticResource InputBox}"
                     Width="120"
                     HorizontalAlignment="Left"
                     ToolTip="Wait time in minutes after FIO completes"/>
        </StackPanel>

        <!-- Checkboxes -->
        <StackPanel Grid.Row="6">
            <!-- Header Row with Text and Checkboxes side by side -->
            <Grid Margin="0,0,0,8">
                <TextBlock Text="Test Profiles" Style="{StaticResource FieldLabel}" HorizontalAlignment="Left" VerticalAlignment="Center"/>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                    <CheckBox x:Name="ChkFill25" Content="25%" Style="{StaticResource ModernCheck}" IsChecked="True" Margin="0,0,12,0"/>
                    <CheckBox x:Name="ChkFill100" Content="100%" Style="{StaticResource ModernCheck}" IsChecked="True" Margin="0,0,4,0"/>
                </StackPanel>
            </Grid>
            
            <Border Background="#2A2A3E" BorderBrush="#45475A" BorderThickness="1" CornerRadius="6" Padding="14,10">
                <StackPanel>
                    <CheckBox x:Name="ChkRR4k"   Content="Random_Read_4k_128"    Style="{StaticResource ModernCheck}" IsChecked="True"/>
                    <CheckBox x:Name="ChkRW4k"   Content="Random_Write_4k_64"    Style="{StaticResource ModernCheck}" IsChecked="True"/>
                    <CheckBox x:Name="ChkSR64k"  Content="Sequential_Read_64k_16" Style="{StaticResource ModernCheck}" IsChecked="True"/>
                    <CheckBox x:Name="ChkSW64k"  Content="Sequential_Write_64k_8" Style="{StaticResource ModernCheck}" IsChecked="True"/>
                </StackPanel>
            </Border>
        </StackPanel>

        <!-- Buttons -->
        <StackPanel Grid.Row="8" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="BtnCancel" Content="Cancel" Style="{StaticResource CancelBtn}" Margin="0,0,12,0"/>
            <Button x:Name="BtnDone" Content="Done" Style="{StaticResource DoneBtn}"/>
        </StackPanel>
    </Grid>
</Window>
"@

# ── Build Window ──────────────────────────────────────────────────────────────
$reader   = [System.Xml.XmlNodeReader]::new($xaml)
$window   = [Windows.Markup.XamlReader]::Load($reader)

$txtLoop      = $window.FindName("TxtLoop")
$txtWaitTime  = $window.FindName("TxtWaitTime")
$chkRR4k      = $window.FindName("ChkRR4k")
$chkRW4k      = $window.FindName("ChkRW4k")
$chkSR64k     = $window.FindName("ChkSR64k")
$chkSW64k     = $window.FindName("ChkSW64k")
$btnCancel    = $window.FindName("BtnCancel")
$btnDone      = $window.FindName("BtnDone")
$chkFill25 = $window.FindName("ChkFill25")
$chkFill100 = $window.FindName("ChkFill100")


# ── Numeric-only validation ───────────────────────────────────────────────────
$numericFilter = {
    param($sender, $e)
    $e.Handled = ($e.Text -notmatch '^\d$')
}
$txtLoop.Add_PreviewTextInput($numericFilter)
$txtWaitTime.Add_PreviewTextInput($numericFilter)

# Block paste of non-numeric content via TextChanged (strip non-digits after any change)
$numericSanitize = {
    param($sender, $e)
    $clean = $sender.Text -replace '\D', ''
    if ($sender.Text -ne $clean) {
        $caret = $sender.CaretIndex
        $sender.Text = $clean
        $sender.CaretIndex = [Math]::Min($caret, $clean.Length)
    }
}
$txtLoop.Add_TextChanged($numericSanitize)
$txtWaitTime.Add_TextChanged($numericSanitize)

# ── Result tracking ───────────────────────────────────────────────────────────
$script:Result = $null

# ── Cancel / X button ─────────────────────────────────────────────────────────
$btnCancel.Add_Click({ $window.Close() })
$window.Add_Closing({
    if ($null -eq $script:Result) {
        Write-Host "User cancelled. Exiting." -ForegroundColor Yellow
        # exit 0   # Uncomment to terminate the host process on cancel
    }
})

# ── Done button ───────────────────────────────────────────────────────────────
$btnDone.Add_Click({
    # Validate Loop
    $loopVal = $txtLoop.Text.Trim()
    if ($loopVal -eq '' -or -not ($loopVal -match '^\d+$')) {
        [System.Windows.MessageBox]::Show(
            "Loop must be a positive integer.",
            "Validation Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning)
        return
    }

    # Validate Wait Time
    $waitVal = $txtWaitTime.Text.Trim()
    if ($waitVal -eq '' -or -not ($waitVal -match '^\d+$')) {
        [System.Windows.MessageBox]::Show(
            "Wait Time must be a positive integer.",
            "Validation Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning)
        return
    }

    $fillsList = [System.Collections.Generic.List[string]]::new()
    
    if ($chkFill25.IsChecked -eq $true) { $fillsList.Add("25") }
    if ($chkFill100.IsChecked -eq $true) { $fillsList.Add("100") }
    
    # Store globally or script-scoped to use outside the form
    $fills = $fillsList.ToArray()
    # Collect selected profiles
    $profiles = @()
    if ($chkRR4k.IsChecked)  { $profiles += "Random_Read_4k_128" }
    if ($chkRW4k.IsChecked)  { $profiles += "Random_Write_4k_64" }
    if ($chkSR64k.IsChecked) { $profiles += "Sequential_Read_64k_16" }
    if ($chkSW64k.IsChecked) { $profiles += "Sequential_Write_64k_8" }

    if ($profiles.Count -eq 0) {
        [System.Windows.MessageBox]::Show(
            "Please select at least one test profile.",
            "Validation Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning)
        return
    }

    $script:Result = [PSCustomObject]@{
        Loop          = [int]$loopVal
        WaitTimeMin   = [int]$waitVal
        TestProfiles  = $profiles
        fillrate      = $fills

    }

    $window.Close()
})

# ── Show dialog ───────────────────────────────────────────────────────────────
$window.ShowDialog() | Out-Null

# ── Use result downstream ─────────────────────────────────────────────────────
if ($null -eq $script:Result -or $script:Result.TestProfiles.count -eq 0) {
    Write-Host "Cancelled — no settings returned." -ForegroundColor Yellow
    exit 0
}

Write-Host "`n=== VDBench Settings ===" -ForegroundColor Cyan
Write-Host "Loop         : $($script:Result.Loop)"
Write-Host "Wait Time    : $($script:Result.WaitTimeMin) min"
Write-Host "filled rate  : $($script:Result.fillrate -join ', ')"
Write-Host "Test Profiles: $($script:Result.TestProfiles -join ', ')"
Write-Host ""

# $script:Result is now ready for use in the rest of your script
#endregion


$TargetDiskNumber = 1
try {
$disk = Get-Disk -Number $TargetDiskNumber -ErrorAction Stop
$drivetype = $disk.BusType
Write-Host "Checking Disk $TargetDiskNumber ($($disk.Model))..." -ForegroundColor Cyan
Write-Host "Disk $TargetDiskNumber type is: $drivetype" -ForegroundColor Cyan
 if ($drivetype -eq "USB" -or $drivetype -eq "SD") {
        [System.Windows.Forms.MessageBox]::Show("CRITICAL ERROR: Disk $TargetDiskNumber is a removable device ($drivetype). Script aborted to prevent data loss.", "Safety Block", "OK", "Error")
        Stop-Transcript
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
     Stop-Transcript
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
         Stop-Transcript
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
 Stop-Transcript
exit
}
}
#endregion

$root=(get-childitem -Directory "$PSScriptRoot/vdbench*").FullName
set-location $root
$loop=$script:Result.Loop
$waittimes=[int32]$($script:Result.WaitTimeMin)*60

$fills=$script:Result.fillrate
foreach($fill in $fills){
fio.exe --filename=\\.\PhysicalDrive1 --direct=1 --rw=write --bs=128k --iodepth=32 --randrepeat=0 --thread --name=128k_writefull --numjobs=1 --description="128k_writefull" --group_reporting "--size=$($fill)%" --output="write$($fill)%.txt"
start-sleep -s $waittimes
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

   if($script:Result.TestProfiles -contains "Random_Read_4k_128"){
    & "./Maxio_MultiDrive_define_RR4K.cmd" 1 128 max Random_Read_4k_128_thread
    Start-Sleep -Seconds 20
    }

   if($script:Result.TestProfiles -contains "Random_Write_4k_64"){
    & "./Maxio_MultiDrive_define_RW4K.cmd" 1 64 max Random_Write_4k_64_thread
    Start-Sleep -Seconds 20
    }

   if($script:Result.TestProfiles -contains "Sequential_Read_64k_16"){
    & "./Maxio_MultiDrive_define_SR64K.cmd" 1 16 max Sequential_Read_64k_16_thread
    Start-Sleep -Seconds 20
    }

   if($script:Result.TestProfiles -contains "Sequential_Write_64k_8"){
    & "./Maxio_MultiDrive_define_SW64K.cmd" 1 8 max Sequential_Write_64k_8_thread
    Start-Sleep -Seconds 20
    }

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