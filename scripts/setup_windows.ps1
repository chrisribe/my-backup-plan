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

    # Clone the Git repository into WSL
    Write-Output "Cloning Git repository into WSL..."
    wsl -e bash -c "cd ~ && git clone https://github.com/chrisribe/my-backup-plan.git"
    wsl -e bash -c "chmod o-w ~/my-backup-plan"

    # Checkout the desired branch (if needed)
    Write-Output "Checking out 'multi-os' branch..."
    wsl -e bash -c "cd ~/my-backup-plan && git checkout multi-os"

    # Run the Ansible backup plan
    Write-Output "Running Ansible backup plan..."
    wsl -e bash -c "cd ~/my-backup-plan && ansible-playbook ansible/playbooks/local_backup.yml"

} else {
    Write-Output "This script is designed for Windows 10 or later."
}