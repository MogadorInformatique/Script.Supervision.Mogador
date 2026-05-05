***Commande a ajouter dans la tâche supervision***
```bash
#!/bin/bash
curl -sSfL https://raw.githubusercontent.com/MogadorInformatique/Script.Supervision.Mogador/main/DSM7_NAS.sh | bash
```

***Voire les logs du disque en question depuis le boot***
```bash
dmesg -T | grep -i sdq
```
OU

```bash
dmesg -T | grep -i "error\|fail\|critical\|I/O\|sdq"
```
À modifier en fonction de l’emplacement du disque (sdX ou sataX).





##Glossaire des erreurs

***Erreurs matérielles disque (critiques)***
- `I/O error, dev sdq, sector 2928550848`
- `Unhandled error code`
- `Result: hostbyte=0x05`

- Échec de lecture/écriture sur le disque  
- Secteurs défectueux (toujours au même emplacement)  
- Erreurs répétées → défaut physique confirmé  

---

***Problème de communication SATA***
- `ata6: failed to resume link (SControl 4)`

- Perte ou instabilité du lien avec le disque  
- Peut indiquer :
  - un disque défaillant  
  - ou un problème de connexion (câble, backplane)  

---

***Corruption du système de fichiers (EXT4)***
- `EXT4-fs (sdq1): error loading journal`

- Journal EXT4 illisible  
- Système de fichiers corrompu  
- Montage non fiable  

---

***Échec du journal (JBD2)***
- `JBD2: IO error -5 recovering block`
- `JBD2: recovery failed`

- Impossible de relire les blocs du journal  
- Récupération automatique échouée  
- Corruption confirmée  

---

***Erreurs de montage (secondaires)***
- `EXT3-fs (md0): error: couldn't mount because of unsupported optional features`
- `EXT2-fs (md0): error: couldn't mount because of unsupported optional features`

- Tentative de montage incorrecte (ext2/ext3 sur un volume non compatible)  
- Non directement lié à la panne du disque  
