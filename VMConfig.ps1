#Requires -RunAsAdministrator
# ==============================================================================
# 1. CONFIGURATION
# Note: Switch does not provide DHCP for NAT. Clients can be statically configured.
# ==============================================================================
$LabRoot = "C:\HyperVLab"
$SwitchName = "Lab-NAT-Switch"
$NATName = "Lab-NAT-Network"
$SubnetPrefix = "192.168.100.0/24"
$GatewayIP = "192.168.100.1"

# Update these paths to point to your downloaded ISOs
$Win11IsoPath = "C:\ISOs\Win11-26H2.iso"
$UbuntuIsoPath = "C:\ISOs\ubuntu-26.04.1-desktop-amd64.iso"

# The following two lines will return True if files exist
Test-Path $Win11IsoPath
Test-Path $UbuntuIsoPath

# ==============================================================================
# 2. CREATE DIRECTORY STRUCTURE
# ==============================================================================
Write-Host "[1/5] Creating lab directories at $LabRoot..." -ForegroundColor Cyan


New-Item -Path "$LabRoot\VMs" -ItemType Directory -Force | Out-Null
New-Item -Path "$LabRoot\VHDs" -ItemType Directory -Force | Out-Null

# ==============================================================================
# 3. CONFIGURE INTERNAL NAT VIRTUAL SWITCH
# ==============================================================================
Write-Host "[2/5] Configuring Internal NAT Switch ($SwitchName)..." -ForegroundColor Cyan

# Create VMSwitch
if (-not (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue)) {
    New-VMSwitch -SwitchName $SwitchName -SwitchType Internal | Out-Null
}

# Assign IP address to network adapter associated with the new virtual switch.
# The host computer will use this IP address to communicate with VMs
$NetAdapter = Get-NetAdapter | Where-Object { $_.Name -like "*$SwitchName*" }
if (-not (Get-NetIPAddress -InterfaceIndex $NetAdapter.ifIndex -IPAddress $GatewayIP -ErrorAction SilentlyContinue)) {
    New-NetIPAddress -IPAddress $GatewayIP -PrefixLength 24 -InterfaceIndex $NetAdapter.ifIndex | Out-Null
}

if (-not (Get-NetNat -Name $NATName -ErrorAction SilentlyContinue)) {
    New-NetNat -Name $NATName -InternalIPInterfaceAddressPrefix $SubnetPrefix | Out-Null
}

# Allows you to view the virtual NIC created and configured
Get-NetIPAddress -InterfaceIndex $NetAdapter.ifIndex

# ==============================================================================
# 4. PROVISION WINDOWS 11 VM
# ==============================================================================
$WinVMName = "Lab-Win11"
Write-Host "[3/5] Provisioning $WinVMName..." -ForegroundColor Cyan

if (-not (Get-VM -Name $WinVMName -ErrorAction SilentlyContinue)) {
    if (-not (Test-Path $Win11IsoPath)) {
        Write-Warning "Windows 11 ISO not found at $Win11IsoPath. VM will be created without media."
    }

    New-VM -Name $WinVMName `
        -MemoryStartupBytes 4GB `
        -Generation 2 `
        -NewVHDPath "$LabRoot\VHDs\$WinVMName.vhdx" `
        -NewVHDSizeBytes 64GB `
        -Path "$LabRoot\VMs" `
        -SwitchName $SwitchName | Out-Null

    # Hardware & Security Requirements for Windows 11
    Set-VMProcessor -VMName $WinVMName -Count 4
    Set-VMMemory -VMName $WinVMName -DynamicMemoryEnabled $true -MinimumBytes 2GB -MaximumBytes 8GB
    Set-VMFirmware -VMName $WinVMName -EnableSecureBoot On -SecureBootTemplate "MicrosoftWindows"

    # Enable Virtual TPM (Required for Win11)
    Set-VMKeyProtector -VMName $WinVMName -NewLocalKeyProtector
    Enable-VMTPM -VMName $WinVMName

    # Disable Automatic Checkpoints to save disk space
    Set-VM -Name $WinVMName -AutomaticCheckpointsEnabled $false

    # Attach ISO and set as primary boot device
    if (Test-Path $Win11IsoPath) {
        $WinDVD = Add-VMDvdDrive -VMName $WinVMName -Path $Win11IsoPath -Passthru
        Set-VMFirmware -VMName $WinVMName -FirstBootDevice $WinDVD
    }
} else {
    Write-Host " -> '$WinVMName' already exists. Skipping." -ForegroundColor Yellow
}

# ==============================================================================
# 5. PROVISION UBUNTU VM
# ==============================================================================
$UbuntuVMName = "Lab-Ubuntu"
Write-Host "[4/5] Provisioning $UbuntuVMName..." -ForegroundColor Cyan

if (-not (Get-VM -Name $UbuntuVMName -ErrorAction SilentlyContinue)) {
    if (-not (Test-Path $UbuntuIsoPath)) {
        Write-Warning "Ubuntu ISO not found at $UbuntuIsoPath. VM will be created without media."
    }

    New-VM -Name $UbuntuVMName `
        -MemoryStartupBytes 4GB `
        -Generation 2 `
        -NewVHDPath "$LabRoot\VHDs\$UbuntuVMName.vhdx" `
        -NewVHDSizeBytes 40GB `
        -Path "$LabRoot\VMs" `
        -SwitchName $SwitchName | Out-Null

    # Hardware & Linux UEFI Secure Boot Configuration
    Set-VMProcessor -VMName $UbuntuVMName -Count 2
    Set-VMMemory -VMName $UbuntuVMName -DynamicMemoryEnabled $true -MinimumBytes 2GB -MaximumBytes 6GB
    Set-VMFirmware -VMName $UbuntuVMName -EnableSecureBoot On -SecureBootTemplate "MicrosoftUEFICertificateAuthority"
    Set-VM -Name $UbuntuVMName -AutomaticCheckpointsEnabled $true

    # Attach ISO and set as primary boot device
    if (Test-Path $UbuntuIsoPath) {
        $UbuntuDVD = Add-VMDvdDrive -VMName $UbuntuVMName -Path $UbuntuIsoPath -Passthru
        Set-VMFirmware -VMName $UbuntuVMName -FirstBootDevice $UbuntuDVD
    }
} else {
    Write-Host " -> '$UbuntuVMName' already exists. Skipping." -ForegroundColor Yellow
}

# ==============================================================================
# 6. SUMMARY & LAUNCH
# ==============================================================================
Write-Host "[5/5] Lab deployment complete!" -ForegroundColor Green
Get-VM -Name "Lab-*" | Format-Table Name, State, Generation, ProcessorCount, @{Name="Memory(GB)";Expression={$_.MemoryStartup/1GB}}

Write-Host "Starting VMs and opening console connections..." -ForegroundColor Cyan
