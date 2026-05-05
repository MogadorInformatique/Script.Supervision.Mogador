**Commande a ajouter dans la tâche supervision**
```bash
#!/bin/bash
curl -sSfL https://raw.githubusercontent.com/MogadorInformatique/Script.Supervision.Mogador/main/DSM7_NAS.sh | bash
```

**Voire les logs du disque en question depuis le boot**
```bash
dmesg -T | grep -i sdq
```
À modifier en fonction de l’emplacement du disque (sdX ou sataX).
