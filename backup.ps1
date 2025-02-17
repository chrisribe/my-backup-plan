# Probably better..... 
# https://github.com/restic/restic/tree/v0.17.3

param (
  [string]$ConfigFile,
  [string]$optionFlag
)

# Function to read configuration file
function Read-ConfigFile {
  param (
    [string]$ConfigFilePath
  )
  if (Test-Path $ConfigFilePath) {
    $config = Get-Content $ConfigFilePath | ConvertFrom-Json
    return $config
  }
  else {
    Write-Error "Configuration file not found: $ConfigFilePath"
    exit 1
  }
}

function New-ScheduledTask {
  param (
    [string]$TaskName,
    [string]$ScriptPath,
    [string]$ConfigFilePath,
    [string]$Frequency = "1h"
  )

  # Parse the frequency
  $trigger = switch -regex ($Frequency) {
    "^(\d+)s$" { 
      $interval = [int]$matches[1]
      New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds($interval) -RepetitionInterval (New-TimeSpan -Seconds $interval) -RepetitionDuration (New-TimeSpan -Days 3650) # 10 years
    }
    "^(\d+)m$" { 
      $interval = [int]$matches[1]
      New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes($interval) -RepetitionInterval (New-TimeSpan -Minutes $interval) -RepetitionDuration (New-TimeSpan -Days 3650) # 10 years
    }
    "^(\d+)h$" { 
      $interval = [int]$matches[1]
      New-ScheduledTaskTrigger -Once -At (Get-Date).Date.AddHours((Get-Date).Hour + $interval) -RepetitionInterval (New-TimeSpan -Hours $interval) -RepetitionDuration (New-TimeSpan -Days 3650) # 10 years
    }
    "^(\d+)d$" { 
      $interval = [int]$matches[1]
      New-ScheduledTaskTrigger -Daily -At (Get-Date).Date.AddDays($interval) -RepetitionDuration (New-TimeSpan -Days 3650) # 10 years
    }
    "^(\d+)w$" { 
      $interval = [int]$matches[1]
      New-ScheduledTaskTrigger -Weekly -At (Get-Date).Date.AddDays(7 * $interval) -RepetitionDuration (New-TimeSpan -Days 3650) # 10 years
    }
    default { 
      Write-Error "Invalid frequency: $Frequency"
      exit 1
    }
  }


  $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument " -WindowStyle Hidden -NoProfile -ExecutionPolicy ByPass -File `"$ScriptPath`" -ConfigFile `"$ConfigFilePath`""
  $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

  Write-Host "Setting up scheduled task '$TaskName' to run every $Frequency."

  # Register or update the scheduled task
  if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
  }
  Register-ScheduledTask `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -TaskName $TaskName `
    -Description "Backup task"
}

function Remove-ScheduledTask {
  param (
    [string]$TaskName
  )

  if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Output "Scheduled task '$TaskName' has been removed."
  }
  else {
    Write-Output "Scheduled task '$TaskName' does not exist."
  }
}

# Function to test if a backup should be run based on the frequency, last run time, day of week, and target time
function ShouldRunBackup {
  param (
    [string]$Frequency,
    [datetime]$LastRunTime,
    [string]$DayOfWeek,
    [string]$TargetTime
  )

  $currentTime = Get-Date
  $currentDayOfWeek = $currentTime.DayOfWeek.ToString()
  
  # Parse the target time if provided
  $targetDateTime = $null 
  if ($TargetTime) { 
    $targetDateTime = [datetime]::ParseExact($TargetTime, "h:mm tt", $null) 
  }

  # Check if it's the right day and time for weekly backups
  if ($Frequency -eq "weekly" -and $currentDayOfWeek -eq $DayOfWeek) {
    if ($targetDateTime) {
      return ($currentTime.Hour -ge $targetDateTime.Hour -and $currentTime.Minute -ge $targetDateTime.Minute)
    }
    else {
      return ($currentTime -gt $LastRunTime.AddDays(7))
    }
  }

  # Check other frequencies
  switch ($Frequency) {
    "hourly" {
      return ($currentTime -gt $LastRunTime.AddHours(1))
    }
    "daily" {
      return ($currentTime -gt $LastRunTime.AddDays(1))
    }
    default {
      return $true # Run backup if no valid frequency is provided
    }
  }
}

# Function to create a unique hash for the folder pair 
function Get-FolderKey {
  param (
      [string]$SourceFolder,
      [string]$DestinationFolder
  )

  $combinedPath = "$SourceFolder|$DestinationFolder"
  $hash = [System.Security.Cryptography.HashAlgorithm]::Create("SHA256")
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($combinedPath)
  $hashBytes = $hash.ComputeHash($bytes)
  $hashString = [BitConverter]::ToString($hashBytes) -replace '-', ''
  return $hashString
}

function Read-ConfigFile {
  param (
      [string]$ConfigFilePath
  )
  if (Test-Path $ConfigFilePath) {
      $config = Get-Content $ConfigFilePath -Raw | ConvertFrom-Json
      return $config
  } else {
      Write-Error "Configuration file not found: $ConfigFilePath"
      exit 1
  }
}

function Write-ConfigFile {
  param (
      [string]$ConfigFilePath,
      [object]$Data
  )
  $Data | ConvertTo-Json -Depth 3 | Set-Content $ConfigFilePath
}

function Get-ConfigFileData {
  param (
      [string]$CommandPath,
      [string]$ConfigFile
  )

  # Read configuration file
  if ($ConfigFile) {
    
    if ($ConfigFile -like "./*" -or $ConfigFile -like ".\*") {
      $ConfigFile = Join-Path -Path (Split-Path -Parent $CommandPath) -ChildPath ($ConfigFile -replace "^\./", "" -replace "^\.\\", "")
    }    
    $config = Read-ConfigFile -ConfigFilePath $ConfigFile
  }
  else {
    Write-Error "ConfigFile is required."
    exit 1
  }

  # Validate configuration
  if (-not $config.Folders -or $config.Folders.Count -eq 0) {
    Write-Error "No folders specified in the configuration file."
    exit 1
  }
  return $config
}


function Get-ConfigValue($folderPair, $key, $defaultValue) {
  if ($folderPair.$key) { 
    return $folderPair.$key 
  } else { 
    return $defaultValue 
  }
}

#Common robocopy exit codes:
# 0: No errors occurred, and no files were copied.
# 1: All files were copied successfully.
# 2: Some files were copied successfully, and some files were skipped.
# 3: Some files were copied successfully, and some files failed to copy.
# 5: Some files were copied successfully, and some files were skipped due to mismatched file attributes.
# 6: Some files were copied successfully, and some files failed to copy due to mismatched file attributes.
function RunBackup($SourceFolder, $DestinationFolder, $FolderKey, $trackingData, $TrackingFilePath) {
  $robocopyCmd = "robocopy `"$SourceFolder`" `"$DestinationFolder`" /MIR /R:5 /W:10"
  Write-Output "Executing: $robocopyCmd"
  Invoke-Expression $robocopyCmd
  if ($LASTEXITCODE -in 0, 1, 2) {
    if ($LASTEXITCODE -eq 2) {
      Write-Warning "Robocopy completed with some files skipped for $SourceFolder to $DestinationFolder."
    }
    $currentTime = Get-Date
    $trackingData.folders.$FolderKey = @{ 
      "SourceFolder" = $SourceFolder 
      "DestinationFolder" = $DestinationFolder
      "LastRunTime" = $currentTime.ToString("o") # Use ISO 8601 format for DateTime
    }
    # Save the updated tracking information to the JSON file after each successful backup
    Write-ConfigFile -ConfigFilePath $TrackingFilePath -Data $trackingData
  }
  else {
    Write-Error "Robocopy failed for $SourceFolder to $DestinationFolder with exit code $LASTEXITCODE"
  }
}

# # Check if BurntToast module is installed
# if (-not (Get-Module -ListAvailable -Name BurntToast)) {
#   Write-Host "BurntToast module not found. Installing..."
#   Install-Module -Name BurntToast -Force -Scope CurrentUser
# }

# # Import the BurntToast module
# Import-Module BurntToast

# # Function to send a notification
# function Send-Notification {
#   param (
#     [string]$Title,
#     [string]$Message
#   )
#   New-BurntToastNotification -Text $Title, $Message
# }
#Send-Notification -Title "Start" -Message "Backup script..."

  ####  Main ####
  $TaskName = "BackupTask"
  $CommandPath = $MyInvocation.MyCommand.Path
  
  # Remove the scheduled task if the -RemoveTask parameter is specified
  if ($optionFlag -eq "RemoveTask") {
    Remove-ScheduledTask -TaskName $TaskName
    exit 0
  }

  # Read the configuration file
  $config = Get-ConfigFileData -CommandPath $CommandPath -ConfigFile $ConfigFile

  # Set up the scheduled task if the -SetupTask parameter is specified
  if ($optionFlag -eq "SetupTask") {
    $ScriptPath = $MyInvocation.MyCommand.Path
    $Frequency = if ($config.Frequency) { $config.Frequency } else { "1h" }

    New-ScheduledTask -TaskName $TaskName -ScriptPath $ScriptPath -ConfigFilePath $ConfigFile -Frequency $Frequency
    write-host "Scheduled task has been set up."
    exit 0
  }

  # Define the path for the tracking file
  $TrackingFilePath = Join-Path -Path (Split-Path -Parent $MyInvocation.MyCommand.Path) -ChildPath "backup_tracking.json"

  # Read the tracking information from the JSON file
  $trackingData = @{
    "folders" = @{}
  }
  if (Test-Path $TrackingFilePath) {
    $trackingData = Read-ConfigFile $TrackingFilePath
  }

  # Loop through each folder pair and perform the backup using robocopy
  foreach ($folderPair in $config.Folders) {
    $SourceFolder = $folderPair.SourceFolder
    $DestinationFolder = $folderPair.DestinationFolder
    $FolderFrequency = Get-ConfigValue $folderPair "Frequency" "immediate"
    $DayOfWeek = Get-ConfigValue $folderPair "DayOfWeek" ""
    $TargetTime = Get-ConfigValue $folderPair "TargetTime" ""
    $FolderKey = Get-FolderKey -SourceFolder $SourceFolder -DestinationFolder $DestinationFolder
  
    if (-not $SourceFolder -or -not $DestinationFolder) {
      Write-Error "SourceFolder and DestinationFolder are required for each folder pair."
      continue
    }
  
    $LastRunTime = if ($trackingData.folders.PSObject.Properties.Name.Contains($FolderKey)) { [datetime]$trackingData.folders.$FolderKey.LastRunTime } else { [datetime]::MinValue }
    $NeedsToRun = ShouldRunBackup $FolderFrequency $LastRunTime $DayOfWeek $TargetTime
    if ($FolderFrequency -eq "immediate" -or $NeedsToRun -eq $true) {
      RunBackup $SourceFolder $DestinationFolder $FolderKey $trackingData $TrackingFilePath
    }
    else {
      Write-Output "Skipping backup for $SourceFolder. Last run time: $LastRunTime"
    }
  }
