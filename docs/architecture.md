# Architecture de l'infrastructure hybride

## 1. Vue d'ensemble

Mon infrastructure repose sur un **Dell Latitude 5490 dédié**, sur lequel j'ai installé **VMware ESXi 8 directement sur le matériel**.

L'environnement regroupe des machines virtuelles Windows Server et Ubuntu Server, réparties sur plusieurs réseaux virtuels. Une machine virtuelle OPNsense assure le routage, le filtrage entre les VLAN et les connexions VPN.

L'infrastructure locale est également reliée à une machine virtuelle Linux hébergée sur Microsoft Azure à travers un tunnel WireGuard.

Les principaux services déployés sont :

- Active Directory et DNS pour la gestion centralisée des identités ;
- deux serveurs Linux intégrés au domaine Active Directory ;
- Centreon pour la supervision ;
- Veeam pour les sauvegardes et les restaurations ;
- Ansible et Rundeck pour l'administration et l'automatisation ;
- OPNsense et WireGuard pour la segmentation réseau et les accès VPN.

## 2. Infrastructure physique et virtualisation

### Serveur physique

| Élément | Configuration |
| --- | --- |
| Matériel | Dell Latitude 5490 |
| Hyperviseur | VMware ESXi 8 |
| Installation | Bare metal |
| Environnement | Homelab personnel |

L'ensemble des machines virtuelles locales s'exécute sur cet hôte ESXi.

Cette architecture permet de travailler sur une infrastructure complète avec un seul équipement physique. Elle présente néanmoins une limite : **l'hôte constitue un point de défaillance unique**.

### Réseaux virtuels ESXi

Deux réseaux virtuels remplissent des fonctions distinctes :

**`vSwitch0` — connexion au réseau physique**

Ce commutateur virtuel utilise la liaison physique vers le réseau domestique. Il permet notamment de raccorder l'interface WAN d'OPNsense au réseau amont.

**`vSwitch-Lab-Interne` — réseau interne du lab**

Ce commutateur virtuel ne possède pas de liaison physique directe vers le réseau domestique. Il accueille les réseaux des machines virtuelles du lab.

La communication entre les VLAN internes et les réseaux extérieurs passe par OPNsense.

## 3. Segmentation réseau

J'ai organisé les machines virtuelles en quatre VLAN afin de séparer les fonctions de l'infrastructure.

| VLAN | Zone | Services |
| --- | --- | --- |
| 10 | Management | Windows Server 2022, Active Directory, DNS |
| 20 | Serveurs | Deux machines virtuelles Ubuntu Server 24.04 |
| 30 | Supervision et sauvegarde | Centreon, Veeam Backup & Replication |
| 40 | Administration | Ansible, Rundeck |

Le réseau interne est organisé en quatre VLAN, chacun correspondant à un ensemble de services. Leurs communications passent par OPNsense, qui applique les règles de filtrage entre les zones.

Le plan d'adressage, les protocoles et les règles de pare-feu seront détaillés séparément dans la documentation réseau.

### Rôle d'OPNsense

OPNsense assure plusieurs fonctions :

- passerelle des réseaux internes ;
- routage entre les VLAN ;
- filtrage des communications par des règles de pare-feu ;
- accès aux ressources extérieures selon les règles configurées ;
- terminaison des tunnels WireGuard.

Les flux nécessaires au fonctionnement des services sont autorisés entre les zones concernées.

## 4. Machines virtuelles et services

### VLAN 10 — Active Directory et DNS

Un serveur **Windows Server 2022** assure les rôles suivants :

- contrôleur de domaine Active Directory ;
- serveur DNS du domaine ;
- gestion des comptes et groupes utilisés dans le lab.

Ce contrôleur de domaine est également utilisé pour l'intégration des machines Linux à l'annuaire.

Le lab utilise actuellement **un seul contrôleur de domaine**.

### VLAN 20 — Serveurs Linux

Deux machines virtuelles **Ubuntu Server 24.04** sont intégrées au domaine Active Directory.

L'intégration repose notamment sur :

- `realmd` pour la jonction au domaine ;
- `SSSD` pour la résolution des identités et l'authentification ;
- les groupes Active Directory pour contrôler les autorisations ;
- `sudo` pour la délégation des droits d'administration.

Les tests réalisés comprennent l'authentification avec un compte du domaine et la vérification des droits d'administration.

### VLAN 30 — Supervision et sauvegarde

**Centreon**

Centreon supervise les principaux systèmes et équipements du lab. Selon les cibles, la collecte repose sur NRPE, NSClient++ ou SNMP.

**Veeam**

Veeam Backup & Replication et les agents de sauvegarde assurent la protection de plusieurs machines Windows et Linux.

Un dépôt de sauvegarde est installé sur un support de stockage distinct, mais il reste situé sur **le même équipement physique que l'hyperviseur**. Il ne constitue donc pas une sauvegarde hors site.

### VLAN 40 — Administration et automatisation

Cette zone regroupe les outils d'administration.

**Ansible** est utilisé pour automatiser des configurations Linux, notamment des opérations liées à l'intégration au domaine et à la synchronisation horaire.

**Rundeck** fournit une interface pour déclencher et organiser certaines opérations d'administration.

Des scripts **PowerShell** complètent l'automatisation des opérations liées à Windows et Active Directory.

## 5. Connexion à Microsoft Azure

Une machine virtuelle **Ubuntu 22.04** est déployée dans Microsoft Azure.

Elle communique avec l'infrastructure locale au moyen d'un **tunnel WireGuard site-à-site**, terminé sur OPNsense.

Cette liaison permet de tester des communications entre l'environnement virtualisé local et une ressource hébergée dans le cloud.

L'accès SSH public direct à la machine Azure est fermé ; son administration s'effectue par la connectivité VPN prévue à cet effet.

## 6. Accès d'administration à distance

Les postes utilisés pour administrer le lab peuvent se connecter à OPNsense à travers un tunnel WireGuard.

Cet accès est distinct de la liaison site-à-site vers Azure.

Une fois le VPN établi, les communications vers les différentes zones internes restent soumises aux règles du pare-feu.

## 7. Principaux flux techniques

| Source | Destination | Utilisation |
| --- | --- | --- |
| Serveurs Linux | Contrôleur de domaine | DNS, intégration au domaine et authentification |
| Serveur d'administration | Serveurs Linux | Automatisation avec Ansible |
| Centreon | Systèmes supervisés | Collecte des états et métriques |
| Composants Veeam | Machines sauvegardées | Sauvegarde et restauration |
| Postes d'administration | OPNsense puis VLAN autorisés | Administration à distance |
| Réseau local | VM Azure | Communication via WireGuard |

Ce tableau présente les **communications fonctionnelles**. Il ne remplace pas un inventaire détaillé des règles de pare-feu, des protocoles et des ports utilisés.

## 8. Limites de l'architecture

L'infrastructure est un environnement personnel de test et d'apprentissage, pas une plateforme de production.

Ses principales limites sont :

- un seul hôte ESXi ;
- un seul contrôleur de domaine Active Directory ;
- des sauvegardes conservées localement, sans copie hors site ;
- une capacité matérielle limitée pour déployer davantage de services simultanément.

Ces contraintes font partie des éléments pris en compte dans l'organisation et les tests du lab.

## 9. Vérification de l'infrastructure

Les différents composants ont été vérifiés à travers des tests de connectivité, d'authentification, d'administration et de restauration.

Les documents du dépôt présenteront les configurations mises en œuvre, les commandes utilisées pour les vérifier et les résultats observés.

Les scripts, extraits de configuration et captures d'écran seront sélectionnés pour illustrer les opérations réellement effectuées sur le lab.

## 10. Évolutions de la documentation

Les autres fichiers du dépôt détailleront progressivement :

- la configuration de la virtualisation et des réseaux virtuels ;
- les règles réseau, le pare-feu et les tunnels VPN ;
- l'intégration Linux à Active Directory ;
- les playbooks et scripts d'automatisation ;
- la supervision ;
- les sauvegardes et les tests de restauration ;
- la connectivité Azure ;
- les incidents rencontrés et leur résolution.
