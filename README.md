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
