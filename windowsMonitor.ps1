[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#region Configuration
$Config = @{
    ScriptName = "WindowsMonitor"
    ScriptVersion = "1.0"
    LogSettings = @{
        Path = $PSScriptRoot
        FileName = "WindowsMonitor.log"
        MaxSizeKB = 64
        BackupCount = 5
    }
    Monitoring = @{
        Services = @("LenovoVantageService", "nscp", "WRCoreService", "WRSVC")
        NtpServer = "north-america.pool.ntp.org"
        TimeZone = "UTC-06"
        Thresholds = @{
            Cpu = 90.0
            Memory = 90.0
            DiskSpace = 10.0
            TimeDrift = 10.0
        }
    }
    Notification = @{
        SmtpServer = "smtp.office365.com"
        Port = 587
        From = "alerts@example.com"
        To = "admin@example.com"
        Credential = @{
            User = "alerts@example.com"
            EncodedPassword = "ENCODEDPASSWORD=="
        }
    }
}
#endregion

#region Initialization
$LogPath = Join-Path $Config.LogSettings.Path $Config.LogSettings.FileName
$StateFile = Join-Path $Config.LogSettings.Path "WindowsMonitor_State.json"
$CurrentState = @{}
$PreviousState = @{}
$AlertMessages = [System.Collections.Generic.List[string]]::new()
$RecoveryMessages = [System.Collections.Generic.List[string]]::new()
#endregion

#region Functions
function Write-SystemLog {
    param(
        [ValidateSet('Info','Warning','Error')]
        [string]$Level,
        [string]$Message
    )

    $timestamp = Get-Date -Format "MM/dd/yyyy HH:mm:ss.fff"
    $logEntry = "$timestamp|$Level|$Message"
    
    # Manage log rotation
    if (Test-Path $LogPath -PathType Leaf) {
        $logFile = Get-Item $LogPath
        if ($logFile.Length -gt ($Config.LogSettings.MaxSizeKB * 1KB)) {
            $backupPath = Join-Path $Config.LogSettings.Path "WindowsMonitor_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
            Move-Item $LogPath $backupPath -Force
        }
    }

    Add-Content -Path $LogPath -Value $logEntry -Encoding UTF8
    Write-Host "[$Level] $Message" -ForegroundColor $(switch ($Level) {
        'Info' { 'Green' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
    })
}

function Get-SystemMetrics {
    # CPU Utilization (1 minute average)
    $cpu = (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 10 | 
            Select-Object -ExpandProperty CounterSamples | 
            Measure-Object -Property CookedValue -Average).Average

    # Memory Utilization
    $os = Get-CimInstance Win32_OperatingSystem
    $memory = ($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize * 100

    # Disk Space
    $disks = Get-Volume | Where-Object DriveType -eq Fixed | ForEach-Object {
        @{
            Drive = $_.DriveLetter
            Free = ($_.SizeRemaining / $_.Size) * 100
        }
    }

    # Service Statuses
    $services = $Config.Monitoring.Services | ForEach-Object {
        try {
            $status = (Get-Service $_ -ErrorAction Stop).Status.ToString()
        } catch {
            $status = 'Not Found'
        }
        @{ Name = $_; Status = $status }
    }

    # Time Synchronization
    $timeDrift = Measure-TimeDrift -NtpServer $Config.Monitoring.NtpServer

    return @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Cpu = [math]::Round($cpu, 2)
        Memory = [math]::Round($memory, 2)
        Disks = $disks
        Services = $services
        TimeDrift = $timeDrift
        TimeZone = (Get-TimeZone).Id
    }
}

function Measure-TimeDrift {
    param([string]$NtpServer)
    
    try {
        $ntpData = ,0 * 48
        $ntpData[0] = 0x1B
        
        $socket = New-Object Net.Sockets.Socket(
            [Net.Sockets.AddressFamily]::InterNetwork,
            [Net.Sockets.SocketType]::Dgram,
            [Net.Sockets.ProtocolType]::Udp
        )
        
        $socket.Connect($NtpServer, 123)
        $socket.Send($ntpData) | Out-Null
        $socket.Receive($ntpData) | Out-Null
        $socket.Close()

        $localTime = [DateTime]::UtcNow
        $ntpTime = [BitConverter]::ToUInt64($ntpData[43..40] + $ntpData[47..44], 0)
        $ntpTime = [DateTime]::new(1900, 1, 1).AddMilliseconds($ntpTime / 0.0001)

        return [math]::Round(($ntpTime - $localTime).TotalSeconds, 1)
    }
    catch {
        Write-SystemLog -Level Error -Message "NTP measurement failed: $($_.Exception.Message)"
        return $null
    }
}

function Send-StatusAlert {
    param(
        [string]$Subject,
        [string[]]$Messages,
        [bool]$IsCritical = $true
    )

    $mailParams = @{
        SmtpServer = $Config.Notification.SmtpServer
        Port = $Config.Notification.Port
        UseSsl = $true
        From = $Config.Notification.From
        To = $Config.Notification.To
        Subject = "$Subject - $env:COMPUTERNAME"
        Body = $Messages -join "`n`n"
        Credential = New-Object System.Management.Automation.PSCredential (
            $Config.Notification.Credential.User,
            (ConvertTo-SecureString -String ([System.Text.Encoding]::ASCII.GetString(
                [System.Convert]::FromBase64String($Config.Notification.Credential.EncodedPassword)
            )) -AsPlainText -Force)
        )
    }

    try {
        Send-MailMessage @mailParams
        Write-SystemLog -Level Info -Message "Alert sent: $Subject"
    }
    catch {
        Write-SystemLog -Level Error -Message "Failed to send alert: $($_.Exception.Message)"
    }
}
#endregion

#region Main Execution
try {
    # Load previous state
    if (Test-Path $StateFile) {
        $PreviousState = Get-Content $StateFile | ConvertFrom-Json -AsHashtable
    }

    # Collect current metrics
    $CurrentState = Get-SystemMetrics

    # Check resource thresholds
    if ($CurrentState.Cpu -ge $Config.Monitoring.Thresholds.Cpu) {
        $AlertMessages.Add("CPU usage exceeded threshold: $($CurrentState.Cpu)%")
    }

    if ($CurrentState.Memory -ge $Config.Monitoring.Thresholds.Memory) {
        $AlertMessages.Add("Memory usage exceeded threshold: $($CurrentState.Memory)%")
    }

    foreach ($disk in $CurrentState.Disks) {
        if ($disk.Free -le $Config.Monitoring.Thresholds.DiskSpace) {
            $AlertMessages.Add("Drive $($disk.Drive): Free space below threshold: $($disk.Free.ToString('0.00'))%")
        }
    }

    # Check service status changes
    foreach ($service in $CurrentState.Services) {
        $previousStatus = $PreviousState.Services | Where-Object Name -eq $service.Name | Select-Object -Expand Status
        if ($previousStatus -and $service.Status -ne $previousStatus) {
            $AlertMessages.Add("Service $($service.Name) changed status from $previousStatus to $($service.Status)")
        }
    }

    # Check time synchronization
    if ($CurrentState.TimeDrift -and [math]::Abs($CurrentState.TimeDrift) -gt $Config.Monitoring.Thresholds.TimeDrift) {
        $AlertMessages.Add("System time drift detected: $($CurrentState.TimeDrift)s")
    }

    # Check time zone
    if ($CurrentState.TimeZone -ne $Config.Monitoring.TimeZone) {
        $AlertMessages.Add("Incorrect time zone: $($CurrentState.TimeZone) (should be $($Config.Monitoring.TimeZone))")
    }

    # Send alerts if needed
    if ($AlertMessages.Count -gt 0) {
        Send-StatusAlert -Subject "System Alert" -Messages $AlertMessages -IsCritical $true
    }

    # Save current state
    $CurrentState | ConvertTo-Json | Out-File $StateFile -Force
}
catch {
    Write-SystemLog -Level Error -Message "Critical error: $($_.Exception.Message)"
    exit 1
}

Write-SystemLog -Level Info -Message "Monitoring check completed successfully"
exit 0
#endregion
