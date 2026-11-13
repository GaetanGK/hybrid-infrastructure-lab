# Automatisation — Ansible

## 1. Rôle dans le lab

Ansible est installé sur `ctrl-ansible`, dans le VLAN 40. Il est utilisé pour configurer les serveurs Linux du lab, notamment leur intégration à Active Directory. Les communications vers le VLAN 20 passent par OPNsense.

## 2. Intégration Linux à Active Directory

Le playbook [`iam-linux.yml`](../ansible/iam-linux.yml) automatise la jonction de `srv-lin-02` au domaine `homelab.local` et configure les accès des comptes AD. `srv-lin-01` a d'abord été intégré manuellement pour valider les étapes.

| Élément | Configuration |
| --- | --- |
| Serveur d'exécution | `ctrl-ansible` |
| Machine cible | `srv-lin-02` |
| Domaine | `homelab.local` |
| Outils | `realmd`, `SSSD`, `adcli` |
| Groupe autorisé | `linux-admins@homelab.local` |
| Délégation `sudo` | `/etc/sudoers.d/linux-admins` |

### Déroulement du playbook

1. Vérification du domaine de recherche DNS associé à `ens34` avec `resolvectl`.
2. Installation des paquets d'intégration AD.
3. Contrôle de la jonction existante avec `realm list`.
4. Jonction au domaine lorsque la machine n'en est pas membre.
5. Activation de la création automatique du répertoire personnel.
6. Restriction des connexions AD au groupe `linux-admins`.
7. Installation de la règle `sudo`, validée avec `visudo`.
8. Contrôle final de l'appartenance au domaine et des autorisations.

Le mot de passe de jonction est demandé à l'exécution. La tâche de jonction utilise `no_log: true`.

## 3. Incident DNS et Netplan

La première version du playbook tentait de modifier Netplan. Sur `srv-lin-02`, plusieurs définitions réseau concernaient la même interface et le domaine de recherche DNS n'était pas correctement appliqué. La jonction AD a échoué.

La configuration réseau a été corrigée sur la VM. Le playbook IAM vérifie maintenant le domaine DNS de l'interface et s'arrête si ce prérequis n'est pas respecté. Il ne modifie plus Netplan.

## 4. Vérifications

Après correction du réseau, `srv-lin-02` a rejoint le domaine. Les tests ont confirmé la connexion de `test-admin` et ses droits `sudo`, ainsi que le refus d'accès de `test-user` sur cette machine.

Les commandes et les vérifications des comptes sont détaillées dans [Active Directory et intégration Linux](active-directory.md).

## 5. Connectivité des machines

Depuis `ctrl-ansible`, la commande suivante a été exécutée avec l’inventaire local :

```bash
ansible all -i inventory.ini -m ping
```

Les quatre hôtes `ctrl-ansible`, `centreon-central`, `srv-lin-01` et `srv-lin-02` ont répondu `SUCCESS`. Ce module vérifie que la connexion Ansible et l’exécution Python fonctionnent sur les machines cibles ; il ne s’agit pas d’un ping ICMP.

## 6. Gestion de la synchronisation horaire

Le playbook [`configure-ntp.yml`](../ansible/configure-ntp.yml) gère un fichier de configuration `systemd-timesyncd` sur les groupes `linux_servers` et `supervision` :

| Paramètre | Valeur |
| --- | --- |
| Hôtes ciblés | `ctrl-ansible`, `centreon-central`, `srv-lin-01`, `srv-lin-02` |
| Service | `systemd-timesyncd` |
| Source NTP interne | `192.168.10.10` (`HOMELAB`) |
| Autre source configurée | `ntp.ubuntu.com` |
| Fichier géré | `/etc/systemd/timesyncd.conf.d/homelab.conf` |
| Application | Handler de redémarrage si le fichier change |

La configuration NTP a été déployée sur les quatre machines par ce playbook. Les contrôles décrits ci-dessous ont été réalisés après ce déploiement initial. La syntaxe du playbook a été validée avec `--syntax-check`. La commande `--list-hosts` a confirmé les quatre machines ciblées ; leur service `systemd-timesyncd` était actif et leur horloge synchronisée.

Le contrôle `--check --diff`, puis **deux exécutions réelles consécutives** du playbook, ont produit les mêmes compteurs sur chaque machine : `ok=3`, `changed=0`, `failed=0`, `unreachable=0`. Aucun redémarrage du service n’a été déclenché. Ces résultats valident l’idempotence du playbook : une configuration déjà conforme n’est pas modifiée.

Le contrôle `timedatectl timesync-status` a montré que trois machines utilisaient `192.168.10.10` comme source NTP active. `centreon-central` utilisait `ntp.ubuntu.com`, également présent dans sa configuration.

## 7. Captures d’écran

| Connectivité Ansible : quatre machines | Validation du playbook NTP |
| :---: | :---: |
| [<img src="../images/ansible/connectivite-machines.png" width="430" alt="Résultat SUCCESS du module ping Ansible sur quatre machines">](../images/ansible/connectivite-machines.png) | [<img src="../images/ansible/controle-ntp-check-mode.png" width="430" alt="Simulation Ansible du playbook NTP : changed=0 et failed=0 sur quatre machines">](../images/ansible/controle-ntp-check-mode.png) |

[<img src="../images/ansible/sources-ntp.png" width="650" alt="Contrôle des sources NTP sur les quatre machines Linux">](../images/ansible/sources-ntp.png)

## 8. Playbooks publiés

Les playbooks du dossier [`ansible/`](../ansible/) sont les versions exécutées depuis `ctrl-ansible`.

| Playbook | Cibles | Rôle |
| --- | --- | --- |
| [`setup-base.yml`](../ansible/setup-base.yml) | `linux_servers` | Mise à jour des paquets, outils de base, compte `devops` |
| [`iam-linux.yml`](../ansible/iam-linux.yml) | `srv-lin-02` | Jonction à Active Directory et droits `sudo` du groupe `linux-admins` |
| [`configure-ntp.yml`](../ansible/configure-ntp.yml) | `linux_servers`, `supervision` | Synchronisation horaire sur le contrôleur de domaine |
| [`install-nrpe.yml`](../ansible/install-nrpe.yml) | `linux_servers` | Installation de l'agent NRPE, accès limité au serveur Centreon |
| [`configure-nrpe-commands.yml`](../ansible/configure-nrpe-commands.yml) | `linux_servers` | Commandes de supervision : charge, disque, mémoire |
| [`install-check-mem.yml`](../ansible/install-check-mem.yml) | `linux_servers` | Installation du script de contrôle mémoire `check_mem` |

L'inventaire réel n'est pas publié ; [`inventory.example.ini`](../ansible/inventory.example.ini) en reprend la structure.

## 9. Améliorations identifiées

La relecture des playbooks a mis en évidence plusieurs points à corriger. Ils seront traités, testés dans le lab puis publiés :

- `install-nrpe.yml` et `configure-nrpe-commands.yml` redémarrent NRPE à chaque exécution. Un *handler* limiterait le redémarrage aux cas où la configuration change.
- `install-check-mem.yml` télécharge le script depuis la branche principale d'un dépôt tiers, sans version figée ni somme de contrôle. Il faudrait fixer une version précise et vérifier son empreinte.
- `setup-base.yml` met à niveau tous les paquets à chaque exécution, y compris sur `ctrl-ansible`. Les mises à jour relèvent plutôt d'un playbook dédié, lancé de façon planifiée et maîtrisée.
- `configure-ntp.yml` déclare `ntp.ubuntu.com` comme seconde source. `systemd-timesyncd` peut basculer sur cette source et y rester, ce qui expliquerait le comportement observé sur `centreon-central`. Cette hypothèse reste à vérifier avant de limiter la configuration aux sources du domaine.

## 10. Périmètre

Le playbook `iam-linux.yml` publié cible `srv-lin-02`. Il configure l'intégration AD et les droits associés. La supervision et l'orchestration des opérations sont assurées séparément par Centreon et Rundeck.

Voir [Orchestration — Rundeck](rundeck.md).
