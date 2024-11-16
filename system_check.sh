#!/bin/bash

echo "=== CachyOS System-Check-Skript ==="
echo "Erstellt einen detaillierten Systembericht"
echo ""

# Erstelle Ausgabeverzeichnis
OUTPUT_DIR="$HOME/system_check_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTPUT_DIR"
LOGFILE="$OUTPUT_DIR/system_check.log"

# Logging-Funktion
log() {
   echo "=== $1 ===" | tee -a "$LOGFILE"
   echo "" | tee -a "$LOGFILE"
   eval "$2" 2>&1 | tee -a "$LOGFILE"
   echo "" | tee -a "$LOGFILE"
}

echo "Logging in: $LOGFILE"
echo "=============================" > "$LOGFILE"
echo "CachyOS System Check Report" >> "$LOGFILE"
echo "Datum: $(date)" >> "$LOGFILE"
echo "=============================" >> "$LOGFILE"
echo "" >> "$LOGFILE"

# System Information
log "System Information" "neofetch"

# Kernel Information
log "Kernel Version" "uname -a"

# System Updates
log "Verfügbare Updates" "yay -Qu"

# Verwaiste Pakete
log "Verwaiste Pakete" "pacman -Qtd"

# Systemd Status
log "Failed Systemd Services" "systemctl --failed"

# System Logs (Errors)
log "System Logs (Errors)" "journalctl -b -p 3..1"

# Grafiktreiber
log "Grafiktreiber Information" "lspci -k | grep -A 2 -E '(VGA|3D)'"

# Kernel Module
log "Geladene Kernel Module" "lsmod"

# Hardware
log "Hardware Übersicht" "sudo lshw"

# Festplatten
log "Festplatten Status" "df -h"

# SMART Status (für jede Festplatte)
for disk in $(lsblk -d -n -o NAME); do
   if [[ $disk == sd* ]] || [[ $disk == nvme* ]]; then
       log "SMART Status für /dev/$disk" "sudo smartctl -a /dev/$disk"
   fi
done

# RAM Status
log "RAM Status" "free -h"

# Detaillierte RAM Info
log "Detaillierte RAM Information" "sudo dmidecode --type memory"

# Pacman Status
log "Pacman Datenbank Check" "sudo pacman -Dk"

# Temperature
log "Systemtemperaturen" "sensors"

# GPU Status (wenn NVIDIA)
if lspci | grep -i nvidia > /dev/null; then
   log "NVIDIA GPU Status" "nvidia-smi"
fi

# Netzwerk Status
log "Netzwerk Interfaces" "ip a"
log "Netzwerk Routen" "ip route"
log "DNS Status" "cat /etc/resolv.conf"

# Firewall Status
log "Firewall Status" "sudo ufw status" 

# Dienste Status
log "Aktive Dienste" "systemctl list-units --type=service --state=running"

# Speichernutzung
log "Top Speichernutzung" "du -h --max-depth=1 /home/$USER | sort -hr | head -n 10"

# CPU Information
log "CPU Information" "lscpu"

# USB Geräte
log "USB Geräte" "lsusb"

# PCI Geräte
log "PCI Geräte" "lspci"

# BIOS Information
log "BIOS Information" "sudo dmidecode -t bios"

echo "=== Überprüfung abgeschlossen ==="
echo "Bericht wurde gespeichert in: $LOGFILE"
echo ""
echo "Möchten Sie den Bericht jetzt anzeigen? (j/n)"
read -r answer

if [[ $answer =~ ^[Jj]$ ]]; then
   less "$LOGFILE"
fi

