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
UTILISE=$(echo "$disk_line" | awk '{print $3}')
TOTALE=$(echo "$disk_line" | awk '{print $2}')

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

if [ "$total" -eq 0 ]; then
    BACKUP_STATUS="Aucune tâche trouvée"
elif [ "$successes" -eq "$total" ]; then
    BACKUP_STATUS="Backup $successes/$total"
else
    BACKUP_STATUS="Backup $successes/$total"
fi

# ---------------------------------------------------------------------------------------------
# État des disques
# ---------------------------------------------------------------------------------------------
DISK_REPORT=""

for d in $(awk '$4 ~ /^(sd[a-z]+|sata[0-9]+)$/ {print "/dev/"$4}' /proc/partitions); do

    [ -b "$d" ] || continue
    disk_name=$(basename "$d")

    model=""
    cap=""
    temp=""
    smart=""

    if echo "$d" | grep -q "sata"; then

        syno_info=$(synodisk --info "$d" 2>/dev/null)

        model=$(echo "$syno_info" | awk -F': ' '/Disk model/ {print $2}')
        cap=$(echo "$syno_info" | awk -F': ' '/Total capacity/ {print $2}')
        temp=$(echo "$syno_info" | awk -F': ' '/Tempeture/ {print $2}')

        [ "$temp" = "-1.00 C" ] && temp="N/A"
        smart=$(smartctl -a "$d" 2>/dev/null)

    else

        smart=$(smartctl -a "$d" 2>/dev/null)

        if [ -z "$smart" ]; then
            smart=$(smartctl -a -d sat "$d" 2>/dev/null)
        fi

        model=$(echo "$smart" | awk -F: '
        /Device Model/ {print $2}
        /Product/ {print $2}
        /Model Number/ {print $2}
        ' | head -n1 | sed 's/^ *//')

        [ -z "$model" ] && model=$(synodisk --info "$d" 2>/dev/null | awk -F': ' '/Disk model/ {print $2}')

        cap=$(echo "$smart" | awk -F: '/User Capacity/ {print $2}')
        [ -z "$cap" ] && cap=$(synodisk --info "$d" 2>/dev/null | awk -F': ' '/Total capacity/ {print $2}')

        temp=$(echo "$smart" | awk '
        /Temperature_Celsius/ {print $10}
        /Temperature:/ {print $2}
        ' | head -n1 | sed 's/^ *//')

        [ -z "$temp" ] && temp=$(synodisk --info "$d" 2>/dev/null | awk -F': ' '/Tempeture/ {print $2}')
    fi

    power_on_hours=$(synodisk --smart_info_get "$d" 2>/dev/null | awk '
        /Id: 9$/ { found=1 }
        found && /Raw:/ { print $2; found=0 }
    ')
    [ -z "$power_on_hours" ] && power_on_hours="N/A"

    reallocated=$(echo "$smart" | awk '/Reallocated_Sector_Ct/ {print $10}')
    pending=$(echo "$smart" | awk '/Current_Pending_Sector/ {print $10}')
    offline=$(echo "$smart" | awk '/Offline_Uncorrectable/ {print $10}')
    ata_error=$(echo "$smart" | awk '/ATA Error Count/ {print $4}')

    [ -z "$reallocated" ] && reallocated=0
    [ -z "$pending" ] && pending=0
    [ -z "$offline" ] && offline=0
    [ -z "$ata_error" ] && ata_error=0

    if [ "$reallocated" -ne 0 ] || [ "$pending" -ne 0 ] || [ "$offline" -ne 0 ] || [ "$ata_error" -ne 0 ]; then
        statut="WARNING"
    else
        statut="OK"
    fi

    dmesg_log=$(dmesg | grep -i "$disk_name" | grep -Ei "error|fail|sense|asc|blk_update|buffer i/o" | tail -n 6)

    DISK_REPORT="${DISK_REPORT}
-------------------------------------
Disque    : $d
Modèle    : $model
Capacité  : $cap
Temp      : $temp
Allumage  : $power_on_hours h

Reallocated: $reallocated
Pending    : $pending
Offline    : $offline
ATA_Error  : $ata_error

STATUT    : $statut

/$disk_name :

$dmesg_log

"
done

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

ETAT DES DISQUES
$DISK_REPORT
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
