
# WindowsMonitor - Windows System Monitoring Solution


## Overview
WindowsMonitor is a PowerShell-based monitoring solution that tracks critical system resources and configurations on Windows machines. It provides automated alerts when key metrics exceed thresholds or when system services change status.

## Features
- **Resource Monitoring**: 
  - CPU Utilization (1-minute average)
  - Memory Usage
  - Disk Space (All fixed drives)
- **Service Monitoring**: Track status of configured Windows services
- **Time Synchronization**:
  - NTP Server time drift detection
  - Time zone configuration validation
- **Alerting System**:
  - Email notifications for critical events
  - State tracking for change detection
- **Logging**:
  - Rotating log files with severity levels
  - JSON state preservation between runs

## Requirements
- Windows 10/11 or Windows Server 2016+
- PowerShell 5.1 or newer
- .NET Framework 4.7.2+
- Network access to:
  - SMTP server (Office 365 in default config)
  - NTP server (pool.ntp.org in default config)

## Setup
1. **Download Script**
   ```powershell
   Invoke-WebRequest -Uri https://example.com/WindowsMonitor.ps1 -OutFile WindowsMonitor.ps1
   ```

2. **Configure Execution Policy**
   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

3. **Edit Configuration**  
   Open the script and modify these sections:
   ```powershell
   $Config = @{
       Notification = @{
           SmtpServer = "smtp.office365.com"
           From = "alerts@yourcompany.com"
           To = "admin@yourcompany.com"
           Credential = @{
               User = "alerts@yourcompany.com"
               EncodedPassword = "Base64EncodedPasswordHere"
           }
       }
       Monitoring = @{
           Services = @("YourCriticalService1", "YourCriticalService2")
           TimeZone = "Your-Time-Zone"
       }
   }
   ```

## Configuration Guide
### Core Settings
| Section         | Key                | Description                                  |
|-----------------|--------------------|----------------------------------------------|
| `LogSettings`   | `MaxSizeKB`        | Maximum log file size before rotation (KB)   |
| `Monitoring`    | `Thresholds.Cpu`   | CPU usage alert threshold (%)                |
| `Monitoring`    | `NtpServer`        | Time synchronization server                  |
| `Notification`  | `EncodedPassword`  | Base64 encoded SMTP password                 |

### Encode SMTP Password
```powershell
$plainPassword = "YourSMTPPassword"
$encodedPassword = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($plainPassword))
Write-Host "Encoded password: $encodedPassword"
```

## Usage
### Manual Run
```powershell
.\WindowsMonitor.ps1
```

### Scheduled Task (Daily)
```powershell
$trigger = New-JobTrigger -Daily -At 9am
Register-ScheduledJob -Name WindowsMonitor -FilePath .\WindowsMonitor.ps1 -Trigger $trigger
```

## Alert Triggers
| Metric                | Threshold              | Example Alert Message                        |
|-----------------------|------------------------|----------------------------------------------|
| CPU Usage             | > 90%                  | CPU usage exceeded threshold: 95.25%         |
| Memory Usage          | > 90%                  | Memory usage exceeded threshold: 92.80%      |
| Disk Space            | < 10% free             | Drive C: Free space below threshold: 8.50%   |
| Time Drift            | > ±10 seconds          | System time drift detected: 15.3s            |
| Service Status Change | Any status change      | Service MySQL changed from Running to Stopped|

## Log Management
- **Location**: Same directory as script (`WindowsMonitor.log`)
- **Rotation**:
  - New log created when reaching 64KB
  - Maximum 5 backup logs kept
- **Format**:
  ```
  MM/dd/yyyy HH:mm:ss.fff|Level|Message
  07/15/2024 14:30:45.123|Info|Monitoring check completed
  ```

## Security Considerations
1. **Credential Protection**:
   - Always use encoded passwords
   - Restrict script access to authorized users
2. **Network Security**:
   - Use TLS 1.2 for SMTP connections
   - Restrict NTP server access to internal sources
3. **Execution Context**:
   - Run with least-privileged account
   - Store in secure directory with access controls

## Troubleshooting
### Common Issues
| Symptom                      | Resolution                                  |
|------------------------------|---------------------------------------------|
| SMTP authentication failed   | Verify encoded password and SMTP settings   |
| NTP measurement failed       | Check firewall rules for UDP port 123       |
| Service not found            | Validate service names in configuration     |
| Time zone mismatch           | Update `TimeZone` value in configuration    |

### Debug Mode
```powershell
Set-PSDebug -Trace 1
.\WindowsMonitor.ps1
