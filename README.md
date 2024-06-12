## Objectif

- Pouvoir changer le nom de la machine
- Modifier IP/Netmask/Passerelle/DNS
- Joindre un domaine
- Installer Chocolatey

## Lien des scripts

Script de configuration : https://github.com/Skream20/script-Conf/blob/2d00d0a1b5d0c784136888bacfd4874842ed3d64/Machine_conf.ps1


Script d'activation AD/AAD : https://github.com/Skream20/script-Conf/blob/2d00d0a1b5d0c784136888bacfd4874842ed3d64/DesyncAD.psi

## Fonctionnement du script

### Set-Name

- **Fonction** : Renomme l'ordinateur.
- **Paramètre** : `$PCName` (nouveau nom de l'ordinateur).
- **Action** : Utilise `Rename-Computer` pour changer le nom de l'ordinateur en utilisant le nom fourni.

```powershell
function Set-Name {
    param (
        [string]$PCName
    )

    Rename-Computer -NewName $PCName -Force
}
```

### Validate-SubnetMask

- **Fonction** : Valide le masque de sous-réseau fourni.
- **Paramètre** : `$SubnetMask` (masque de sous-réseau sous forme de chaîne).
- **Action** : Vérifie si le masque de sous-réseau fourni correspond à un masque valide et retourne la longueur du préfixe correspondante (actuellement, seulement 255.255.0.0 est supporté).

```powershell
function Validate-SubnetMask {
    param (
        [string]$SubnetMask
    )

    $subnetMasks = @{
        '255.255.0.0' = 16
    }

    return $subnetMasks[$SubnetMask]
}
```

### Change-InterfaceAlias

- **Fonction** : Change l'alias de l'interface réseau.
- **Paramètre** : `$DesiredAlias` (nouvel alias désiré, par défaut "inboard").
- **Action** : Vérifie et renomme l'alias de la première interface réseau trouvée s'il ne correspond pas déjà au nouvel alias désiré.

```powershell
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
```

### Set-IPConfig

- **Fonction** : Configure les paramètres réseau de l'ordinateur.
- **Paramètres** : `$PCName`, `$IPAddress`, `$PrefixLengthOrSubnetMask`, `$Gateway`, `$DNSServers`, `$InterfaceAlias`.
- **Action** :
    - Renomme l'ordinateur.
    - Détermine la longueur du préfixe à partir du masque de sous-réseau ou de la longueur du préfixe fournie.
    - Supprime les adresses IP et les serveurs DNS existants de l'interface.
    - Configure la nouvelle adresse IP, la passerelle et les serveurs DNS sur l'interface.

```powershell
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
        # Remove IP
        $existingIPs = Get-NetIPAddress -InterfaceAlias $InterfaceAlias
        foreach ($ip in $existingIPs) {
            Remove-NetIPAddress -IPAddress $ip.IPAddress -Confirm:$false
        }

        # Remove DNS
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
```

### Configure-IP

- **Fonction** : Demande les informations réseau à l'utilisateur et configure l'IP de l'ordinateur.
- **Action** :
    - Change l'alias de l'interface réseau.
    - Demande à l'utilisateur les informations de la salle et du poste.
    - Construit les paramètres réseau à partir des informations fournies.
    - Appelle `Set-IPConfig` pour configurer l'ordinateur avec les nouvelles informations.

```powershell
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
```

### Join-Domain

- **Fonction** : Ajoute l'ordinateur à un domaine.
- **Paramètres** : `$DomainName`, `$DomainUser`, `$DomainPassword`, `$OU` (optionnel).
- **Action** : Utilise `Add-Computer` pour ajouter l'ordinateur au domaine spécifié en utilisant les informations d'authentification fournies, puis redémarre l'ordinateur.

```powershell
function Join-Domain {
    param (
        [string]$DomainName,
        [string]$DomainUser,
        [string]$DomainPassword,
        [string]$OU = ""
    )

    $securePassword = ConvertTo-SecureString $DomainPassword -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($DomainUser, $securePassword)

    try {
        if ($OU) {
            Add-Computer -DomainName $DomainName -Credential $credential -OUPath $OU -ErrorAction Stop
        } else {
            Add-Computer -DomainName $DomainName -Credential $credential -ErrorAction Stop
        }
        Restart-Computer -Force
    } catch {
        Write-Warning "An error occurred: $_"
    }
}
```

### Install-Chocolatey

- **Fonction** : Installe Chocolatey, un gestionnaire de paquets pour Windows.
- **Action** : Modifie la politique d'exécution des scripts et télécharge/installe Chocolatey.

```powershell
function Install-Chocolatey {
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('<https://community.chocolatey.org/install.ps1>'))
}
```

### Main-Menu

- **Fonction** : Menu principal pour choisir l'opération à effectuer.
- **Action** :
    - Affiche les options disponibles à l'utilisateur.
    - Demande à l'utilisateur de choisir

 une option.
    - Appelle la fonction correspondante en fonction du choix de l'utilisateur (Configurer IP, rejoindre un domaine ou installer Chocolatey).

```powershell
function Main-Menu {
    while ($true) {
        Write-Output "Select an option:"
        Write-Output "1. Configure IP"
        Write-Output "2. Join Domain"
        Write-Output "3. Install Chocolatey"
        Write-Output "4. Exit"

        $choice = Read-Host "Enter your choice (1/2/3/4)"

        switch ($choice) {
            1 { Configure-IP }
            2 {
                $domainName = "estransup.local"
                $domainUser = Read-Host "Enter Domain User"
                $domainPassword = Read-Host "Enter Domain Password"
                $ou = Read-Host "Enter OU (optional, press enter to skip)"
                Join-Domain -DomainName $domainName -DomainUser $domainUser -DomainPassword $domainPassword -OU $ou
            }
            3 { Install-Chocolatey }
            4 { break }
            default { Write-Warning "Invalid choice, please try again." }
        }
    }
}

Main-Menu
```

## Problème / Solution

### Impossibilité de connexion au domaine

```
AVERTISSEMENT : An error occurred: L'ordinateur « hj » 
n'a pas pu joindre le domaine « estransup.local » 
à partir de son groupe de travail actuel « WORKGROUP » avec le message 
d'erreur suivant : Cet appareil est joint à Azure AD. 
Pour joindre un domaine Active Directory, 
vous devez d'abord accéder aux paramètres 
et déconnecter votre appareil de votre réseau professionnel ou scolaire.
```

💡 Solution :

Le responsable de cette erreur est le service Azure Active Directory et Service Azure Directory sur Windows 11 mis en place de façon automatique. Pour modifier le domaine, il faut donc désactiver le service AAD puis “unjoin” de Azure AD.

Le script ci-dessous désactive et “unjoin” du service AD :

```powershell
# Disable AAD-related services
Invoke-Command -ScriptBlock {
    $services = @(
        "DsmSvc",    # User Device Registration
        "wlidsvc"    # Microsoft Account Sign-in Assistant
    )
    foreach ($service in $services) {
        try {
            Set-Service -Name $service -StartupType Disabled -ErrorAction Stop
            Stop-Service -Name $service -Force -ErrorAction Stop
            Write-Output "Service $service has been disabled and stopped."
        } catch {
            Write-Warning "Failed to disable or stop service $service: $_"
        }
    }
}

# Unjoin the device from Azure AD
Invoke-Command -ScriptBlock {
    $aadJoined = (Get-WmiObject -Namespace "root\cimv2\mdm\dmmap" -Class MDM_DevDetail_Ext01).IsAzureJoined
    if ($aadJoined) {
        dsregcmd /leave
        Write-Output "Device has been unjoined from Azure AD."
    } else {
        Write-Output "Device is not joined to Azure AD."
    }
}
```

1. **Désactiver et arrêter les services** :
    - Le script itère sur les services spécifiés (`DsmSvc` et `wlidsvc`).
    - Pour chaque service, il essaie de définir le type de démarrage sur `Disabled` et ensuite d'arrêter le service.
    - Les erreurs rencontrées durant ces opérations sont capturées et enregistrées en tant qu'avertissements.

2. **Désinscrire l'appareil d'Azure AD** :
    - Le script vérifie si l'appareil est actuellement inscrit à Azure AD en utilisant la cmdlet `Get-WmiObject`.
    - Si l'appareil est inscrit, il exécute `dsregcmd /leave` pour désinscrire l'appareil.
    - Les erreurs durant le processus de désinscription sont également capturées et enregistrées en tant qu'avertissements.
