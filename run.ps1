# Set output encoding to UTF-8
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Color definitions
$RED = "`e[31m"
$GREEN = "`e[32m"
$YELLOW = "`e[33m"
$BLUE = "`e[34m"
$NC = "`e[0m"

# Configuration file paths
$STORAGE_FILE = "$env:APPDATA\SAJJAD\User\globalStorage\storage.json"
$BACKUP_DIR = "$env:APPDATA\SAJJAD\User\globalStorage\backups"

# Check administrator privileges
function Test-Administrator {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($user)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Host "$RED[ERROR]$NC Please run this script as Administrator"
    Write-Host "Right-click the script and select 'Run as Administrator'"
    Read-Host "Press Enter to exit"
    exit 1
}

# Display Logo
Clear-Host
Write-Host @"

    ███████╗ █████╗     ██╗     ██╗ █████╗ ██████╗ ██████╗ 
    ██╔════╝██╔══██╗    ██║     ██║██╔══██╗██╔══██╗██╔══██╗
    ███████╗███████║    ██║     ██║███████║██║  ██║██║  ██║
    ╚════██║██╔══██║    ██║     ██║██╔══██║██║  ██║██║  ██║
    ███████║██║  ██║    ███████╗██║██║  ██║██████╔╝██████╔╝
    ╚══════╝╚═╝  ╚═╝    ╚══════╝╚═╝╚═╝  ╚═╝╚═════╝ ╚═════╝ 

"@
Write-Host "$BLUE================================$NC"
Write-Host "$GREEN      SAJJAD ID Modifier          $NC"
Write-Host "$BLUE================================$NC"
Write-Host ""

# Check and close SAJJAD processes
Write-Host "$GREEN[INFO]$NC Checking SAJJAD processes..."

function Get-ProcessDetails {
    param($processName)
    Write-Host "$BLUE[DEBUG]$NC Getting details for $processName processes:"
    Get-WmiObject Win32_Process -Filter "name='$processName'" | 
        Select-Object ProcessId, ExecutablePath, CommandLine | 
        Format-List
}

# Process closing parameters
$MAX_RETRIES = 5
$WAIT_TIME = 1

# Process closing function
function Close-SAJJADProcess {
    param($processName)
    
    $process = Get-Process -Name $processName -ErrorAction SilentlyContinue
    if ($process) {
        Write-Host "$YELLOW[WARNING]$NC Found running $processName process"
        Get-ProcessDetails $processName
        
        Write-Host "$YELLOW[WARNING]$NC Attempting to close $processName..."
        Stop-Process -Name $processName -Force
        
        $retryCount = 0
        while ($retryCount -lt $MAX_RETRIES) {
            $process = Get-Process -Name $processName -ErrorAction SilentlyContinue
            if (-not $process) { break }
            
            $retryCount++
            if ($retryCount -ge $MAX_RETRIES) {
                Write-Host "$RED[ERROR]$NC Failed to close $processName after $MAX_RETRIES attempts"
                Get-ProcessDetails $processName
                Write-Host "$RED[ERROR]$NC Please close the process manually and try again"
                Read-Host "Press Enter to exit"
                exit 1
            }
            Write-Host "$YELLOW[WARNING]$NC Waiting for process termination, attempt $retryCount/$MAX_RETRIES..."
            Start-Sleep -Seconds $WAIT_TIME
        }
        Write-Host "$GREEN[INFO]$NC Successfully closed $processName"
    }
}

# Close all SAJJAD processes
Close-SAJJADProcess "SAJJAD"
Close-SAJJADProcess "sajjad"

# Create backup directory
if (-not (Test-Path $BACKUP_DIR)) {
    New-Item -ItemType Directory -Path $BACKUP_DIR | Out-Null
}

# Backup existing configuration
if (Test-Path $STORAGE_FILE) {
    Write-Host "$GREEN[INFO]$NC Creating configuration backup..."
    $backupName = "storage.json.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item $STORAGE_FILE "$BACKUP_DIR\$backupName"
}

# Generate new ID
Write-Host "$GREEN[INFO]$NC Generating new ID..."

function Get-RandomHex {
    param ([int]$length)
    $bytes = New-Object byte[] $length
    $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
    $rng.GetBytes($bytes)
    $rng.Dispose()
    return -join ($bytes | ForEach-Object { '{0:x2}' -f $_ })
}

$UUID = [System.Guid]::NewGuid().ToString()
$prefixBytes = [System.Text.Encoding]::UTF8.GetBytes("auth0|user_")
$prefixHex = -join ($prefixBytes | ForEach-Object { '{0:x2}' -f $_ })
$randomPart = Get-RandomHex -length 32
$MACHINE_ID = "$prefixHex$randomPart"
$MAC_MACHINE_ID = Get-RandomHex -length 32
$SQM_ID = "{$([System.Guid]::NewGuid().ToString().ToUpper())}"

# Update configuration
Write-Host "$GREEN[INFO]$NC Updating configuration..."

try {
    $storageDir = Split-Path $STORAGE_FILE -Parent
    if (-not (Test-Path $storageDir)) {
        New-Item -ItemType Directory -Path $storageDir -Force | Out-Null
    }

    $config = @{
        'telemetry.machineId' = $MACHINE_ID
        'telemetry.macMachineId' = $MAC_MACHINE_ID
        'telemetry.devDeviceId' = $UUID
        'telemetry.sqmId' = $SQM_ID
    }

    try {
        $jsonContent = $config | ConvertTo-Json
        [System.IO.File]::WriteAllText(
            [System.IO.Path]::GetFullPath($STORAGE_FILE), 
            $jsonContent, 
            [System.Text.Encoding]::UTF8
        )
        Write-Host "$GREEN[INFO]$NC Configuration file updated successfully"
    } catch {
        throw "File write failed: $_"
    }

    try {
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $userAccount = "$($env:USERDOMAIN)\$($env:USERNAME)"
        
        $acl = New-Object System.Security.AccessControl.FileSecurity
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $userAccount,
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            [System.Security.AccessControl.InheritanceFlags]::None,
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        
        try {
            $acl.AddAccessRule($accessRule)
            Set-Acl -Path $STORAGE_FILE -AclObject $acl -ErrorAction Stop
            Write-Host "$GREEN[INFO]$NC File permissions set successfully"
        } catch {
            Write-Host "$YELLOW[WARNING]$NC Using fallback permission method..."
            $result = Start-Process "icacls.exe" -ArgumentList "`"$STORAGE_FILE`" /grant `"$($env:USERNAME):(F)`"" -Wait -NoNewWindow -PassThru
            if ($result.ExitCode -eq 0) {
                Write-Host "$GREEN[INFO]$NC Permissions set using icacls"
            } else {
                Write-Host "$YELLOW[WARNING]$NC File permissions failed but write succeeded"
            }
        }
    } catch {
        Write-Host "$YELLOW[WARNING]$NC Permission setting failed: $_"
    }

} catch {
    Write-Host "$RED[ERROR]$NC Main operation failed: $_"
    
    try {
        $tempFile = [System.IO.Path]::GetTempFileName()
        $config | ConvertTo-Json | Set-Content -Path $tempFile -Encoding UTF8
        Copy-Item -Path $tempFile -Destination $STORAGE_FILE -Force
        Remove-Item -Path $tempFile
        Write-Host "$GREEN[INFO]$NC Configuration updated using fallback method"
    } catch {
        Write-Host "$RED[ERROR]$NC All methods failed"
        Write-Host "Error details: $_"
        Write-Host "Target file: $STORAGE_FILE"
        Read-Host "Press Enter to exit"
        exit 1
    }
}

# Display results
Write-Host ""
Write-Host "$GREEN[INFO]$NC Updated configuration:"
Write-Host "$BLUE[DEBUG]$NC machineId: $MACHINE_ID"
Write-Host "$BLUE[DEBUG]$NC macMachineId: $MAC_MACHINE_ID"
Write-Host "$BLUE[DEBUG]$NC devDeviceId: $UUID"
Write-Host "$BLUE[DEBUG]$NC sqmId: $SQM_ID"

# Display file structure
Write-Host ""
Write-Host "$GREEN[INFO]$NC File structure:"
Write-Host "$BLUE$env:APPDATA\SAJJAD\User$NC"
Write-Host "├── globalStorage"
Write-Host "│   ├── storage.json (modified)"
Write-Host "│   └── backups"

# List backup files
$backupFiles = Get-ChildItem "$BACKUP_DIR\*" -ErrorAction SilentlyContinue
if ($backupFiles) {
    foreach ($file in $backupFiles) {
        Write-Host "│       └── $($file.Name)"
    }
} else {
    Write-Host "│       └── (empty)"
}

# Final instructions
Write-Host ""
Write-Host "$GREEN================================$NC"
Write-Host "$GREEN[INFO]$NC Please restart SAJJAD to apply changes"
Write-Host ""

# Disable auto-update prompt
Write-Host ""
Write-Host "$YELLOW[PROMPT]$NC Disable automatic updates?"
Write-Host "0) No - Keep default settings (press Enter)"
Write-Host "1) Yes - Disable auto-updates"
$choice = Read-Host "Enter choice (1 or press Enter)"

if ($choice -eq "1") {
    Write-Host ""
    Write-Host "$GREEN[INFO]$NC Handling auto-updates..."
    $updaterPath = "$env:LOCALAPPDATA\sajjad-updater"

    if (Test-Path $updaterPath) {
        try {
            Remove-Item -Path $updaterPath -Force -Recurse -ErrorAction Stop
            Write-Host "$GREEN[INFO]$NC Removed updater directory"
            New-Item -Path $updaterPath -ItemType File -Force | Out-Null
            Write-Host "$GREEN[INFO]$NC Created update blocker file"
        }
        catch {
            Write-Host "$RED[ERROR]$NC Update handling failed: $_"
        }
    }
    else {
        New-Item -Path $updaterPath -ItemType File -Force | Out-Null
        Write-Host "$GREEN[INFO]$NC Created update blocker file"
    }
}
elseif ($choice -ne "") {
    Write-Host "$YELLOW[INFO]$NC Keeping default settings"
}
else {
    Write-Host "$YELLOW[INFO]$NC Keeping default settings"
}

Read-Host "Press Enter to exit"
exit 0
