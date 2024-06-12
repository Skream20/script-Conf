## Objectif:

- Pouvoir changer le nom de la machine
- Modifier IP/Netmask/Passerelle/DNS
- Joindre un domaine
- Installer Chocolatey

## lien des scriptes

## **Fonctionnement du script :**

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
