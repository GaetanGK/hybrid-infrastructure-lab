<#
.SYNOPSIS
    Prépare l'annuaire Active Directory du lab pour l'IAM Linux.

.DESCRIPTION
    Crée l'arborescence d'unités d'organisation (Lab, Serveurs-Linux, Utilisateurs, Groupes),
    le groupe de sécurité linux-admins et deux comptes de test (test-admin, test-user).
    test-admin est ajouté à linux-admins ; test-user n'appartient pas au groupe linux-admins et sert de
    comparaison pour vérifier que les droits dépendent bien de l'appartenance au groupe.

    Idempotent : chaque objet est vérifié avant d'être créé, le script peut être rejoué sans
    rien dupliquer.
    Aucun mot de passe n'est stocké : ils sont demandés à l'exécution (SecureString).

.NOTES
    À exécuter sur le contrôleur de domaine, avec un compte administrateur du domaine.
    Les unités d'organisation sont protégées contre la suppression accidentelle : pour en
    supprimer une, retirer d'abord cette protection (Set-ADOrganizationalUnit
    -ProtectedFromAccidentalDeletion $false).
#>

$ErrorActionPreference = 'Stop'
$domain = Get-ADDomain
$dn = $domain.DistinguishedName

function Ensure-OU($name, $path) {
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$name'" -SearchBase $path -SearchScope OneLevel -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $name -Path $path -ProtectedFromAccidentalDeletion $true
        "OU créée : $name"
    } else { "OU déjà présente : $name" }
}

# Arborescence
Ensure-OU 'Lab' $dn
$lab = "OU=Lab,$dn"
Ensure-OU 'Serveurs-Linux' $lab
Ensure-OU 'Utilisateurs'   $lab
Ensure-OU 'Groupes'        $lab

# Groupe des administrateurs Linux (recevra le droit sudo côté Linux)
if (-not (Get-ADGroup -Filter "Name -eq 'linux-admins'")) {
    New-ADGroup -Name 'linux-admins' -GroupScope Global -GroupCategory Security -Path "OU=Groupes,$lab" -Description 'Administrateurs des serveurs Linux (sudo)'
    "Groupe créé : linux-admins"
} else { "Groupe déjà présent : linux-admins" }

# Comptes de test : les mots de passe sont saisis à l'exécution
foreach ($u in 'test-admin', 'test-user') {
    if (-not (Get-ADUser -Filter "SamAccountName -eq '$u'")) {
        $pw = Read-Host "Mot de passe pour $u" -AsSecureString
        New-ADUser -Name $u -SamAccountName $u -UserPrincipalName "$u@$($domain.DNSRoot)" -Path "OU=Utilisateurs,$lab" -AccountPassword $pw -Enabled $true
        "Utilisateur créé : $u"
    } else { "Utilisateur déjà présent : $u" }
}

# test-admin devient administrateur Linux ; test-user reste hors du groupe linux-admins
if ((Get-ADGroupMember -Identity 'linux-admins').SamAccountName -notcontains 'test-admin') {
    Add-ADGroupMember -Identity 'linux-admins' -Members 'test-admin'
    "test-admin ajouté à linux-admins"
}
