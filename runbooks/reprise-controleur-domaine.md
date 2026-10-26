# PRA — Restauration du contrôleur de domaine Active Directory

## 1. Scénario testé

La machine virtuelle hébergeant Active Directory et DNS est arrêtée. Sa sauvegarde Veeam est restaurée sur **une nouvelle VM ESXi**, sans écraser la VM d'origine.

Le contrôleur est désigné `HOMELAB` dans la documentation du lab et `DC01` dans l'inventaire vSphere. La VM de test s'appelle `homelab-restore`.

**Condition de sécurité :** la VM d'origine et la VM restaurée possèdent la même identité Windows et utilisent la même adresse IP. Elles ne doivent jamais être connectées simultanément au réseau du lab.

## 2. Environnement utilisé

| Élément | Configuration |
| --- | --- |
| Hyperviseur | VMware ESXi 8 — Dell Latitude 5490 |
| Contrôleur de domaine | Windows Server 2022, AD DS et DNS |
| Adresse du contrôleur | `192.168.10.10`, VLAN 10 |
| Sauvegarde | Veeam Agent for Windows, stockée sur `veeam-01` |
| Méthode de reprise | Démarrage de `homelab-restore` sur un ISO Veeam Recovery Media |
| Datastore de restauration | `datastore-extension` |
| Disque de la VM testée | 60 Go |
| Démarrage | EFI avec Secure Boot |

La restauration a été lancée **depuis l'ISO de récupération**, et non depuis l'assistant de restauration de Veeam Backup & Replication.

## 3. Préparation et isolement

1. Vérifier la présence d'un point de restauration exploitable sur le dépôt Veeam.
2. Préparer la nouvelle VM `homelab-restore` avec un disque de capacité suffisante, sur un datastore disposant d'espace libre.
3. Monter l'ISO Veeam Recovery Media sur la VM de test.
4. Arrêter proprement `DC01` et confirmer son état hors tension.
5. Garder la carte réseau de `homelab-restore` déconnectée tant que l'arrêt de l'originale n'est pas confirmé.

Dans le test réalisé, `DC01` a été conservée intacte ; seule la VM de test a reçu les données restaurées.

## 4. Vérification de l'indisponibilité de l'annuaire

Après l'arrêt du contrôleur de domaine, les requêtes DNS vers `HOMELAB` ne répondaient plus. Sur un serveur Linux intégré au domaine, `sssctl domain-status` indiquait :

```text
Online status: Offline
```

Une session SSH a néanmoins fonctionné avec un compte AD déjà connu de `SSSD`, grâce au cache local. Cette observation ne garantit pas que tous les comptes AD puissent se connecter lorsque l'annuaire est indisponible.

## 5. Restauration avec Veeam Recovery Media

1. Démarrer `homelab-restore` sur l'ISO Veeam.
2. Sélectionner le dépôt de sauvegarde Veeam comme source.
3. Récupérer le point de restauration de `HOMELAB`.
4. Associer les volumes sauvegardés au disque de la VM de restauration.
5. Lancer la restauration et attendre la fin du traitement.
6. Démarrer Windows depuis le disque restauré.

### Incident 1 — Carte réseau non détectée

Le média de récupération ne reconnaissait pas l'adaptateur **VMXNET 3** de la VM de test. L'adaptateur a été remplacé par **E1000E**, reconnu par l'environnement de récupération. L'accès au dépôt Veeam a alors pu être configuré.

### Incident 2 — Disque de destination absent

Veeam affichait :

```text
Unable to auto-match disks, please use manual restore mode
```

En mode manuel, aucun disque cible n'apparaissait. Le contrôleur **VMware Paravirtual** de la VM de test n'était pas pris en charge par le média de récupération utilisé.

Le disque a été rattaché à un contrôleur **SATA (AHCI)**. Il est alors devenu visible, l'association des volumes a fonctionné et la restauration s'est exécutée. Windows a ensuite démarré sur ce disque.

## 6. Remise en service du contrôleur restauré

Après le premier démarrage, la carte réseau E1000E était considérée par Windows comme une nouvelle interface et utilisait DHCP. L'adresse statique `192.168.10.10` a été réaffectée depuis la console de la VM restaurée.

Les contrôles sur le serveur restauré ont confirmé :

- les services `NTDS`, `DNS`, `KDC` et `Netlogon` démarrés ;
- la présence du compte de test Active Directory ;
- le fonctionnement de la résolution DNS ;
- la conservation de la configuration du service de temps Windows.

Depuis `srv-lin-01`, le DNS était de nouveau accessible. `SSSD` restait cependant en mode hors ligne après le retour de l'annuaire. Un redémarrage du service a rétabli son état :

```bash
sudo systemctl restart sssd
sssctl domain-status homelab.local
```

L'authentification SSH avec `test-admin@homelab.local` a réussi, avec le groupe `linux-admins` et les droits `sudo`. Ce test confirme le fonctionnement de l'annuaire restauré et son utilisation depuis Linux.

## 7. Retour à la VM d'origine

1. Arrêter `homelab-restore` et vérifier qu'elle n'est plus active sur le réseau.
2. Redémarrer la VM d'origine `DC01`.
3. Vérifier que l'adresse `192.168.10.10` correspond bien à l'interface réseau du contrôleur d'origine.
4. Contrôler les services AD DS, DNS, KDC et Netlogon.
5. Vérifier la disponibilité de l'annuaire depuis les machines Linux.
6. Redémarrer `sssd` sur les serveurs Linux restés hors ligne, puis tester l'authentification AD et `sudo`.

Pendant le test, le retour de `DC01` s'est terminé avec les services AD/DNS actifs. Les contrôles Linux ont de nouveau réussi après relance de `sssd`.

## 8. Points opérationnels

- Vérifier le média de récupération avec le matériel virtuel visé, notamment les pilotes réseau et stockage.
- Tester la reconnaissance du disque et l'accès au dépôt avant une restauration en situation d'urgence.
- Éviter toute coexistence réseau entre l'originale et une copie restaurée du contrôleur de domaine.
- Prévoir la réaffectation de l'adresse IP statique en cas de changement d'adaptateur réseau.
- Après restauration, vérifier les services AD/DNS **et** les authentifications réelles depuis les machines clientes.
- Le dépôt Veeam étant hébergé sur le même hôte physique, une défaillance totale de l'hôte n'est pas couverte par cette procédure.

Voir aussi [Sauvegardes — Veeam Backup & Replication](../docs/veeam.md) et [Active Directory et intégration Linux](../docs/active-directory.md).
