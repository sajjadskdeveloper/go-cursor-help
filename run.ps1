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
$STORAGE_FILE = "$env:APPDATA\Cursor\User\globalStorage\storage.json"
$BACKUP_DIR = "$env:APPDATA\Cursor\User\globalStorage\backups"

# Check for administrator privileges
function Test-Administrator {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($user)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Host "$RED[Error]$NC Please run this script as an administrator."
    Write-Host "Right-click the script and select 'Run as Administrator'."
    Read-Host "Press Enter to exit"
    exit 1
}

# Display Logo
Clear-Host
Write-Host "@"
Write-Host "
    ██████╗██╗   ██╗██████╗ ███████╗ ██████╗ ██████╗ 
   ██╔════╝██║   ██║██╔══██╗██╔════╝██╔═══██╗██╔══██╗
   ██║     ██║   ██║██████╔╝███████╗██║   ██║██████╔╝
   ██║     ██║   ██║██╔══██╗╚════██║██║   ██║██╔══██╗
   ╚██████╗╚██████╔╝██║  ██║███████║╚██████╔╝██║  ██║
    ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝
"
Write-Host "$BLUE================================$NC"
Write-Host "$GREEN      Cursor ID Modification Tool      $NC"
Write-Host "$BLUE================================$NC"
Write-Host ""

# Check and close Cursor processes
Write-Host "$GREEN[Info]$NC Checking for Cursor processes..."

function Get-ProcessDetails {
    param($processName)
    Write-Host "$BLUE[Debug]$NC Retrieving details for $processName:"
    Get-WmiObject Win32_Process -Filter "name='$processName'" | 
        Select-Object ProcessId, ExecutablePath, CommandLine | 
        Format-List
}

# Define retry settings
$MAX_RETRIES = 5
$WAIT_TIME = 1

# Handle process closure
function Close-CursorProcess {
    param($processName)

    $process = Get-Process -Name $processName -ErrorAction SilentlyContinue
    if ($process) {
        Write-Host "$YELLOW[Warning]$NC Found $processName running."
        Get-ProcessDetails $processName

        Write-Host "$YELLOW[Warning]$NC Attempting to close $processName..."
        Stop-Process -Name $processName -Force

        $retryCount = 0
        while ($retryCount -lt $MAX_RETRIES) {
            $process = Get-Process -Name $processName -ErrorAction SilentlyContinue
            if (-not $process) { break }

            $retryCount++
            if ($retryCount -ge $MAX_RETRIES) {
                Write-Host "$RED[Error]$NC Unable to close $processName after $MAX_RETRIES attempts."
                Get-ProcessDetails $processName
                Write-Host "$RED[Error]$NC Please manually close the process and try again."
                Read-Host "Press Enter to exit"
                exit 1
            }
            Write-Host "$YELLOW[Warning]$NC Waiting for process closure, attempt $retryCount/$MAX_RETRIES..."
            Start-Sleep -Seconds $WAIT_TIME
        }
        Write-Host "$GREEN[Info]$NC Successfully closed $processName."
    }
}

# Close all Cursor processes
Close-CursorProcess "Cursor"
Close-CursorProcess "cursor"

# Create backup directory
if (-not (Test-Path $BACKUP_DIR)) {
    New-Item -ItemType Directory -Path $BACKUP_DIR | Out-Null
}

# Backup existing configuration
if (Test-Path $STORAGE_FILE) {
    Write-Host "$GREEN[Info]$NC Backing up configuration file..."
    $backupName = "storage.json.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item $STORAGE_FILE "$BACKUP_DIR\$backupName"
}

# Generate new ID
Write-Host "$GREEN[Info]$NC Generating new ID..."

function Get-RandomHex {
    param (
        [int]$length
    )
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

# Update configuration file
Write-Host "$GREEN[Info]$NC Updating configuration..."

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

    $jsonContent = $config | ConvertTo-Json
    [System.IO.File]::WriteAllText(
        [System.IO.Path]::GetFullPath($STORAGE_FILE), 
        $jsonContent, 
        [System.Text.Encoding]::UTF8
    )
    Write-Host "$GREEN[Info]$NC Configuration file updated successfully."
} catch {
    Write-Host "$RED[Error]$NC Failed to update configuration: $_"
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host ""
Write-Host "$GREEN[Info]$NC Configuration updated:"
Write-Host "$BLUE[Debug]$NC machineId: $MACHINE_ID"
Write-Host "$BLUE[Debug]$NC macMachineId: $MAC_MACHINE_ID"
Write-Host "$BLUE[Debug]$NC devDeviceId: $UUID"
Write-Host "$BLUE[Debug]$NC sqmId: $SQM_ID"

Write-Host "$GREEN[Info]$NC Please restart Cursor to apply the new configuration."
Read-Host "Press Enter to exit"
exit 0
