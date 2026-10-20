# Réseau et sécurité — OPNsense et WireGuard

## 1. Rôle d'OPNsense

J'utilise OPNsense comme routeur et pare-feu principal de mon infrastructure.

Il assure le routage inter-VLAN, le NAT sortant vers Internet et la terminaison des tunnels WireGuard.

Les réseaux internes sont organisés selon les fonctions des machines : Active Directory, serveurs Linux, supervision, sauvegarde et administration.

Leur répartition et leur configuration dans ESXi sont présentées dans les documents [Architecture](architecture.md) et [Virtualisation](virtualisation.md).

Ce document se concentre sur le filtrage réseau, les accès VPN et les problèmes rencontrés lors de leur configuration.

## 2. Filtrage inter-VLAN

### Mise en place des règles

Après la création des VLAN, j'ai d'abord utilisé des règles permissives pour valider la connectivité entre les différentes zones.

J'ai ensuite progressivement restreint les communications en conservant les flux nécessaires au fonctionnement des services.

OPNsense utilise un **pare-feu stateful** : il suit l'état des connexions et autorise les paquets de réponse correspondant aux sessions établies.

L'objectif était de limiter les communications initiées entre les VLAN, sans perturber les services comme DNS, la synchronisation horaire ou les sauvegardes.

### Restriction du VLAN 20

J'ai notamment travaillé sur le filtrage du VLAN 20, qui héberge les deux serveurs Linux.

Les règles permettent de conserver :

- les requêtes DNS vers le contrôleur de domaine ;
- la synchronisation horaire ;
- les communications nécessaires aux sauvegardes Veeam ;
- l'accès Internet pour les mises à jour système.

Les autres connexions non autorisées vers les réseaux privés sont bloquées.

Pour éviter de créer une règle distincte pour chaque réseau de destination, j'ai utilisé un alias OPNsense regroupant les réseaux privés concernés.

### Vérification du filtrage

Depuis `srv-lin-01`, j'ai vérifié que :

- l'accès SSH au contrôleur de domaine était bloqué ;
- l'accès SSH au serveur Ansible/Rundeck était bloqué ;
- l'interface web d'ESXi n'était plus accessible ;
- la résolution DNS et l'accès Internet fonctionnaient toujours ;
- les communications nécessaires à Veeam restaient autorisées.

Ces tests ont permis de vérifier à la fois les restrictions appliquées et le maintien des services nécessaires.

## 3. Incident : règle de pare-feu appliquée trop largement

Pendant le durcissement du VLAN 20, une règle destinée à bloquer les communications vers les réseaux privés a provoqué une perte de connectivité sur plusieurs services.

### Symptômes

La règle ne concernait pas uniquement les serveurs Linux. Elle bloquait également de nouvelles connexions provenant d'autres réseaux.

Les effets observés comprenaient notamment :

- une interruption de nouvelles connexions WireGuard ;
- une perte d'accès à certaines interfaces d'administration ;
- le blocage de flux qui ne provenaient pas du VLAN 20.

Le problème est apparu progressivement, car les connexions déjà établies continuaient temporairement de fonctionner grâce à la table d'états du pare-feu.

### Diagnostic

J'ai commencé par vérifier que les paquets arrivaient sur l'interface WAN d'OPNsense.

J'ai ensuite utilisé `tcpdump` pour examiner les événements de filtrage et identifier la règle responsable.

```bash
tcpdump -ni vmx1
tcpdump -nei pflog0 udp port 51820
```

L'inspection des règles réellement chargées avec la commande suivante a permis d'identifier le problème :

```bash
pfctl -vvsr
```

La règle de blocage ne comportait ni l'interface ni la source attendues.

Elle s'appliquait donc à un périmètre beaucoup plus large que celui initialement prévu.

### Rétablissement des accès

Pour rétablir temporairement la connectivité, j'ai vidé en mémoire la table d'adresses associée à la règle concernée.

Cette intervention était temporaire : elle ne supprimait pas la règle de la configuration persistante, et un rechargement du pare-feu pouvait rétablir le blocage.

J'ai ensuite supprimé puis recréé les règles concernées.

### Second problème : ordre d'évaluation des règles

Après cette correction, les nouvelles règles ciblaient correctement le VLAN 20, mais les tests montraient que certaines connexions restaient autorisées.

En examinant les compteurs et l'ordre des règles avec `pfctl`, j'ai constaté que les règles de blocage n'étaient pas évaluées avant une règle générale d'autorisation déjà présente.

J'ai corrigé leur placement en utilisant des **règles flottantes (*floating rules*)**, avec une source explicitement définie.

Les règles nécessaires aux services autorisés sont placées avant le blocage général des autres destinations privées.

### Validation

Après correction, j'ai effectué de nouveaux tests depuis le VLAN 20 et vérifié le retour des accès d'administration concernés.

Les connexions interdites étaient bloquées, tandis que les communications nécessaires au fonctionnement des services restaient accessibles.

Cet incident m'a conduit à vérifier systématiquement la portée, l'ordre d'évaluation et les compteurs des règles réellement chargées dans le pare-feu, plutôt que de me fier uniquement à leur affichage dans l'interface web.

## 4. Accès distant avec WireGuard

J'ai déployé WireGuard sur OPNsense pour administrer le lab à distance, sans exposer directement les interfaces d'administration sur Internet.

Le trafic passe par la Freebox, qui redirige les connexions VPN vers l'interface WAN d'OPNsense. Une fois le tunnel établi, les règles du pare-feu déterminent les réseaux internes accessibles.

J'utilise deux **peers WireGuard**, un pour chaque poste d'administration. Chaque peer possède sa propre paire de clés et son adresse IP de tunnel.

### Incident : chevauchement des Allowed IPs

Lors de l'ajout des VLAN aux réseaux accessibles par VPN, j'ai rencontré un problème de connectivité lié à la configuration des `Allowed IPs`.

Les deux peers côté OPNsense partageaient les mêmes réseaux internes dans leur configuration. Ce chevauchement provoquait un conflit d'association des routes aux peers.

### Diagnostic

J'ai procédé par étapes :

- vérification du **handshake** WireGuard ;
- capture du trafic UDP entrant sur l'interface WAN ;
- contrôle du trafic sur l'interface WireGuard ;
- consultation de l'état des peers avec `wg show` ;
- comparaison avec la configuration enregistrée dans OPNsense.

La commande `wg show` affichait notamment `allowed ips: (none)` pour un peer, alors que des réseaux étaient définis dans l'interface de configuration.

### Correction

J'ai corrigé les `Allowed IPs` côté OPNsense en attribuant à chaque peer uniquement son adresse de tunnel en `/32`.

Les réseaux internes à joindre par le VPN restent définis dans les `Allowed IPs` des clients.

Cette séparation évite le chevauchement entre les peers. Les règles du pare-feu OPNsense continuent de contrôler les flux autorisés vers les différents VLAN.

Les deux postes conservent ainsi une configuration VPN indépendante, avec leur propre identité cryptographique.

## 5. Liaison avec Microsoft Azure

J'ai également mis en place un tunnel WireGuard site-à-site entre OPNsense et une machine virtuelle Ubuntu hébergée dans Microsoft Azure.

Ce tunnel est distinct du VPN utilisé pour les postes d'administration.

Il permet d'établir des communications entre l'infrastructure locale et la machine Azure, selon les routes et les règles de filtrage configurées.

L'administration de la VM Azure s'effectue à travers le VPN, sans exposition directe du service SSH sur Internet.

Les détails de la configuration Azure seront présentés dans `docs/cloud-azure.md`.

## 6. Vérifications et outils de diagnostic

Pour diagnostiquer les problèmes réseau et vérifier les configurations, j'ai utilisé plusieurs outils.

| Outil / commande | Utilisation |
| --- | --- |
| `ping` | Vérification de la connectivité IP |
| `ip route` | Contrôle des routes sur les serveurs Linux |
| `tcpdump` | Capture et analyse du trafic réseau |
| `pfctl -vvsr` | Inspection des règles réellement chargées par le pare-feu |
| `wg show` | Vérification des peers, des handshakes et des Allowed IPs |
| Journaux OPNsense | Identification des connexions autorisées ou bloquées |

Les tests portent autant sur les communications autorisées que sur celles qui doivent être bloquées.

## 7. Captures d'écran

Ces captures présentent la configuration du lab au moment de leur réalisation. Cliquez sur une miniature pour ouvrir l'image complète.

| Interfaces VLAN | Règles de filtrage |
| :---: | :---: |
| [<img src="../images/opnsense/interfaces-vlan.png" width="320" alt="Interfaces VLAN OPNsense">](../images/opnsense/interfaces-vlan.png) | [<img src="../images/opnsense/regles-pare-feu.png" width="320" alt="Règles de filtrage OPNsense">](../images/opnsense/regles-pare-feu.png) |

| Peers WireGuard | Statut WireGuard |
| :---: | :---: |
| [<img src="../images/opnsense/peers-wireguard.png" width="320" alt="Peers WireGuard">](../images/opnsense/peers-wireguard.png) | [<img src="../images/opnsense/statut-wireguard.png" width="320" alt="État des tunnels WireGuard">](../images/opnsense/statut-wireguard.png) |

## 8. Limites et évolutions prévues

### Limites actuelles

Le routage inter-VLAN et les VPN reposent sur une seule instance OPNsense hébergée sur l'hôte ESXi du lab.

Une indisponibilité de cet hôte ou du pare-feu entraîne donc une interruption des communications qui en dépendent.

### Mise en place d'un serveur bastion

Actuellement, les postes d'administration accèdent aux ressources internes à travers WireGuard, selon les règles de filtrage configurées dans OPNsense.

Une prochaine évolution consistera à déployer un **serveur bastion dans le VLAN 40**, dédié à l'administration.

L'objectif sera de centraliser les connexions vers les serveurs Windows et Linux, de réduire les accès directs depuis les postes distants et d'améliorer la traçabilité des sessions d'administration.

WireGuard restera le moyen d'accès distant au lab. Le bastion constituera un point de passage supplémentaire vers les machines internes.

Cette évolution est prévue, mais n'est pas encore déployée.
