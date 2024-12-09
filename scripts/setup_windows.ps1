# setup_windows.ps1

# Detect OS Version
$osVersion = (Get-WmiObject -Class Win32_OperatingSystem).Version
Write-Output "OS Version: $osVersion"

if ($osVersion -ge "10.0") {
    Write-Output "Setting up for Windows 10 or later..."

    # Enable WSL
    Write-Output "Enabling WSL..."
    wsl --install --no-launch

    # Wait for WSL to initialize
    Write-Output "Waiting for WSL to initialize..."
    $wslReady = $false
    while (-not $wslReady) {
        try {
            wsl -e echo "WSL is ready"
            $wslReady = $true
        } catch {
            Write-Output "WSL not ready yet, retrying in 5 seconds..."
            Start-Sleep -Seconds 5
        }
    }

    # Install Ansible in WSL
    Write-Output "Installing Ansible in WSL..."
    wsl -e sudo apt update
    wsl -e sudo apt install -y ansible

   # Run the Ansible backup plan
   Write-Output "Running Ansible backup plan..."
#   wsl -e ansible-playbook -i /mnt/c/cribe/GitRepos/chrisribe/my-backup-plan/inventory/hosts.ini /mnt/c//mnt/c/cribe/GitRepos/chrisribe/my-backup-plan/ansible/playbooks/windows/win10_and_up.yml

} else {
    Write-Output "This script is designed for Windows 10 or later."
}