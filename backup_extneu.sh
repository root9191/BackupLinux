#!/bin/bash
# ==============================================================================
# TEIL 1: KONFIGURIERBARE VARIABLEN UND EINSTELLUNGEN
# ==============================================================================

# Fehlerbehandlung aktivieren
set -euo pipefail

# --- Backup Basis-Konfiguration ---
USE_TIMESTAMP="no"  # "yes" oder "no"
TIMESTAMP_FORMAT="%d%m%y_%H%M"  # Format: YYYYMMDD_HHMM (z.B. 20241101_1430)
# Mögliche Zeitstempel-Formate:
# %Y%m%d         -> 20241101     (nur Datum)
# %Y-%m-%d       -> 2024-11-01   (Datum mit Bindestrichen)
# %Y%m%d_%H%M    -> 20241101_1430 (Datum und Zeit)
# %Y%m%d_%H-%M-%S -> 20241101_14-30-45 (Datum und Zeit mit Sekunden)

# --- SSH Backup Konfiguration ---
BACKUP_SSH="no"           # "yes" oder "no"
BACKUP_SSH_KEYS="no"      # "yes" oder "no" - Private Schlüssel nur wenn ENCRYPT="true"

# --- Basis-Verzeichnisse ---
BASE_BACKUP_DIR="/mnt/Daten/lichti/cachyos_btrfs"
TEMP_BASE_DIR="/var/tmp/bkp"

# --- Logging Konfiguration ---
LOG_TO_FILE="yes"          # "yes" oder "no" - Logging in Datei aktivieren
LOG_ERRORS="yes"          # "yes" oder "no" - Separate Fehlerprotokollierung
LOG_DIR="/mnt/bkplog/"
LOG_FILE="${LOG_DIR}/backup.log"
ERROR_LOG="${LOG_DIR}/backup_error.log"
MAX_LOG_FILES=5           # Anzahl der zu behaltenden Log-Dateien

# Benutzer-Home-Verzeichnis automatisch ermitteln und setzen
if [ -n "${SUDO_USER:-}" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    if [ -z "$USER_HOME" ]; then
        echo -e "${RED}Fehler: Konnte Home-Verzeichnis für $SUDO_USER nicht ermitteln${RESET}"
        exit 1
    fi
    export USER_HOME
else
    echo -e "${RED}Fehler: SUDO_USER nicht gesetzt${RESET}"
    exit 1
fi

# --- Backup Unterverzeichnisse ---
declare -A BACKUP_SUBDIRS=(
    [etc]="$BASE_BACKUP_DIR/etc"
    [usr_share]="$BASE_BACKUP_DIR/usr/share"
)

# --- Farbdefinitionen ---
BLUE='\e[34m'
GREEN='\e[32m'
DARK_GREEN='\e[32;2m'  # Für Erstellen/Prüfen Meldungen
LIGHT_GREEN='\e[92m'
YELLOW='\e[33m'
RED='\e[31m'
CYAN='\e[36m'
MAGENTA='\e[35m'
ORANGE='\e[38;5;208m'
BOLD='\e[1m'
RESET='\e[0m'

# ==============================================================================
# TEIL 2: ZU SICHERNDE DATEIEN UND VERZEICHNISSE
# ==============================================================================

# --- Zu sichernde Dotfiles ---
# Diese Dateien werden alle relativ zu $USER Home gesichert,
# d.h. ".zshrc" wird als "/home/$USER/.zshrc" gesichert
declare -a DOTFILES=(
    # Aktive Shell-Konfigurationen
    .zshrc
    .zsh_history
    .p10k.zsh
    .bashrc
    .bash_profile
 #   .bash_history
 #   .nvidia-settings-rc
    
    
    # Zusätzliche Shell-Konfigurationen (auskommentiert)
    #.zshenv
    #.zprofile
    #.zlogin
    #.zlogout
    #.inputrc
    #.profile
    
    # Editoren (auskommentiert)
    #.vim/
    #.vimrc
    #.nanorc
    #.emacs
    #.emacs.d/
    
    # Entwicklungswerkzeuge (auskommentiert)
    #.npmrc
    #.yarnrc
    #.cargo/config
    #.gradle/gradle.properties
    #.m2/settings.xml
    #.composer/config.json
    
    # Cloud und Dienste (auskommentiert)
    #.aws/config
    #.aws/credentials
    #.kube/config
    
    # Terminal-Tools (auskommentiert)
    #.screenrc
    #.tmux.conf
    #.wgetrc
    #.curlrc
)

# --- Zu sichernde Home-Verzeichnisse ---
# Diese Verzeichnisse werden alle relativ zu $USER Home gesichert,
# d.h. ".fonts" wird als "/home/$USER/.fonts" gesichert
declare -a HOME_DIRS=(
    # Aktive Anwendungsverzeichnisse
    .vscode
    .thunderbird
    .mozilla
    .var
    AppImages
    Musik
    Videos
  #  .vmware
   # .wine
    .icons
    .themes
  #  .fonts
  #  .docker
    Downloads
    Dokumente
    Bilder
   # Desktop
    .config/BraveSoftware

    # Entwicklungstools (auskommentiert)
    #.gradle
    #.cargo
    #.npm
    #.gem
    #.composer
    #.jupyter
    
    # Sicherheit (auskommentiert)
    #.password-store
    #.gnupg
    #.ssh
    
    # Lokale Anwendungsdaten (auskommentiert)
    #.local/share/keyrings
    #.local/share/applications
)

# --- Systemkonfigurationen ---
# Diese Verzeichnisse werden alle relativ zu /etc gesichert,
# d.h. "conf.d" wird als "/etc/conf.d" gesichert
declare -a SYSTEM_CONFIGS=(
    # Aktive Systemkonfigurationen
    "fstab"
    "pacman.conf"
    "mkinitcpio.conf"
    #default/grub
    default/limine
    limine-entry-tool.conf
    limine-snapper-sync.conf
    limine-entry-tool.conf.pacnew
    default/ufw
    # Basis-System (auskommentiert)
    #"hosts"
    #"hostname"
    #"locale.conf"
    #"resolv.conf"
    
    # Sicherheit (auskommentiert)
    #"hosts.allow"
    #"hosts.deny"
    #"sudoers"
    #"ssl/openssl.cnf"
    
    # Systemkonfiguration (auskommentiert)
    #"sysctl.conf"
    #"modules-load.d/modules.conf"
)

# --- Systemkonfigurationsverzeichnisse in /etc ---
# Diese Verzeichnisse werden alle relativ zu /etc gesichert,
# d.h. "conf.d" wird als "/etc/conf.d" gesichert
declare -a SYSTEM_CONFIG_DIRS=(
    # Aktive Verzeichnisse
    "conf.d"
    "default"
    "ufw"
   # "grub.d"
    
    # System (auskommentiert)
    #"xdg"
    #"sysctl.d"
    #"modprobe.d"
    #"dracut.conf.d"
    
    # Sicherheit (auskommentiert)
    #"ssl"
    #"pam.d"
    
    # Paketmanager (auskommentiert)
    #"apt"          # Debian/Ubuntu
    #"yum.repos.d"  # RHEL/Fedora
    #"zypp"         # openSUSE
    
    # Dienste (auskommentiert)
    #"cron.d"
    #"logrotate.d"
    #"tmpfiles.d"
)

# --- Icons ---
#/usr/share/icons
declare -a ICONS=(
    "Numix-Circle"
    "Numix"
    "MacTahoe-dark"
    "MacTahoe"
)

# --- Applications ---
#/usr/share/applications
#declare -a APPLICATIONS=(
    #"*equibop*.desktop"
#)



# --- RSYNC Ausschlüsse ---
declare -a CACHE_EXCLUDES=(
    ".cache/yay"
    ".cache/mozilla"
    ".cache/doc"
)

#Ausschlüsse aus dem Backup aus dem $User Home .local Verzeichnis
#/home/$USER/.local
declare -a LOCAL_EXCLUDES=(
    "share/Steam/steamapps/common"
    "share/Steam/steamapps/compatdata"
    "share/Steam/compatibilitytools.d"
    "share/DaVinciResolve/DVIP/Cache"
    "share/Steam/ubuntu12_64"
    "share/Steam/steamapps/shadercache"
    "share/Trash"
    "share/lutris/runners"
    "share/lutris/runtime"
    "share/bottles/runners"
    "share/bottles/templates"
    "share/bottles/temp"
    "share/pnpm"
)

# ==============================================================================
# TEIL 3: WIEDERHERSTELLUNGS-ANWEISUNGEN
# ==============================================================================

# === WIEDERHERSTELLUNGS-ANWEISUNGEN ===

# GNOME-Einstellungen wiederherstellen:
# 1. Alle Einstellungen:
#    dconf load / < gnome-settings-backup.dconf
#
# 2. Tastenkürzel wiederherstellen mit:
#    dconf load /org/gnome/desktop/wm/keybindings/ < gnome-shortcuts-wm.dconf
#    dconf load /org/gnome/settings-daemon/plugins/media-keys/ < gnome-shortcuts-media.dconf
#    dconf load /org/gnome/shell/keybindings/ < gnome-shortcuts-shell.dconf
#
# 3. GNOME-Erweiterungen wiederherstellen:
#    cp -r gnome_extensions/* ~/.local/share/gnome-shell/extensions/
#    Alt+F2 -> 'r' -> Enter (GNOME Shell neustarten)

# Paketlisten wiederherstellen:
# 1. System-Pakete:
#    sudo pacman -S --needed - < system_packages.txt  # Für Arch-basierte Systeme
#    sudo apt-get install -y $(cat packages.txt)      # Für Debian-basierte Systeme
#    sudo dnf install -y $(cat packages.txt)          # Für Fedora
#    sudo zypper install -y $(cat packages.txt)       # Für OpenSUSE
#
# 2. AUR-Pakete (nur für Arch):
#    yay -S --needed - < aur_packages.txt
#
# 3. Flatpak-Pakete und Remotes:
#    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
#    while read -r app; do flatpak install -y flathub $app; done < flatpak_packages.txt
#    while read -r name url; do flatpak remote-add --if-not-exists "$name" "$url"; done < flatpak_remotes.txt

# 4. Snap-Pakete (falls vorhanden):
#    while read -r name rest; do [ "$name" != "Name" ] && snap install "$name"; done < snap_packages.txt

# System-Konfigurationen wiederherstellen:
# !! VORSICHT: Prüfen Sie die Konfigurationen vor dem Überschreiben !!
# 1. fstab:
#    sudo cp backup_etc/fstab /etc/fstab
#    sudo mount -a  # Zum Testen der fstab
#
# 2. Weitere Systemkonfigurationen:
#    sudo cp -r backup_etc/conf.d/* /etc/conf.d/
#    sudo cp -r backup_etc/default/* /etc/default/
#    sudo cp -r backup_etc/ufw/* /etc/ufw/
#    sudo cp backup_etc/mkinitcpio.conf /etc/mkinitcpio.conf
#    sudo mkinitcpio -P  # Kernel-Image neu erstellen

# NetworkManager-Verbindungen wiederherstellen:
#    sudo cp -r backup_etc/NetworkManager_system-connections/* /etc/NetworkManager/system-connections/
#    sudo chmod 600 /etc/NetworkManager/system-connections/*
#    sudo systemctl restart NetworkManager

# Themes und Icons wiederherstellen:
#    sudo cp -r backup_usr_share/icons/* /usr/share/icons/
#    sudo cp -r backup_usr_share/themes/* /usr/share/themes/

# Dotfiles wiederherstellen:
#    cp -a .zshrc .p10k.zsh .gitconfig ~/
#    cp -a .bashrc .bash_profile ~/
#    source ~/.zshrc  # oder ~/.bashrc

# Wichtige Verzeichnisse wiederherstellen:
#    cp -r .config ~/
#    cp -r .local ~/
#    cp -r .vscode ~/
#    cp -r .mozilla ~/
#    cp -r .thunderbird ~/
#    cp -r .wine ~/
#    cp -r .icons ~/
#    cp -r .themes ~/
#    cp -r .fonts ~/
#    fc-cache -f -v  # Schriften-Cache aktualisieren

# Flatpak-Daten wiederherstellen:
#    cp -r flatpak_data/* ~/.local/share/flatpak/
#    cp -r flatpak_apps/* ~/.var/app/

# Persönliche Ordner wiederherstellen:
#    cp -r Downloads ~/
#    cp -r Bilder ~/
#    cp -r Dokumente ~/

# Verschlüsseltes Backup wiederherstellen:
# 1. Entschlüsseln:
#    gpg --output backup.tar.gz --decrypt backup.tar.gz.gpg
# 2. Entpacken:
#    tar xzf backup.tar.gz

# ==============================================================================
# TEIL 4: FUNKTIONEN
# ==============================================================================

# --- Logging Funktionen ---
# --- Logging Funktionen ---
init_logging() {
    if [ "${LOG_TO_FILE,,}" = "yes" ]; then
        # Logging-Verzeichnis erstellen falls nicht vorhanden
        [ ! -d "$LOG_DIR" ] && mkdir -p "$LOG_DIR"
        
        # Neue Logdatei beginnen
        echo "=== Backup gestartet am $(date) ===" > "$LOG_FILE"
        
        # Berechtigungen setzen
        chown "$SUDO_USER:$SUDO_USER" "$LOG_DIR"
        chmod 750 "$LOG_DIR"
        [ -f "$LOG_FILE" ] && chown "$SUDO_USER:$SUDO_USER" "$LOG_FILE"
        
        # Fehlerlog wird erst angelegt wenn wirklich ein Fehler auftritt
        if [ "${LOG_ERRORS,,}" = "yes" ]; then
            ERROR_LOG="${LOG_DIR}/backup_error.log"
        fi
    fi
}

cleanup_logs() {
    local max_logs=5
    local log_pattern="backup_*.log"
    
    cd "$LOG_DIR" || return
    if [ -f "$LOG_FILE" ]; then
        mv "$LOG_FILE" "${LOG_FILE%.log}_$(date +'%Y%m%d_%H%M%S').log"
    fi
    
    ls -t $log_pattern 2>/dev/null | tail -n +$((max_logs + 1)) | xargs -r rm
    
    if [ -f "$ERROR_LOG" ]; then
        mv "$ERROR_LOG" "${ERROR_LOG%.log}_$(date +'%Y%m%d_%H%M%S').log"
    fi
}

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    local formatted_message

    # Clean message for logfile (ohne ANSI Farben)
    local log_message="[$timestamp] $level: $message"

    # Formatierte Timestamp für Terminal
    local formatted_timestamp="${CYAN}[${timestamp}]${RESET}"
    
    # Terminal Ausgabe
    case "$level" in
        "ERROR")
            formatted_message="${formatted_timestamp} ${BOLD}${RED}ERROR:${RESET} $message"
            echo -e "$formatted_message" >&2
            if [ "${LOG_ERRORS,,}" = "yes" ]; then
                if [ ! -f "$ERROR_LOG" ]; then
                    echo "=== Fehlerprotokoll gestartet am $(date) ===" > "$ERROR_LOG"
                    chown "$SUDO_USER:$SUDO_USER" "$ERROR_LOG"
                fi
                local line_number=$(caller | cut -d" " -f1)
                echo "[$timestamp] ERROR: $message (Zeile $line_number)" >> "$ERROR_LOG"
            fi
            return 1
            ;;
        "WARNING")
            formatted_message="${formatted_timestamp} ${BOLD}${YELLOW}WARNING:${RESET} $message"
            echo -e "$formatted_message"
            ;;
        "INFO")
            case "$message" in
                "Initialisiere Backup-Prozess"*|"Starte Backup-Prozess"*)
                    formatted_message="${formatted_timestamp} ${BOLD}${GREEN}INFO:${RESET} ${GREEN}$message${RESET}"
                    ;;
                *"Verschlüssele Backup"*)
                    formatted_message="${formatted_timestamp} ${BOLD}${GREEN}INFO:${RESET} ${BLUE}$message${RESET}"
                    ;;
                *"Benutzer-Home-Verzeichnis:"*)
                    formatted_message="${formatted_timestamp} ${BOLD}${GREEN}INFO:${RESET} ${GREEN}$message${RESET}"
                    ;;
                *"Gefunden:"*)
                    if [[ $message =~ Gefunden:\ ([0-9]+)\ (.*)\ und\ ([0-9]+)\ (.*) ]]; then
                        local num1="${BASH_REMATCH[1]}"
                        local text1="${BASH_REMATCH[2]}"
                        local num2="${BASH_REMATCH[3]}"
                        local text2="${BASH_REMATCH[4]}"
                        formatted_message="${formatted_timestamp} ${BOLD}${GREEN}INFO:${RESET} ${GREEN}Gefunden: ${ORANGE}${num1}${GREEN} ${text1} und ${ORANGE}${num2}${GREEN} ${text2}${RESET}"
                    else
                        if [[ $message =~ Gefunden:\ ([0-9]+)\ (.*) ]]; then
                            local num="${BASH_REMATCH[1]}"
                            local text="${BASH_REMATCH[2]}"
                            formatted_message="${formatted_timestamp} ${BOLD}${GREEN}INFO:${RESET} ${GREEN}Gefunden: ${ORANGE}${num}${GREEN} ${text}${RESET}"
                        else
                            formatted_message="${formatted_timestamp} ${BOLD}${GREEN}INFO:${RESET} ${GREEN}$message${RESET}"
                        fi
                    fi
                    ;;
                "Beginne mit der Komprimierung"*)
                    formatted_message="${formatted_timestamp} ${BOLD}${GREEN}INFO:${RESET} ${BLUE}$message${RESET}"
                    ;;
                *"Ursprungsgröße:"*)
                    if [[ $message =~ Ursprungsgröße:\ ([0-9A-Za-z]+B?) ]]; then
                        local size="${BASH_REMATCH[1]}"
                        formatted_message="${formatted_timestamp} ${BOLD}${GREEN}INFO:${RESET} ${GREEN}Ursprungsgröße: ${ORANGE}${size}${RESET}"
                    else
                        formatted_message="${formatted_timestamp} ${BOLD}${GREEN}INFO:${RESET} ${GREEN}$message${RESET}"
                    fi
                    ;;
                *"Starte Komprimierung mit"*)
                    if [[ $message =~ Starte\ Komprimierung\ mit\ ([0-9]+)\ (.*) ]]; then
                        local num="${BASH_REMATCH[1]}"
                        local text="${BASH_REMATCH[2]}"
                        formatted_message="${formatted_timestamp} ${BOLD}${GREEN}INFO:${RESET} ${BLUE}Starte Komprimierung mit ${ORANGE}${num}${BLUE} ${text}${RESET}"
                    else
                        formatted_message="${formatted_timestamp} ${BOLD}${GREEN}INFO:${RESET} ${BLUE}$message${RESET}"
                    fi
                    ;;
                *"Komprimierte Größe:"*)
                    if [[ $message =~ Komprimierte\ Größe:\ ([0-9A-Za-z]+G?) ]]; then
                        local size="${BASH_REMATCH[1]}"
                        formatted_message="${formatted_timestamp} ${BOLD}${GREEN}INFO:${RESET} ${GREEN}Komprimierte Größe: ${ORANGE}${size}${RESET}"
                    else
                        formatted_message="${formatted_timestamp} ${BOLD}${GREEN}INFO:${RESET} ${GREEN}$message${RESET}"
                    fi
                    ;;
                "Räume auf"*)
                    formatted_message="${formatted_timestamp} ${BOLD}${GREEN}INFO:${RESET} ${GREEN}$message${RESET}"
                    ;;
                *"GPG ist installiert:"*)
                    if [[ $message =~ GPG\ ist\ installiert:\ gpg\ \(GnuPG\)\ ([0-9.]+) ]]; then
                        local version="${BASH_REMATCH[1]}"
                        formatted_message="${formatted_timestamp} ${BOLD}${GREEN}INFO:${RESET} ${LIGHT_GREEN}GPG ist installiert: gpg (GnuPG) ${ORANGE}${version}${RESET}"
                    else
                        formatted_message="${formatted_timestamp} ${BOLD}${GREEN}INFO:${RESET} ${LIGHT_GREEN}$message${RESET}"
                    fi
                    ;;
                *"Backup-Größe:"*)
                    if [[ $message =~ Backup-Größe:\ ([0-9A-Za-z]+G?) ]]; then
                        local size="${BASH_REMATCH[1]}"
                        formatted_message="${formatted_timestamp} ${BOLD}${GREEN}INFO:${RESET} ${GREEN}Backup-Größe: ${ORANGE}${size}${RESET}"
                    else
                        formatted_message="${formatted_timestamp} ${BOLD}${GREEN}INFO:${RESET} ${GREEN}$message${RESET}"
                    fi
                    ;;
                *"Erkannt"*)
                    formatted_message="${formatted_timestamp} ${BOLD}${GREEN}INFO:${RESET} ${GREEN}$message${RESET}"
                    ;;
                *"Erstelle"*|*"Prüfe"*)
                    formatted_message="${formatted_timestamp} ${BOLD}${GREEN}INFO:${RESET} ${DARK_GREEN}$message${RESET}"
                    ;;
                "Sichere"*)
                    formatted_message="${formatted_timestamp} ${BOLD}${GREEN}INFO:${RESET} ${BLUE}$message${RESET}"
                    ;;
                "Alle Basis-Abhängigkeiten sind bereits installiert"*|*"Backup abgeschlossen."*)
                    formatted_message="${formatted_timestamp} ${BOLD}${GREEN}INFO:${RESET} ${LIGHT_GREEN}$message${RESET}"
                    ;;
                *"Expac Version:"*)
                    if [[ $message =~ Expac\ Version:\ expac\ ([0-9]+) ]]; then
                        local version="${BASH_REMATCH[1]}"
                        formatted_message="${formatted_timestamp} ${BOLD}${GREEN}INFO:${RESET} ${GREEN}Expac Version: expac ${ORANGE}${version}${RESET}"
                    fi
                    ;;
                *)
                    formatted_message="${formatted_timestamp} ${BOLD}${GREEN}INFO:${RESET} $message"
                    ;;
            esac
            echo -e "$formatted_message"
            ;;
    esac
    
    # Logfile Ausgabe ohne ANSI Farben
    [ "${LOG_TO_FILE,,}" = "yes" ] && echo "$log_message" >> "$LOG_FILE"
}

# Vereinfachte Log-Wrapper (diese nur einmal aufrufen!)
log_error() { log "ERROR" "$1"; }
log_warning() { log "WARNING" "$1"; }
log_info() { log "INFO" "$1"; }



# --- Hilfsfunktionen ---
cleanup_logs() {
    local max_logs=5
    local log_pattern="backup_*.log"
    
    cd "$LOG_DIR" || return
    if [ -f "$LOG_FILE" ]; then
        mv "$LOG_FILE" "${LOG_FILE%.log}_$(date +'%Y%m%d_%H%M%S').log"
    fi
    
    ls -t $log_pattern 2>/dev/null | tail -n +$((max_logs + 1)) | xargs -r rm
    
    if [ -f "$ERROR_LOG" ]; then
        mv "$ERROR_LOG" "${ERROR_LOG%.log}_$(date +'%Y%m%d_%H%M%S').log"
    fi
}

cleanup() {
    local exit_code=$?
    if [ -d "${TEMP_BASE_DIR}" ]; then
        log_info "Räume temporäre Dateien auf..."
        kill_processes "${TEMP_BASE_DIR}"
        rm -rf "${TEMP_BASE_DIR}"
        mkdir -p "${TEMP_BASE_DIR}"
    fi
    
    if [ $exit_code -eq 0 ]; then
        cleanup_logs
    fi
    
    return $exit_code
}

# Im "Systemkonfigurationen sichern" Abschnitt und für die Home-Verzeichnisse:
cp_with_error_handling() {
    local source="${@: -2:1}"  # Vorletztes Argument ist die Quelle
    local dest="${@: -1}"      # Letztes Argument ist das Ziel
    local error_output
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    
    if [ ! -e "$source" ]; then
        # Komplette Zeile in Rot
        echo -e "${RED}[${timestamp}] ERROR: Datei/Verzeichnis nicht gefunden: $source${RESET}"
        return 0  # Rückgabe 0, damit das Skript weiterläuft
    fi

    # Fehlerausgabe in Variable speichern
    if ! error_output=$(cp "$@" 2>&1); then
        echo -e "${RED}[${timestamp}] ERROR: Fehler beim Kopieren von $source nach $dest: $error_output${RESET}"
        return 0  # Rückgabe 0, damit das Skript weiterläuft
    fi
    
    return 0
}

# Für die Home-Verzeichnisse:
#log_info "Sichere wichtige Verzeichnisse..."
#for dir in "${HOME_DIRS[@]}"; do
#    if [ -d "${USER_HOME}/${dir}" ]; then
#        log_info "Sichere ${dir}..."
#        cp_with_error_handling -r "${USER_HOME}/${dir}" "$BASE_BACKUP_DIR/"
#    else
#        # Fehlermeldung für nicht vorhandene Verzeichnisse
#        timestamp=$(date +'%Y-%m-%d %H:%M:%S')
#        echo -e "${RED}[${timestamp}] ERROR: Verzeichnis nicht gefunden: ${USER_HOME}/${dir}${RESET}"
#    fi
#done


# Optional: Eine zusätzliche Funktion für die Fehlerbehandlung der Hauptoperationen
handle_operation_error() {
    local operation="$1"
    local target="$2"
    local error_msg="$3"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    
    echo -e "${RED}[${timestamp}] ERROR: Fehler bei $operation von $target: $error_msg${RESET}"
}


kill_processes() {
    local dir="$1"
    local pids
    
    pids=$(lsof +D "$dir" 2>/dev/null | awk 'NR>1 {print $2}' | sort -u)
    
    if [ -n "$pids" ]; then
        log_info "Beende Prozesse mit offenen Dateien..."
        echo "$pids" | xargs -r kill 2>/dev/null || true
        sleep 1
        echo "$pids" | xargs -r kill -9 2>/dev/null || true
    fi
}

# --- System-Erkennung Funktionen ---
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_NAME="$ID"
        if [ -n "${VERSION_ID:-}" ]; then
            DISTRO_VERSION="$VERSION_ID"
        elif [ -n "${BUILD_ID:-}" ]; then
            DISTRO_VERSION="$BUILD_ID"
        else
            DISTRO_VERSION=""
        fi
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        DISTRO_NAME="$DISTRIB_ID"
        DISTRO_VERSION="$DISTRIB_RELEASE"
    else
        DISTRO_NAME="unknown"
        DISTRO_VERSION="unknown"
    fi
    
    DISTRO_NAME=$(echo "$DISTRO_NAME" | tr '[:upper:]' '[:lower:]')
    
    if [ -n "$DISTRO_VERSION" ]; then
        log_info "Erkannte Distribution: $DISTRO_NAME ($DISTRO_VERSION)"
    else
        log_info "Erkannte Distribution: $DISTRO_NAME"
    fi
}

# --- Weitere Funktionen ---

# --- Backup-spezifische Funktionen ---

# Desktop Environment spezifische Backup-Funktionen
backup_gnome_settings() {
    log_info "Sichere zusätzliche GNOME-Einstellungen..."
    
    # Extensions und Konfigurationen
    mkdir -p "$BASE_BACKUP_DIR/gnome"
    
    # Extension-Einstellungen
    if [ -d "${USER_HOME}/.local/share/gnome-shell/extensions" ]; then
        cp_with_error_handling -r "${USER_HOME}/.local/share/gnome-shell/extensions" "$BASE_BACKUP_DIR/gnome/"
    fi
    
    # Globale GNOME-Einstellungen
    sudo -u "$SUDO_USER" dconf dump / > "$BASE_BACKUP_DIR/gnome/all-settings.dconf"
    
    # Desktop-Einstellungen
    sudo -u "$SUDO_USER" dconf dump /org/gnome/desktop/ > "$BASE_BACKUP_DIR/gnome/desktop-settings.dconf"
    
    # Shell-Einstellungen
    sudo -u "$SUDO_USER" dconf dump /org/gnome/shell/ > "$BASE_BACKUP_DIR/gnome/shell-settings.dconf"
    
    # Tastenkombinationen
    sudo -u "$SUDO_USER" dconf dump /org/gnome/desktop/wm/keybindings/ > "$BASE_BACKUP_DIR/gnome/keyboard-shortcuts.dconf"
    sudo -u "$SUDO_USER" dconf dump /org/gnome/settings-daemon/plugins/media-keys/ > "$BASE_BACKUP_DIR/gnome/media-keys.dconf"
    
    # Benutzerdefinierte Tastenkombinationen
    sudo -u "$SUDO_USER" dconf dump /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ > "$BASE_BACKUP_DIR/gnome/custom-shortcuts.dconf"
}

backup_kde_settings() {
    log_info "Sichere zusätzliche KDE-Einstellungen..."
    
    mkdir -p "$BASE_BACKUP_DIR/kde"
    
    # KDE Konfigurationsdateien
    if [ -d "${USER_HOME}/.config" ]; then
        for config in plasma* kde* kwin* k*rc; do
            cp_with_error_handling -r "${USER_HOME}/.config/$config" "$BASE_BACKUP_DIR/kde/" 2>/dev/null || true
        done
    fi
    
    # KDE Lokale Daten
    if [ -d "${USER_HOME}/.local/share" ]; then
        for data in plasma* kde*; do
            cp_with_error_handling -r "${USER_HOME}/.local/share/$data" "$BASE_BACKUP_DIR/kde/" 2>/dev/null || true
        done
    fi
    
    # Spezielle KDE-Einstellungen
    cp_with_error_handling -r "${USER_HOME}/.kde4" "$BASE_BACKUP_DIR/kde/" 2>/dev/null || true
    cp_with_error_handling -r "${USER_HOME}/.kde" "$BASE_BACKUP_DIR/kde/" 2>/dev/null || true
}

backup_xfce_settings() {
    log_info "Sichere zusätzliche XFCE-Einstellungen..."
    
    mkdir -p "$BASE_BACKUP_DIR/xfce"
    
    # XFCE4 Konfiguration
    if [ -d "${USER_HOME}/.config/xfce4" ]; then
        cp_with_error_handling -r "${USER_HOME}/.config/xfce4" "$BASE_BACKUP_DIR/xfce/"
    fi
    
    # Thunar-Einstellungen
    if [ -d "${USER_HOME}/.config/Thunar" ]; then
        cp_with_error_handling -r "${USER_HOME}/.config/Thunar" "$BASE_BACKUP_DIR/xfce/"
    fi
    
    # Weitere XFCE-spezifische Konfigurationen
    for config in xfce4-session xfce4-panel xfconf xfwm4; do
        if [ -d "${USER_HOME}/.config/$config" ]; then
            cp_with_error_handling -r "${USER_HOME}/.config/$config" "$BASE_BACKUP_DIR/xfce/"
        fi
    done
}

detect_desktop_environment() {
    if [ -n "$XDG_CURRENT_DESKTOP" ]; then
        DE="$XDG_CURRENT_DESKTOP"
    elif [ -n "$DESKTOP_SESSION" ]; then
        DE="$DESKTOP_SESSION"
    else
        DE="unknown"
    fi
    
    DE=$(echo "$DE" | tr '[:upper:]' '[:lower:]')
    log_info "Erkanntes Desktop Environment: $DE"
    export DE
}

configure_package_manager() {
    case "$DISTRO_NAME" in
        "arch"|"endeavouros"|"manjaro"|"cachyos"|"garuda")
            PKG_MANAGER="pacman"
            PKG_MANAGER_INSTALL="pacman -S --noconfirm"
            PKG_MANAGER_LIST="pacman -Qqe"
            PKG_MANAGER_UPDATE="pacman -Syy"
            AUR_HELPER="yay"
            AUR_HELPER_LIST="sudo -u ${SUDO_USER} yay -Qm"
            AUR_HELPER_INSTALL="sudo -u ${SUDO_USER} yay -S --noconfirm"
            USE_AUR=true
            ;;
        "ubuntu"|"debian"|"linuxmint"|"pop"|"kali")
            PKG_MANAGER="apt"
            PKG_MANAGER_INSTALL="apt-get install -y"
            PKG_MANAGER_LIST="dpkg --get-selections | grep -v deinstall | cut -f1"
            PKG_MANAGER_UPDATE="apt-get update"
            USE_AUR=false
            ;;
        "fedora")
            PKG_MANAGER="dnf"
            PKG_MANAGER_INSTALL="dnf install -y"
            PKG_MANAGER_LIST="dnf list installed | cut -d' ' -f1"
            PKG_MANAGER_UPDATE="dnf check-update"
            USE_AUR=false
            ;;
        "opensuse"|"suse")
            PKG_MANAGER="zypper"
            PKG_MANAGER_INSTALL="zypper install -y"
            PKG_MANAGER_LIST="zypper search -i | tail -n+5 | cut -d'|' -f2"
            PKG_MANAGER_UPDATE="zypper refresh"
            USE_AUR=false
            ;;
        *)
            log_error "Distribution '$DISTRO_NAME' nicht erkannt"
            exit 1
            ;;
    esac
}

check_base_dependencies() {
    local base_deps=("rsync" "pigz" "expac")
    local missing_base_deps=()
    local gpg_package="gnupg"

    log_info "Prüfe Basis-Abhängigkeiten..."

    if [ -z "$DISTRO_NAME" ]; then
        log_error "Distribution konnte nicht erkannt werden"
        exit 1
    fi

    if [[ "$DISTRO_NAME" =~ ^(arch|endeavouros|manjaro|cachyos|garuda)$ ]]; then
        if ! command -v expac &> /dev/null; then
            missing_base_deps+=("expac")
        else
            local expac_version=$(expac -V 2>/dev/null || echo "nicht verfügbar")
            log_info "Expac Version: ${expac_version}"
        fi
    else
        base_deps=("${base_deps[@]/expac}")
    fi

    if ! command -v gpg &> /dev/null || ! gpg --version &> /dev/null; then
        case "$DISTRO_NAME" in
            "arch"|"endeavouros"|"manjaro"|"cachyos"|"garuda") gpg_package="gnupg" ;;
            "ubuntu"|"debian"|"linuxmint"|"pop"|"kali") gpg_package="gnupg2" ;;
            "fedora") gpg_package="gnupg2" ;;
            "opensuse"|"suse") gpg_package="gpg2" ;;
        esac
        missing_base_deps+=("$gpg_package")
    fi

    # Fehlende Abhängigkeiten installieren wenn nötig
    if [ ${#missing_base_deps[@]} -ne 0 ]; then
        log_info "Installiere fehlende Basis-Abhängigkeiten: ${missing_base_deps[*]}"
        if ! eval "$PKG_MANAGER_INSTALL ${missing_base_deps[*]}"; then
            log_error "Installation der Basis-Abhängigkeiten fehlgeschlagen"
            exit 1
        fi
    else
        log_info "Alle Basis-Abhängigkeiten sind bereits installiert"
    fi

    if command -v gpg &> /dev/null; then
        local gpg_version=$(gpg --version | head -n 1)
        log_info "GPG ist installiert: $gpg_version"
    fi
}

backup_ssh() {
    if [ "${BACKUP_SSH,,}" != "yes" ]; then
        return 0
    fi

    local backup_dir="$1"
    local ssh_dir="$backup_dir/ssh"
    
    log_info "Sichere SSH-Konfiguration..."
    
    if [ -d "${USER_HOME}/.ssh" ]; then
        mkdir -p "$ssh_dir"
        
        # Immer diese Dateien sichern
        for file in "config" "known_hosts" "authorized_keys"; do
            if [ -f "${USER_HOME}/.ssh/$file" ]; then
                cp_with_error_handling "${USER_HOME}/.ssh/$file" "$ssh_dir/" 2>/dev/null || true
            fi
        done
        
        # Private Schlüssel nur sichern wenn gewünscht und Backup verschlüsselt wird
        if [ "${BACKUP_SSH_KEYS,,}" = "yes" ] && [ "$ENCRYPT" = true ]; then
            log_info "Sichere SSH-Schlüssel..."
            cp_with_error_handling "${USER_HOME}/.ssh/id_"* "$ssh_dir/" 2>/dev/null || true
        fi
        
        # Berechtigungen setzen
        chmod 700 "$ssh_dir"
        chmod 600 "$ssh_dir"/*
    else
        log_info "Kein .ssh Verzeichnis gefunden, überspringe..."
    fi
}

backup_desktop_settings() {
    case "$DE" in
        *"gnome"*)
            log_info "Sichere GNOME-Einstellungen..."
            cp_with_error_handling -r "${USER_HOME}/.local/share/gnome-shell/extensions/" "$BASE_BACKUP_DIR/gnome_extensions"
            sudo -u "$SUDO_USER" dconf dump / > "$BASE_BACKUP_DIR/gnome-settings-backup.dconf"
            
            # Tastenkürzel sichern
            for shortcut in "desktop/wm/keybindings" "settings-daemon/plugins/media-keys" "shell/keybindings"; do
                sudo -u "$SUDO_USER" dconf dump "/org/gnome/${shortcut}/" > "$BASE_BACKUP_DIR/gnome-shortcuts-${shortcut//\//-}.dconf"
            done
            ;;
        *"kde"*|*"plasma"*)
            log_info "Sichere KDE-Einstellungen..."
            cp_with_error_handling -r "${USER_HOME}/.config/plasma-*" "$BASE_BACKUP_DIR/"
            cp_with_error_handling -r "${USER_HOME}/.local/share/plasma*" "$BASE_BACKUP_DIR/"
            cp_with_error_handling -r "${USER_HOME}/.config/kde*" "$BASE_BACKUP_DIR/"
            ;;
        *"xfce"*)
            log_info "Sichere XFCE-Einstellungen..."
            cp_with_error_handling -r "${USER_HOME}/.config/xfce4" "$BASE_BACKUP_DIR/"
            cp_with_error_handling -r "${USER_HOME}/.config/Thunar" "$BASE_BACKUP_DIR/"
            ;;
    esac
}

# Vor der Hauptlogik einfügen:

create_package_lists() {
    local backup_dir="$1"
    local temp_dir="${TEMP_BASE_DIR}/packages_$$"
    mkdir -p "$temp_dir"
    
    log_info "Erstelle Paketlisten für $DISTRO_NAME..."
    
    case "$DISTRO_NAME" in
    "arch"|"endeavouros"|"manjaro"|"cachyos"|"garuda")
        # Alle installierten Pakete mit Zeitstempel (nur für Referenz)
        log_info "Erstelle erweiterte Paketliste mit Installationsdaten..."
        expac --timefmt='%Y-%m-%d %T' '%l\t%n' | sort -r > "$backup_dir/all_packages_timestamps.txt" || {
            log_error "Fehler beim Erstellen der Paketliste (Zeile ${LINENO})"
            return 1
        }
        
        # Basis-Paketlisten erstellen
        if [ "$USE_AUR" = true ] && [ -n "$AUR_HELPER" ]; then
            # System-Pakete
            pacman -Qqen > "$backup_dir/pacman_packages.txt" || true
            
            # AUR-Pakete separat auflisten
            sudo -u "$SUDO_USER" yay -Qqem > "$backup_dir/aur_packages.txt" || true
            
            # Zählen der Pakete
            local pacman_count=0
            local aur_count=0
            [ -f "$backup_dir/pacman_packages.txt" ] && pacman_count=$(wc -l < "$backup_dir/pacman_packages.txt" 2>/dev/null || echo 0)
            [ -f "$backup_dir/aur_packages.txt" ] && aur_count=$(wc -l < "$backup_dir/aur_packages.txt" 2>/dev/null || echo 0)
            
            log_info "Gefunden: $pacman_count System-Pakete und $aur_count AUR-Pakete"
        else
            # Wenn kein AUR verwendet wird, nur System-Pakete speichern
            pacman -Qqen > "$backup_dir/pacman_packages.txt" || true
            
            local package_count=0
            [ -f "$backup_dir/pacman_packages.txt" ] && package_count=$(wc -l < "$backup_dir/pacman_packages.txt" 2>/dev/null || echo 0)
            log_info "Gefunden: $package_count installierte Pakete"
        fi
        ;;
            
        "ubuntu"|"debian"|"linuxmint"|"pop")
            # Für Debian-basierte Systeme
            dpkg-query -l | awk '/^ii/ {printf "%-30s %-30s %s\n", $2, $3, $6}' | sort > "$backup_dir/packages_detailed.txt"
            dpkg --get-selections | grep -v deinstall | cut -f1 > "$backup_dir/packages.txt"
            log_info "Gefunden: $(wc -l < "$backup_dir/packages.txt") installierte Pakete"
            ;;
            
        "fedora")
            # Für Fedora
            rpm -qa --queryformat '%-30{NAME} %-30{VERSION} %{INSTALLTIME:date}\n' | sort > "$backup_dir/packages_detailed.txt"
            rpm -qa --queryformat '%{NAME}\n' | sort > "$backup_dir/packages.txt"
            log_info "Gefunden: $(wc -l < "$backup_dir/packages.txt") installierte Pakete"
            ;;
            
        "opensuse"|"suse")
            # Für openSUSE
            rpm -qa --queryformat '%-30{NAME} %-30{VERSION} %{INSTALLTIME:date}\n' | sort > "$backup_dir/packages_detailed.txt"
            zypper search -i | tail -n+5 | cut -d'|' -f2 | sort > "$backup_dir/packages.txt"
            log_info "Gefunden: $(wc -l < "$backup_dir/packages.txt") installierte Pakete"
            ;;
    esac
    
    # Flatpak-Liste erstellen (falls installiert)
    if command -v flatpak &> /dev/null; then
        # Normale Liste für Installation
        sudo -u "$SUDO_USER" flatpak list --app --columns=application > "$backup_dir/flatpak_packages.txt" 2>/dev/null || true
        if [ -f "$backup_dir/flatpak_packages.txt" ]; then
            flatpak_count=$(wc -l < "$backup_dir/flatpak_packages.txt" 2>/dev/null || echo 0)
            log_info "Gefunden: $flatpak_count Flatpak-Anwendungen"
            sudo -u "$SUDO_USER" flatpak remote-list --columns=name,url > "$backup_dir/flatpak_remotes.txt" 2>/dev/null || true
        fi
    fi
    
    # Snap-Liste erstellen (falls installiert)
    if command -v snap &> /dev/null; then
        # Detaillierte Liste mit zusätzlichen Informationen
        snap list --color=never > "$backup_dir/snap_packages_detailed.txt" 2>/dev/null || true
        # Einfache Liste für Installation
        snap list 2>/dev/null | tail -n+2 | awk '{print $1}' > "$backup_dir/snap_packages.txt" || true
        if [ -f "$backup_dir/snap_packages.txt" ]; then
            snap_count=$(wc -l < "$backup_dir/snap_packages.txt" 2>/dev/null || echo 0)
            log_info "Gefunden: $snap_count Snap-Pakete"
        fi
    fi
    
    rm -rf "$temp_dir" 2>/dev/null || true
    return 0
}


compress_backup() {
    local source_dir="$1"
    local target_archive="$2"
    local use_encryption="$3"
    local compression_level=1
    local cpu_cores=$(nproc)
    local temp_dir="${TEMP_BASE_DIR}/compress_$$"
    
    # Ursprungsgröße ermitteln
    local source_size=$(du -sb "$source_dir" | cut -f1)
    log_info "Ursprungsgröße: $(numfmt --to=iec-i --suffix=B $source_size)"
    
    # Benötigten Speicherplatz berechnen (Original + 30% für Komprimierung und Temp-Dateien)
    local required_space=$(( source_size + (source_size * 30 / 100) ))
    
    mkdir -p "$temp_dir"
    
    # Prüfen ob genügend Speicherplatz verfügbar ist
    if ! check_disk_space "$(dirname "$target_archive")" "$required_space"; then
        rm -rf "$temp_dir"
        exit 1
    fi
    
    log_info "Starte Komprimierung mit $((cpu_cores-1)) CPU-Kernen..."
    
    if [ "$use_encryption" = true ]; then
        # Temporäres unverschlüsseltes Archiv erstellen
        local temp_archive="$temp_dir/backup.tar.gz"
        
        # Komprimierung
        tar --use-compress-program="pigz -p $((cpu_cores-1)) -$compression_level" -cf "$temp_archive" \
            -C "$(dirname "$source_dir")" "$(basename "$source_dir")" 2>/dev/null
        
        log_info "Verschlüssele Backup..."
        get_backup_password "$password_file" | gpg --batch --yes --passphrase-fd 0 -c \
            --cipher-algo AES256 --output "$target_archive" "$temp_archive"
        
    else
        # Normale Komprimierung ohne Verschlüsselung
        tar --use-compress-program="pigz -p $((cpu_cores-1)) -$compression_level" -cf "$target_archive" \
            -C "$(dirname "$source_dir")" "$(basename "$source_dir")" 2>/dev/null
    fi
    
    # Finale Größe berechnen
    if [ -f "$target_archive" ]; then
        local final_size=$(du -sh "$target_archive" | cut -f1)
        log_info "Komprimierte Größe: $final_size"
    else
        log_error "Backup-Archiv wurde nicht erstellt"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # Temporäres Verzeichnis aufräumen
    rm -rf "$temp_dir"
}

check_disk_space() {
    local path="$1"
    local required_space="$2"  # in Bytes
    
    # Verfügbaren Speicherplatz ermitteln (in Bytes)
    local available_space=$(df --output=avail -B1 "$path" | tail -n1)
    
    if [ "$available_space" -lt "$required_space" ]; then
        log_error "Nicht genügend Speicherplatz verfügbar"
        log_error "Verfügbar: $(numfmt --to=iec-i --suffix=B $available_space)"
        log_error "Benötigt: $(numfmt --to=iec-i --suffix=B $required_space)"
        return 1
    fi
    return 0
}

get_backup_password() {
    local password_file="$1"
    local key_file="${USER_HOME}/.backup_key"
    
    if [ -n "${BACKUP_PASSWORD:-}" ]; then
        # Passwort aus Umgebungsvariable verwenden
        echo "$BACKUP_PASSWORD"
    elif [ -f "$password_file" ] && [ -f "$key_file" ]; then
        # Passwort aus verschlüsselter Datei lesen
        openssl enc -aes-256-cbc -salt -pbkdf2 -d -in "$password_file" -pass file:"$key_file"
    else
        log_error "Keine Passwortdatei oder Umgebungsvariable gefunden."
        log_error "Erstellen Sie eine Passwortdatei mit: $0 -create-pw"
        exit 1
    fi
}

create_password_file() {
    local password_file="$1"
    local temp_key_file="/tmp/backup_key_$$"
    
    # Zufälligen Schlüssel generieren
    openssl rand -hex 32 > "$temp_key_file"
    
    # Passwort zweimal abfragen
    while true; do
        read -s -p "Backup-Passwort eingeben: " password
        echo
        read -s -p "Backup-Passwort wiederholen: " password2
        echo
        
        if [ "$password" = "$password2" ]; then
            break
        else
            echo "Passwörter stimmen nicht überein. Bitte erneut versuchen."
        fi
    done
    
    # Passwort verschlüsselt speichern
    echo "$password" | openssl enc -aes-256-cbc -salt -pbkdf2 -in - -out "$password_file" -pass file:"$temp_key_file"
    
    # Schlüssel sicher in Home-Verzeichnis speichern
    mv "$temp_key_file" "${USER_HOME}/.backup_key"
    chmod 600 "${USER_HOME}/.backup_key"
    chmod 600 "$password_file"
    
    echo "Passwortdatei und Schlüssel wurden erstellt:"
    echo "Passwortdatei: $password_file"
    echo "Schlüsseldatei: ${USER_HOME}/.backup_key"
    echo "Bitte bewahren Sie beide Dateien sicher auf!"
}

get_backup_path() {
    local base_path="$1"
    
    if [ "${USE_TIMESTAMP,,}" = "yes" ]; then
        local timestamp=$(date +"$TIMESTAMP_FORMAT")
        echo "${base_path}_${timestamp}"
    else
        echo "$base_path"
    fi
}

# Direkt vor der Hauptlogik im TEIL 4: FUNKTIONEN einfügen:

create_rsync_excludes() {
    local excludes=("$@")
    local rsync_excludes=""
    for exclude in "${excludes[@]}"; do
        rsync_excludes+=" --exclude='$exclude'"
    done
    echo "$rsync_excludes"
}

backup_with_rsync() {
    local source="$1"
    local target="$2"
    local excludes="${3:-}"
    
    if [ -d "$source" ]; then
        local rsync_cmd="rsync -a $excludes \"$source\" \"$target\""
        eval $rsync_cmd
    else
        log_info "Verzeichnis $source existiert nicht, überspringe..."
    fi
}



# ==============================================================================
# TEIL 5: HAUPTLOGIK
# ==============================================================================

# --- PHASE 1: GRUNDLEGENDE CHECKS ---
# Prüfen ob Script als root läuft
# TEIL 5: HAUPTLOGIK

# --- PHASE 1: GRUNDLEGENDE CHECKS ---
if [ "$EUID" -ne 0 ]; then 
    echo "Dieses Script muss mit sudo-Rechten ausgeführt werden!"
    exit 1
fi

# --- PHASE 2: BENUTZER UND PARAMETER ---
# Benutzer-Home-Verzeichnis setzen
if [ -n "${SUDO_USER:-}" ]; then
    export USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    if [ -z "$USER_HOME" ]; then
        echo -e "${RED}Fehler: Konnte Home-Verzeichnis für $SUDO_USER nicht ermitteln${RESET}"
        exit 1
    fi
else
    echo -e "${RED}Fehler: SUDO_USER nicht gesetzt${RESET}"
    exit 1
fi

# Logging initialisieren
init_logging

# Parameter verarbeiten
COMPRESS=false
ENCRYPT=false
CREATE_PW=false
password_file="${USER_HOME}/.backup_password"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -zip)
            COMPRESS=true
            ;;
        -pw)
            COMPRESS=true
            ENCRYPT=true
            ;;
        -create-pw)
            CREATE_PW=true
            ;;
        *)
            echo "Unbekannte Option: $1"
            echo "Verwendung: $0 [-zip] [-pw] [-create-pw]"
            exit 1
            ;;
    esac
    shift
done

if [ "$CREATE_PW" = true ]; then
    create_password_file "$password_file"
    echo "Passwortdatei wurde erstellt. Starten Sie das Backup erneut mit der Option -pw"
    exit 0
fi

# --- PHASE 3: SYSTEM-ERKENNUNG UND ABHÄNGIGKEITEN ---
log_info "Prüfe System und Abhängigkeiten..."
detect_distro
detect_desktop_environment
check_base_dependencies
configure_package_manager

# --- PHASE 4: BACKUP VORBEREITUNG ---
log_info "Initialisiere Backup-Prozess..."
log_info "Benutzer-Home-Verzeichnis: $USER_HOME"

# Backup-Pfad vorbereiten
BASE_BACKUP_DIR=$(get_backup_path "$BASE_BACKUP_DIR")
mkdir -p "$TEMP_BASE_DIR"

# Backup-Verzeichnisse erstellen
log_info "Erstelle Backup-Verzeichnisse..."
for dir in "${BACKUP_SUBDIRS[@]}"; do
    mkdir -p "$dir"
done

# Paketlisten erstellen
create_package_lists "$BASE_BACKUP_DIR"

# --- PHASE 5: BACKUP DURCHFÜHRUNG ---
log_info "Starte Backup-Prozess..."

# Dann erst die eigentlichen Backup-Funktionen aufrufen
backup_desktop_settings
backup_ssh "$BASE_BACKUP_DIR"


# Desktop-Environment spezifische Backups
log_info "Sichere Desktop-Environment spezifische Einstellungen..."
case "$DE" in
    *"gnome"*) backup_gnome_settings ;;
    *"kde"*|*"plasma"*) backup_kde_settings ;;
    *"xfce"*) backup_xfce_settings ;;
esac

# Systemkonfigurationen sichern
log_info "Sichere Systemkonfigurationen..."
for config in "${SYSTEM_CONFIGS[@]}"; do
    cp_with_error_handling "/etc/$config" "${BACKUP_SUBDIRS[etc]}/$config"
done

for dir in "${SYSTEM_CONFIG_DIRS[@]}"; do
    cp_with_error_handling -r "/etc/$dir" "${BACKUP_SUBDIRS[etc]}/$dir"
done

# NetworkManager Verbindungen sichern
log_info "Sichere NetworkManager-Konfigurationen..."
cp_with_error_handling -r /etc/NetworkManager/system-connections "${BACKUP_SUBDIRS[etc]}/NetworkManager_system-connections"

# /usr/share Verzeichnisse sichern
#log_info "Sichere /usr/share Verzeichnisse..."

# Icons sichern
mkdir -p "${BACKUP_SUBDIRS[usr_share]}/icons"
for icon in "${ICONS[@]}"; do
    if [ -d "/usr/share/icons/$icon" ]; then
        log_info "Sichere Icon-Theme: $icon"
        cp_with_error_handling -r "/usr/share/icons/$icon" "${BACKUP_SUBDIRS[usr_share]}/icons/"
    fi
done


# Applications sichern
#log_info "Sichere ausgewählte .desktop Dateien..."
#mkdir -p "${BACKUP_SUBDIRS[usr_share]}/applications"
#for app in "${APPLICATIONS[@]}"; do
#    found_files=$(find /usr/share/applications -name "$app" -type f)
#    if [ -n "$found_files" ]; then
#        file_count=$(echo "$found_files" | wc -l)
#        log_info "Gefunden: $file_count .desktop Dateien für Muster '$app'"
#        while IFS= read -r file; do
#            filename=$(basename "$file")
#            cp_with_error_handling "$file" "${BACKUP_SUBDIRS[usr_share]}/applications/"
#        done <<< "$found_files"
#    else
#        log_info "Keine .desktop Dateien gefunden für Muster: $app"
#    fi
#done

# Themes sichern
if [ -d "/usr/share/themes" ]; then
    log_info "Sichere Themes..."
    mkdir -p "${BACKUP_SUBDIRS[usr_share]}/themes"
    cp_with_error_handling -r /usr/share/themes/* "${BACKUP_SUBDIRS[usr_share]}/themes/" 2>/dev/null || true
fi

# Flatpak-Einstellungen und Daten sichern
if command -v flatpak &> /dev/null; then
    log_info "Sichere Flatpak-Einstellungen und Daten..."
    cp_with_error_handling -r "${USER_HOME}/.local/share/flatpak" "$BASE_BACKUP_DIR/flatpak_data"
    cp_with_error_handling -r "${USER_HOME}/.var/app" "$BASE_BACKUP_DIR/flatpak_apps"
fi

# Dotfiles sichern
log_info "Sichere Dotfiles..."
for file in "${DOTFILES[@]}"; do
    cp_with_error_handling -a "${USER_HOME}/${file}" "$BASE_BACKUP_DIR/" 2>/dev/null || true
done

# Home-Verzeichnisse sichern
log_info "Sichere wichtige Verzeichnisse..."
for dir in "${HOME_DIRS[@]}"; do
    source="${USER_HOME}/${dir}"
    target="$BASE_BACKUP_DIR/${dir}"
    
    if [ -d "$source" ]; then
        log_info "Sichere ${dir}..."
        # Zielverzeichnis erstellen
        mkdir -p "$target"
        # Komplettes Verzeichnis mit Struktur kopieren
        cp_with_error_handling -r "$source/." "$target/"
    else
        timestamp=$(date +'%Y-%m-%d %H:%M:%S')
        echo -e "${RED}[${timestamp}] ERROR: Verzeichnis nicht gefunden: $source${RESET}"
    fi
done

# .cache Ordner sichern
log_info "Sichere .cache Ordner..."
cache_excludes=$(create_rsync_excludes "${CACHE_EXCLUDES[@]}")
backup_with_rsync "${USER_HOME}/.cache" "$BASE_BACKUP_DIR" "$cache_excludes"

# .config Ordner sichern
log_info "Sichere .config Ordner..."
backup_with_rsync "${USER_HOME}/.config" "$BASE_BACKUP_DIR"

# .local Ordner sichern
log_info "Sichere .local Ordner..."
local_excludes=$(create_rsync_excludes "${LOCAL_EXCLUDES[@]}")
backup_with_rsync "${USER_HOME}/.local" "$BASE_BACKUP_DIR" "$local_excludes"

# Persönliche Ordner sichern
log_info "Sichere persönliche Ordner..."
for dir in "${PERSONAL_DIRS[@]}"; do
    if [ -d "${USER_HOME}/${dir}" ] && [ "$(ls -A "${USER_HOME}/${dir}")" ]; then
        mkdir -p "$BASE_BACKUP_DIR/$dir"
        cp_with_error_handling -r "${USER_HOME}/${dir}"/* "$BASE_BACKUP_DIR/$dir/"
    fi
done

# Backup abschließen
if [ "$COMPRESS" = true ]; then
    log_info "Beginne mit der Komprimierung..."
    if [ "$ENCRYPT" = true ]; then
        backup_archive="${BASE_BACKUP_DIR%/}.tar.gz.gpg"
    else
        backup_archive="${BASE_BACKUP_DIR%/}.tar.gz"
    fi
    
    trap cleanup EXIT ERR
    compress_backup "$BASE_BACKUP_DIR" "$backup_archive" "$ENCRYPT"
    trap - EXIT ERR
    
    log_info "Räume auf..."
    rm -rf "$BASE_BACKUP_DIR"
    rm -rf "$TEMP_BASE_DIR"
    
    chown -R "$SUDO_USER:$SUDO_USER" "$backup_archive"
    
    log_info "Backup abgeschlossen. Archiv wurde erstellt: $backup_archive"
else
    chown -R "$SUDO_USER:$SUDO_USER" "$BASE_BACKUP_DIR"
    backup_size=$(du -sh "$BASE_BACKUP_DIR" | cut -f1)
    log_info "Backup abgeschlossen. Dateien befinden sich in: $BASE_BACKUP_DIR"
    log_info "Backup-Größe: $backup_size"
fi

