#!/bin/sh

# -------------------------------
# VARIABLES MAIL
# -------------------------------
TOMAIL="supervision.mogador.informatique@free.fr"
SUJETMAIL="Rapport DSM Synology - $(date '+%d/%m/%Y %H:%M')"
FROMMAIL=$(grep 'smtp_from_mail' /usr/syno/etc/synosmtp.conf | cut -d '=' -f2 | tr -d '"')

# -------------------------------
# SYSTEME
# -------------------------------
DS_SERIAL=$(grep '^pushservice_dsserial=' /etc/synoinfo.conf | cut -d '=' -f2 | tr -d '"')
NAME=$(cat /etc/hostname)
SERVER_NAME=$(cat /proc/sys/kernel/syno_hw_version)
DSM_VERSION=$(grep '^productversion' /etc/VERSION | cut -d'"' -f2)

# -------------------------------
# UPDATE DSM
# -------------------------------
UPDATE_FILE="/var/update/check_result/last_notified/update"

if [ -f "$UPDATE_FILE" ] && grep -q '"blAvailable":true' "$UPDATE_FILE"; then
    MISE="Mise à jour DSM disponible"
else
    MISE="DSM à jour"
fi

# -------------------------------
# ETAT SERVEUR
# -------------------------------
SERVER_STATUS="Inconnu"

if [ -f /usr/syno/sbin/synostgvolume ]; then
    VOLUME_STATUS=$(/usr/syno/sbin/synostgvolume --status 2>/dev/null)

    echo "$VOLUME_STATUS" | grep -q "attention" && SERVER_STATUS="Avertissement"
    echo "$VOLUME_STATUS" | grep -q "crashed" && SERVER_STATUS="Critique"
    echo "$VOLUME_STATUS" | grep -q "normal" && SERVER_STATUS="Sain"
fi

# -------------------------------
# STOCKAGE / RAM
# -------------------------------
disk_line=$(df -h | awk '$6=="/volume1" {print $0}')
UTILISE=$(echo "$disk_line" | awk '{print $3}')
TOTALE=$(echo "$disk_line" | awk '{print $2}')

RAM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
RAM_USED=$(free -m | awk '/Mem:/ {print $3}')

RAM_PERCENT=$(( RAM_USED * 100 / RAM_TOTAL ))

# -------------------------------
# BACKUP
# -------------------------------
CONF_FILE="/usr/syno/etc/synobackup.conf"
LAST_FILE="/var/synobackup/last_result/backup.last"

task_names=$(awk -F= '
/^\[task_[0-9]+\]/ {f=1; next}
/^\[/ {f=0}
f && /^[[:space:]]*name=/ {gsub(/"/,"",$2); print $2}' "$CONF_FILE")

details=""
successes=0
total=0
i=0

while read -r line; do
    if echo "$line" | grep -q '^error_code='; then
        code=$(echo "$line" | cut -d= -f2)
        name=$(echo "$task_names" | sed -n "$((i+1))p")

        if [ "$code" -eq 0 ]; then
            status="OK"
            successes=$((successes+1))
        else
            status="Échec"
        fi

        details="${details}
$name : $status"
        total=$((total+1))
        i=$((i+1))
    fi
done < "$LAST_FILE"

BACKUP_STATUS="Backup $successes/$total"





# -------------------------------
# DISQUES (COMPATIBLE TOUS NAS)
# -------------------------------
DISK_REPORT=""

for d in $(awk '$4 ~ /^(sd[a-z]+|sata[0-9]+)$/ {print "/dev/"$4}' /proc/partitions); do

    [ -b "$d" ] || continue
    disk_name=$(basename "$d")

    model=""
    cap=""
    temp=""
    smart=""

    # -------------------------------
    # CAS DISQUE SATA (Synology récent)
    # -------------------------------
    if echo "$d" | grep -q "sata"; then

        syno_info=$(synodisk --info "$d" 2>/dev/null)

        model=$(echo "$syno_info" | awk -F': ' '/Disk model/ {print $2}')
        cap=$(echo "$syno_info" | awk -F': ' '/Total capacity/ {print $2}')
        temp=$(echo "$syno_info" | awk -F': ' '/Tempeture/ {print $2}')

        # correction valeur invalide
        [ "$temp" = "-1.00 C" ] && temp="N/A"

        # SMART pour erreurs
        smart=$(smartctl -a "$d" 2>/dev/null)

    else
        # -------------------------------
        # CAS DISQUE SD (anciens NAS)
        # -------------------------------
        smart=$(smartctl -a "$d" 2>/dev/null)

        if [ -z "$smart" ]; then
            smart=$(smartctl -a -d sat "$d" 2>/dev/null)
        fi

        # modèle (multi-format)
        model=$(echo "$smart" | awk -F: '
        /Device Model/ {print $2}
        /Product/ {print $2}
        /Model Number/ {print $2}
        ' | head -n1 | sed 's/^ *//')

        # fallback synology
        [ -z "$model" ] && model=$(synodisk --info "$d" 2>/dev/null | awk -F': ' '/Disk model/ {print $2}')

        # capacité
        cap=$(echo "$smart" | awk -F: '/User Capacity/ {print $2}')
        [ -z "$cap" ] && cap=$(synodisk --info "$d" 2>/dev/null | awk -F': ' '/Total capacity/ {print $2}')

        # température (multi-format)
        temp=$(echo "$smart" | awk '
        /Temperature_Celsius/ {print $10}
        /Temperature:/ {print $2}
        ' | head -n1 | sed 's/^ *//')

        [ -z "$temp" ] && temp=$(synodisk --info "$d" 2>/dev/null | awk -F': ' '/Tempeture/ {print $2}')
    fi

    # -------------------------------
    # SMART (commun)
    # -------------------------------
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

Reallocated: $reallocated
Pending    : $pending
Offline    : $offline
ATA_Error  : $ata_error

STATUT    : $statut

/$disk_name :

$dmesg_log

"
done








# -------------------------------
# MAIL FINAL
# -------------------------------
CORPSMAIL="Rapport DSM Synology - $(date '+%d/%m/%Y %H:%M')
-------------------------------------
Numero de serie : $DS_SERIAL
Nom du client   : $NAME
Nom du serveur  : $SERVER_NAME
Version DSM     : $DSM_VERSION
Mise à jour     : $MISE
Etat du serveur : $SERVER_STATUS

Stockage        : utilise : $UTILISE / total : $TOTALE
RAM utiliser    : $RAM_PERCENT %

Backups         : $BACKUP_STATUS
Détails :
$details


ETAT DES DISQUES
$DISK_REPORT
"
# -------------------------------
# ENVOI MAIL
# -------------------------------
{
echo "To: $TOMAIL"
echo "From: $FROMMAIL"
echo "Subject: $SUJETMAIL"
echo "Content-Type: text/plain; charset=UTF-8"
echo
printf "%b\n" "$CORPSMAIL"
} | ssmtp -v "$TOMAIL"