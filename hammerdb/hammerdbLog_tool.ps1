Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# ── WPF dialog ──────────────────────────────────────────
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="HammerDB Log Parser"
        Width="480" Height="230"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize"
        FontFamily="Segoe UI" FontSize="13">
  <Grid Margin="20">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="12"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="16"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="20"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <TextBlock Grid.Row="0" Text="Select log folder" FontSize="12"
               Foreground="#666"/>

    <Grid Grid.Row="2">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="8"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <TextBox x:Name="txtPath" Grid.Column="0"
               Height="32" Padding="6,4"
               VerticalContentAlignment="Center"
               BorderBrush="#CCCCCC"/>
      <Button x:Name="btnBrowse" Grid.Column="2"
              Content="Browse..." Width="80" Height="32"/>
    </Grid>

    <CheckBox x:Name="chkHDD" Grid.Row="4"
              Content="HDD (keep last 46 results, default: 23)"
              IsChecked="False" VerticalContentAlignment="Center"/>

    <StackPanel Grid.Row="6" Orientation="Horizontal"
                HorizontalAlignment="Right">
      <Button x:Name="btnOK" Content="Run" Width="80"
              Height="32" Margin="0,0,8,0" IsDefault="True"/>
      <Button x:Name="btnCancel" Content="Cancel"
              Width="80" Height="32" IsCancel="True"/>
    </StackPanel>
  </Grid>
</Window>
"@

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$txtPath   = $window.FindName("txtPath")
$btnBrowse = $window.FindName("btnBrowse")
$btnOK     = $window.FindName("btnOK")
$btnCancel = $window.FindName("btnCancel")
$chkHDD    = $window.FindName("chkHDD")

$btnBrowse.Add_Click({
    $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
    $dlg.Description = "Select folder containing hammerdb.log"
    if ($dlg.ShowDialog() -eq "OK") {
        $txtPath.Text = $dlg.SelectedPath
    }
})

$btnOK.Add_Click({
    if ([string]::IsNullOrWhiteSpace($txtPath.Text)) {
        [System.Windows.MessageBox]::Show(
            "Please enter or browse to a folder path.",
            "Missing input", "OK", "Warning") | Out-Null
        return
    }
    if (-not (Test-Path $txtPath.Text)) {
        [System.Windows.MessageBox]::Show(
            "Path not found: $($txtPath.Text)",
            "Invalid path", "OK", "Warning") | Out-Null
        return
    }
    $script:folderPath = $txtPath.Text
    $script:isHDD      = $chkHDD.IsChecked
    $window.DialogResult = $true
    $window.Close()
})

$btnCancel.Add_Click({ $window.Close() })

$result = $window.ShowDialog()
if (-not $result -or -not $script:folderPath) { exit }

$folderPath = $script:folderPath
$keepRows   = if ($script:isHDD) { 46 } else { 23 }

# ── find log (exactly one) ───────────────────────────────
$logFiles = Get-ChildItem -Path $folderPath -Recurse -Filter "hammerdb.log"

if ($logFiles.Count -eq 0) {
    [System.Windows.MessageBox]::Show(
        "No hammerdb.log found under:`n$folderPath",
        "Not found", "OK", "Warning") | Out-Null
    exit
}
if ($logFiles.Count -gt 1) {
    $list = $logFiles.FullName -join "`n"
    [System.Windows.MessageBox]::Show(
        "Multiple hammerdb.log found — expected exactly one:`n`n$list",
        "Ambiguous", "OK", "Warning") | Out-Null
    exit
}

# ── parse full log ───────────────────────────────────────
$logFile     = $logFiles[0]
$lines       = Get-Content $logFile.FullName
$results     = [System.Collections.Generic.List[PSCustomObject]]::new()
$activeCount = $null

foreach ($line in $lines) {
    if ($line -match 'Vuser\s+\d+:(\d+)\s+Active Virtual Users') {
        $activeCount = $Matches[1]
    }
    if ($line -match 'Vuser\s+\d+:TEST RESULT.*?(\d+)\s+NOPM from\s+(\d+)\s+SQL') {
        $results.Add([PSCustomObject]@{
            ActiveUsers = [int]$activeCount
            NOPM        = [int]$Matches[1]
            TPM         = [int]$Matches[2]
        })
        $activeCount = $null
    }
}

# ── trim to last N result rows ───────────────────────────
$trimmed = $results | Select-Object -Last $keepRows

# ── export to desktop ────────────────────────────────────
$datetime   = Get-Date -Format "yyyyMMdd_HHmmss"
$desktop    = [Environment]::GetFolderPath("Desktop")
$outputFile = Join-Path $desktop "hammerdb_$datetime.csv"

$trimmed | Export-Csv -Path $outputFile -NoTypeInformation

[System.Windows.MessageBox]::Show(
    "Done! $($trimmed.Count) result(s) saved to:`n`n$outputFile",
    "Complete", "OK", "Information") | Out-Null

$trimmed | Format-Table
