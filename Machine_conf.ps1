function Set-Name {
    param (
        [string]$PCName
    )

    Rename-Computer -NewName $PCName -Force 
}

function Validate-SubnetMask {
    param (
        [string]$SubnetMask
    )
    
    $subnetMasks = @{
        '255.255.0.0' = 16
    }

    return $subnetMasks[$SubnetMask]
}

function Change-InterfaceAlias {
    param (
        [string]$DesiredAlias = "inboard"
    )

    $interfaces = Get-NetAdapter | Select-Object -ExpandProperty Name
    $currentAlias = $interfaces | Where-Object { $_ -eq $DesiredAlias }

    if (-not $currentAlias) {
        try {
            $currentAlias = $interfaces | Select-Object -First 1
            Rename-NetAdapter -Name $currentAlias -NewName $DesiredAlias -PassThru
            Write-Output "Changed interface alias from $currentAlias to '$DesiredAlias'."
        } catch {
            Write-Warning "Failed to change interface alias: $_"
            return $null
        }
    }

    return $DesiredAlias
}

function Set-IPConfig {
    param (
        [string]$PCName,
        [string]$IPAddress,
        [string]$PrefixLengthOrSubnetMask,
        [string]$Gateway,
        [string[]]$DNSServers,
        [string]$InterfaceAlias
    )

    # Set the PC name
    Set-Name -PCName $PCName

    # Determine netmask
    $PrefixLength = if ($PrefixLengthOrSubnetMask -match '^\d+$') {
        [int]$PrefixLengthOrSubnetMask
    } else {
        Validate-SubnetMask -SubnetMask $PrefixLengthOrSubnetMask
    }

    if (-not $PrefixLength) {
        Write-Warning "Invalid Prefix Length or Subnet Mask: $PrefixLengthOrSubnetMask. Please provide a valid value."
        return $false
    }

    try {
        # Remove ip
        $existingIPs = Get-NetIPAddress -InterfaceAlias $InterfaceAlias
        foreach ($ip in $existingIPs) {
            Remove-NetIPAddress -IPAddress $ip.IPAddress -Confirm:$false
        }

        # Remove dns
        Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ResetServerAddresses

        # Set IP address/netmask
        New-NetIPAddress -InterfaceAlias $InterfaceAlias -IPAddress $IPAddress -PrefixLength $PrefixLength -DefaultGateway $Gateway -ErrorAction Stop

        # Set DNS
        Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses $DNSServers -ErrorAction Stop
    } catch {
        Write-Warning "An error occurred: $_"
        return $false
    }

    return $true
}

function Configure-IP {
    $interfaceAlias = Change-InterfaceAlias

    if (-not $interfaceAlias) {
        Write-Warning "Failed to set the interface alias to 'inboard'."
        return
    }

    $salle = Read-Host "Enter salle D" 
    $post = Read-Host "Enter post"
    $name = "D" + $salle + "-Po" + $post
    $newIPAddress = "10.0." + $salle + "." + $post
    $prefixLengthOrSubnetMask = "255.255.0.0"
    $newGateway = "10.0.255.254"
    $dnsInput = "10.0.0.11"
    $dnsServers = $dnsInput -split ',\s*'

    if (Set-IPConfig -PCName $name -IPAddress $newIPAddress -PrefixLengthOrSubnetMask $prefixLengthOrSubnetMask -Gateway $newGateway -DNSServers $dnsServers -InterfaceAlias $interfaceAlias) {
        # Verify changes
        $hostname = hostname
        $interface = Get-NetIPConfiguration | Where-Object { $_.InterfaceAlias -eq $interfaceAlias }

        Write-Output "-----------------------------------------------"
        Write-Output "IP Configuration has been set successfully:"
        Write-Output "PC Name: $hostname"
        Write-Output "IP Address: $newIPAddress"
        Write-Output "Netmask/Prefix Length: $prefixLengthOrSubnetMask"
        Write-Output "Gateway: $newGateway"
        Write-Output "DNS: $($dnsServers -join ', ')"
        Write-Output "Interface Alias: $interfaceAlias"
        Write-Output "-----------------------------------------------"
    } else {
        Write-Warning "Failed to set IP configuration."
    }
}

function Join-Domain {
    param (
        [string]$DomainName,
        [string]$DomainUser,
        [string]$DomainPassword,
        [string]$OU = ""
    )

    $securePassword = ConvertTo-SecureString $DomainPassword -AsPlainText -Force
    try {
        if ($OU) {
            Add-Computer -DomainName $DomainName -Credential (New-Object System.Management.Automation.PSCredential($DomainUser, $securePassword)) -OUPath $OU -ErrorAction Stop
        } else {
            Add-Computer -DomainName $DomainName -Credential (New-Object System.Management.Automation.PSCredential($DomainUser, $securePassword)) -ErrorAction Stop
        }
        Write-Output "Successfully joined the domain $DomainName."
        Restart-Computer -Force
    } catch {
        Write-Warning "An error occurred: $_"
    }
}

function Install-Chocolatey {
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
        Write-Output "Chocolatey installation completed successfully."
    } catch {
        Write-Warning "An error occurred during Chocolatey installation: $_"
    }
}

function Main-Menu {
    Write-Output "Choose an operation:"
    Write-Output "1. Configure IP and Set PC Name"
    Write-Output "2. Join Domain"
    Write-Output "3. Install Chocolatey"

    $choice = Read-Host "Enter your choice (1, 2, or 3)"

    switch ($choice) {
        1 {
            Configure-IP
        }
        2 {
            $domainName = "estransup.local"
            $domainUser = Read-Host "Enter the domain user"
            $domainPassword = Read-Host "Enter the domain password"
            Join-Domain -DomainName $domainName -DomainUser $domainUser -DomainPassword $domainPassword 
        }
        3 {
            Install-Chocolatey
        }
        default {
            Write-Output "Invalid choice. Please run the script again and select a valid option."
        }
    }
}

# Display the main 
Main-Menu
