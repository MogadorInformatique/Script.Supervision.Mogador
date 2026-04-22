```sh
#!/bin/sh

# -------------------------------
# Variables
# -------------------------------
TOMAIL="supervision.mogador.informatique@free.fr"
SUJETMAIL="Rapport DSM Synology - $(date '+%d/%m/%Y %H:%M')"
FROMMAIL=$(grep 'smtp_from_mail' /usr/syno/etc/synosmtp.conf | cut -d '=' -f2 | tr -d '"')

# ---------------------------------------------------------------------------------------------
# Numéro de série DSM
# ---------------------------------------------------------------------------------------------
DS_SERIAL=$(grep '^pushservice_dsserial=' /etc/synoinfo.conf | cut -d '=' -f2 | tr -d '"')


# ---------------------------------------------------------------------------------------------
# Nom du client
# ---------------------------------------------------------------------------------------------
NAME=$(cat /etc/hostname)

# ---------------------------------------------------------------------------------------------
# Nom du serveur
# ---------------------------------------------------------------------------------------------
SERVER_NAME=$(cat /proc/sys/kernel/syno_hw_version)

# ---------------------------------------------------------------------------------------------
# Version DSM
# ---------------------------------------------------------------------------------------------
DSM_VERSION=$(grep '^productversion' /etc/VERSION | cut -d'"' -f2)

# ---------------------------------------------------------------------------------------------
# Mise à jour (DSM 7)
# ---------------------------------------------------------------------------------------------
UPDATE_FILE="/var/update/check_result/last_notified/update"
if [ -f "$UPDATE_FILE" ] && grep -q '"blAvailable":true' "$UPDATE_FILE"; then
    MISE="Mise à jour DSM disponible"
else
    MISE="DSM à jour"
fi

# ---------------------------------------------------------------------------------------------
# État du serveur
# ---------------------------------------------------------------------------------------------
if [ -x /usr/syno/sbin/synostgvolume ]; then
    VOLUME_STATUS=$(/usr/syno/sbin/synostgvolume --status 2>/dev/null)

    echo "$VOLUME_STATUS" | grep -q '"status":"attention"' && SERVER_STATUS="Avertissement"
    echo "$VOLUME_STATUS" | grep -q '"status":"crashed"' && SERVER_STATUS="Critique"
    echo "$VOLUME_STATUS" | grep -q '"status":"normal"' && SERVER_STATUS="Sain"
    [ -z "$SERVER_STATUS" ] && SERVER_STATUS="Inconnu"
else
    SERVER_STATUS="Inconnu"
fi

# ---------------------------------------------------------------------------------------------
# Espace disque
# ---------------------------------------------------------------------------------------------
disk_line=$(df -h | awk '$6=="/volume1" {print $0}')
UTILISE=$(echo "$disk_line" | awk '{print $3}')   # utilisé
TOTALE=$(echo "$disk_line" | awk '{print $2}')    # total

# ---------------------------------------------------------------------------------------------
# RAM
# ---------------------------------------------------------------------------------------------
RAM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
RAM_USED=$(free -m | awk '/Mem:/ {print $3}')
if [ -n "$RAM_TOTAL" ] && [ "$RAM_TOTAL" -ne 0 ]; then
    RAM_PERCENT=$(( RAM_USED * 100 / RAM_TOTAL ))
else
    RAM_PERCENT="N/A"
fi

# ---------------------------------------------------------------------------------------------
# Backup Status (depuis /tmp/synobackup/progress)
# ---------------------------------------------------------------------------------------------
TASKS_DIR="/tmp/synobackup/progress"

details=""
successes=0
total=0

# définir manuellement les noms lisibles ici
get_task_name() {
    case "$1" in
        task_1) echo "Tâche : " ;;    # numéro de la tâche en rouge et le nom de la tâche(cloud;distant;paire;impaire;etc...)
        task_2) echo "Tâche : " ;;    # numéro de la tâche en rouge et le nom de la tâche(cloud;distant;paire;impaire;etc...)
        *) echo "$1" ;;
    esac
}

for task_path in "$TASKS_DIR"/task_*; do
    [ -d "$task_path" ] || continue
    task_id=$(basename "$task_path")
    name=$(get_task_name "$task_id")

    progress_file="$task_path/0"
    if [ -f "$progress_file" ]; then
        code=$(grep -E '^error_code=' "$progress_file" | cut -d'"' -f2)
        if [ "$code" = "0" ]; then
            status="OK"
            successes=$((successes+1))
        else
            status="Échec"
        fi
    else
        status="Inconnu"
    fi

    details="$details""$name : $status\n"
    total=$((total+1))
done

# Statut global
if [ "$total" -eq 0 ]; then
    BACKUP_STATUS="Aucune tâche trouvée"
elif [ "$successes" -eq "$total" ]; then
    BACKUP_STATUS="Backup $successes/$total"
else
    BACKUP_STATUS="Backup $successes/$total"
fi

# ---------------------------------------------------------------------------------------------
# Construction du rapport
# ---------------------------------------------------------------------------------------------
CORPSMAIL="Rapport DSM Synology - $(date '+%d/%m/%Y %H:%M')
-------------------------------------
Numero de serie : $DS_SERIAL
Nom du client   : $NAME
Nom du serveur  : $SERVER_NAME
Version DSM     : DSM $DSM_VERSION
Mise a jour     : $MISE
Etat du serveur : $SERVER_STATUS
MFA active      : Non disponible via script local

Disques         : utilise : $UTILISE / total : $TOTALE
RAM utiliser    : $RAM_PERCENT%

Backups : $BACKUP_STATUS

Détails :
$details
"

# ---------------------------------------------------------------------------------------------
# Envoi du mail
# ---------------------------------------------------------------------------------------------
{
  echo "To: $TOMAIL"
  echo "From: $FROMMAIL"
  echo "Subject: $SUJETMAIL"
  echo "Content-Type: text/plain; charset=UTF-8"
  echo
  echo -e "$CORPSMAIL"
} | ssmtp $TOMAIL -v
```
