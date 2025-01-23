# Set the output encoding to UTF-8
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Color definition
$RED = "`e[31m"
$GREEN = "`e[32m"
$YELLOW = "`e[33m"
$BLUE = "`e[34m"
$NC = "`e[0m"

# Configuration file path
$STORAGE_FILE = "$env:APPDATA\Cursor\User\globalStorage\storage.json"
$BACKUP_DIR = "$env:APPDATA\Cursor\User\globalStorage\backups"

# Check administrator privileges
function Test-Administrator {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($user)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Host "$RED[error]$NC Please run this script as an administrator"
    Write-Host "Right-click the script and select 'Run as Administrator'"
    Read-Host "Press Enter to exit"
    exit 1
}

# Display Logo
Clear-Host
Write-Host @"

    ╗
   ██╔════╝██║ ██║██╔══██╗██╔════╝██╔═══██╗██╔══██╗
   ║
   ██║ ██║ ██║██╔══██╗╚════██║██║ ██║██╔══██╗
   *
    ╚═════╝ ╚═════╝ ╚═╝ ╚═╝╚══════╝ ╚═════╝ ╚═╝ ╚═╝

"@
Write-Host "$BLUE================================$NC"
Write-Host "$GREEN Cursor ID Modification Tool $NC"
Write-Host "$BLUE================================$NC"
Write-Host ""

# Check and close the Cursor process
Write-Host "$GREEN[INFO]$NC Check Cursor Process..."

function Get-ProcessDetails {
    param($processName)
    Write-Host "$BLUE[debug]$NC Getting $processName process details:"
    Get-WmiObject Win32_Process -Filter "name='$processName'" |
        Select-Object ProcessId, ExecutablePath, CommandLine |
        Format-List
}

# Define the maximum number of retries and waiting time
$MAX_RETRIES = 5
$WAIT_TIME = 1

# Process shutdown
function Close-CursorProcess {
    param($processName)
    
    $process = Get-Process -Name $processName -ErrorAction SilentlyContinue
    if ($process) {
        Write-Host "$YELLOW[Warning]$NC found $processName running"
        Get-ProcessDetails $processName
        
        Write-Host "$YELLOW[WARN]$NC Trying to shut down $processName..."
        Stop-Process -Name $processName -Force
        
        $retryCount = 0
        while ($retryCount -lt $MAX_RETRIES) {
            $process = Get-Process -Name $processName -ErrorAction SilentlyContinue
            if (-not $process) { break }
            
            $retryCount++
            if ($retryCount -ge $MAX_RETRIES) {
                Write-Host "$RED[ERROR]$NC Failed to close $processName after $MAX_RETRIES attempts"
                Get-ProcessDetails $processName
                Write-Host "$RED[error]$NC Please manually close the process and try again"
                Read-Host "Press Enter to exit"
                exit 1
            }
            Write-Host "$YELLOW[WARN]$NC Waiting for process to close, trying $retryCount/$MAX_RETRIES..."
            Start-Sleep -Seconds $WAIT_TIME
        }
        Write-Host "$GREEN[info]$NC $processName successfully closed"
    }
}

# Close all Cursor processes
Close-CursorProcess "Cursor"
Close-CursorProcess "cursor"

# Create a backup directory
if (-not (Test-Path $BACKUP_DIR)) {
    New-Item -ItemType Directory -Path $BACKUP_DIR | Out-Null
}

# Back up the existing configuration
if (Test-Path $STORAGE_FILE) {
    Write-Host "$GREEN[INFO]$NC Backing up configuration files..."
    $backupName = "storage.json.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item $STORAGE_FILE "$BACKUP_DIR\$backupName"
}

# Generate a new ID
Write-Host "$GREEN[INFO]$NC Generating new ID..."

# Function to generate random byte array and convert to hexadecimal string
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
# Convert auth0|user_ to hexadecimal byte array
$prefixBytes = [System.Text.Encoding]::UTF8.GetBytes("auth0|user_")
$prefixHex = -join ($prefixBytes | ForEach-Object { '{0:x2}' -f $_ })
# Generate a 32-byte (64 hexadecimal characters) random number as the random part of machineId
$randomPart = Get-RandomHex -length 32
$MACHINE_ID = "$prefixHex$randomPart"
$MAC_MACHINE_ID = Get-RandomHex -length 32
$SQM_ID = "{$([System.Guid]::NewGuid().ToString().ToUpper())}"

# Create or update configuration files
Write-Host "$GREEN[INFO]$NC Updating configuration..."

try {
    # Make sure the directory exists
    $storageDir = Split-Path $STORAGE_FILE -Parent
    if (-not (Test-Path $storageDir)) {
        New-Item -ItemType Directory -Path $storageDir -Force | Out-Null
    }

    # Write configuration
    $config = @{
        'telemetry.machineId' = $MACHINE_ID
        'telemetry.macMachineId' = $MAC_MACHINE_ID
        'telemetry.devDeviceId' = $UUID
        'telemetry.sqmId' = $SQM_ID
    }

    # Use System.IO.File methods to write to a file
    try {
        $jsonContent = $config | ConvertTo-Json
        [System.IO.File]::WriteAllText(
            [System.IO.Path]::GetFullPath($STORAGE_FILE),
            $jsonContent,
            [System.Text.Encoding]::UTF8
        )
        Write-Host "$GREEN[INFO]$NC Successfully wrote configuration file"
    } catch {
        throw "Failed to write file: $_"
    }

    # Try setting file permissions
    try {
        # Use the current username and domain name
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $userAccount = "$($env:USERDOMAIN)\$($env:USERNAME)"
        
        # Create a new access control list
        $acl = New-Object System.Security.AccessControl.FileSecurity
        
        # Add full control permissions for the current user
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $userAccount, # Use domain name\user name format
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            [System.Security.AccessControl.InheritanceFlags]::None,
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        
        try {
            $acl.AddAccessRule($accessRule)
            Set-Acl -Path $STORAGE_FILE -AclObject $acl -ErrorAction Stop
            Write-Host "$GREEN[INFO]$NC Successfully set file permissions"
        } catch {
            # If the first method fails, try icacls
            Write-Host "$YELLOW[WARNING]$NC Using alternate method to set permissions..."
            $result = Start-Process "icacls.exe" -ArgumentList "`"$STORAGE_FILE`" /grant `"$($env:USERNAME):(F)`"" -Wait -NoNewWindow -PassThru
            if ($result.ExitCode -eq 0) {
                Write-Host "$GREEN[INFO]$NC Successfully used icacls to set file permissions"
            } else {
                Write-Host "$YELLOW[Warning]$NC Failed to set file permissions, but the file was written successfully"
            }
        }
    } catch {
        Write-Host "$YELLOW[WARNING]$NC Failed to set file permissions: $_"
        Write-Host "$YELLOW[WARNING]$NC Attempting to use the icacls command..."
        try {
            $result = Start-Process "icacls.exe" -ArgumentList "`"$STORAGE_FILE`" /grant `"$($env:USERNAME):(F)`"" -Wait -NoNewWindow -PassThru
            if ($result.ExitCode -eq 0) {
                Write-Host "$GREEN[INFO]$NC Successfully used icacls to set file permissions"
            } else {
                Write-Host "$YELLOW[Warning]$NC All permission setting methods failed, but the file was written successfully"
            }
        } catch {
            Write-Host "$YELLOW[WARNING]$NC icacls command failed: $_"
        }
    }

} catch {
    Write-Host "$RED[ERROR]$NC Primary operation failed: $_"
    Write-Host "$YELLOW[Try]$NC Use alternative method..."
    
    try {
        # Alternative method: Use Add-Content
        $tempFile = [System.IO.Path]::GetTempFileName()
        $config | ConvertTo-Json | Set-Content -Path $tempFile -Encoding UTF8
        Copy-Item -Path $tempFile -Destination $STORAGE_FILE -Force
        Remove-Item -Path $tempFile
        Write-Host "$GREEN[INFO]$NC Successfully wrote configuration using alternative method"
    } catch {
        Write-Host "$RED[ERROR]$NC All attempts failed"
        Write-Host "Error Details: $_"
        Write-Host "Destination File: $STORAGE_FILE"
        Write-Host "Please make sure you have sufficient permissions to access the file"
        Read-Host "Press Enter to exit"
        exit 1
    }
}

# Display results
Write-Host ""
Write-Host "$GREEN[INFO]$NC Updated configuration:"
Write-Host "$BLUE[debug]$NC machineId:$MACHINE_ID"
Write-Host "$BLUE[debug]$NC macMachineId:$MAC_MACHINE_ID"
Write-Host "$BLUE[debug]$NC devDeviceId:$UUID"
Write-Host "$BLUE[DEBUG]$NC sqmId: $SQM_ID"

# Display the file tree structure
Write-Host ""
Write-Host "$GREEN[INFO]$NC File Structure:"
Write-Host "$BLUE$env:APPDATA\Cursor\User$NC"
Write-Host "├── globalStorage"
Write-Host "│ ├── storage.json (modified)"
Write-Host "│ └── backups"

# List backup files
$backupFiles = Get-ChildItem "$BACKUP_DIR\*" -ErrorAction SilentlyContinue
if ($backupFiles) {
    foreach ($file in $backupFiles) {
        Write-Host "│ └── $($file.Name)"
    }
} else {
    Write-Host "│ └── (empty)"
}

# Display public account information
Write-Host ""
Write-Host "$GREEN================================$NC"
Write-Host "$YELLOW Follow the public account [Jianbing Guozijuan AI] to exchange more Cursor skills and AI knowledge $NC"
Write-Host "$GREEN================================$NC"
Write-Host ""
Write-Host "$GREEN[info]$NC Please restart Cursor to apply the new configuration"
Write-Host ""

# Ask if you want to disable automatic updates
Write-Host ""
Write-Host "$YELLOW[Ask]$NC Do you want to disable the automatic update feature of the Cursor?"
Write-Host "0) No - Keep default settings (Press Enter)"
Write-Host "1) Yes - Disable automatic updates"
$choice = Read-Host "Please enter an option (1 or press Enter)"

if ($choice -eq "1") {
    Write-Host ""
    Write-Host "$GREEN[INFO]$NC Processing automatic updates..."
    $updaterPath = "$env:LOCALAPPDATA\cursor-updater"

    if (Test-Path $updaterPath) {
        try {
            # Force delete directory
            Remove-Item -Path $updaterPath -Force -Recurse -ErrorAction Stop
            Write-Host "$GREEN[INFO]$NC Successfully deleted cursor-updater directory"
            
            # Create a file with the same name
            New-Item -Path $updaterPath -ItemType File -Force | Out-Null
            Write-Host "$GREEN[INFO]$NC Successfully created block file"
        }
        catch {
            Write-Host "$RED[ERROR]$NC Error processing cursor-updater: $_"
        }
    }
    else {
        # Create a blocking file directly
        New-Item -Path $updaterPath -ItemType File -Force | Out-Null
        Write-Host "$GREEN[INFO]$NC Successfully created block file"
    }
}
elseif ($choice -ne "") {
    Write-Host "$YELLOW[info]$NC Keep the default settings and do not change"
}
else {
    Write-Host "$YELLOW[info]$NC Keep the default settings and do not change"
}



Read-Host "Press Enter to exit"
exit 0
