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
BASE_BACKUP_DIR="/mnt/Daten/lichti"
TEMP_BASE_DIR="/var/tmp/bkp"

# --- Logging Konfiguration ---
LOG_TO_FILE="yes"          # "yes" oder "no" - Logging in Datei aktivieren
LOG_ERRORS="yes"          # "yes" oder "no" - Separate Fehlerprotokollierung
LOG_DIR="/home/log/"
LOG_FILE="${LOG_DIR}/backup.log"
ERROR_LOG="${LOG_DIR}/backup_error.log"
MAX_LOG_FILES=5           # Anzahl der zu behaltenden Log-Dateien

# --- Farbdefinitionen (erweitert) ---
BLUE='\e[34m'
LIGHT_BLUE='\e[94m'
GREEN='\e[32m'
DARK_GREEN='\e[32;2m'
LIGHT_GREEN='\e[92m'
YELLOW='\e[33m'
LIGHT_YELLOW='\e[93m'
RED='\e[31m'
LIGHT_RED='\e[91m'
CYAN='\e[36m'
LIGHT_CYAN='\e[96m'
MAGENTA='\e[35m'
LIGHT_MAGENTA='\e[95m'
ORANGE='\e[38;5;208m'
WHITE='\e[97m'
GRAY='\e[90m'
BOLD='\e[1m'
DIM='\e[2m'
ITALIC='\e[3m'
UNDERLINE='\e[4m'
BLINK='\e[5m'
REVERSE='\e[7m'
RESET='\e[0m'

# Globale Variablen
DISTRO_NAME=""
DISTRO_VERSION=""
DE=""
PKG_MANAGER=""
PKG_MANAGER_INSTALL=""
PKG_MANAGER_LIST=""
PKG_MANAGER_UPDATE=""
AUR_HELPER=""
AUR_HELPER_LIST=""
AUR_HELPER_INSTALL=""
USE_AUR=false

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
    [home]="$BASE_BACKUP_DIR/home"
    [config]="$BASE_BACKUP_DIR/config"
    [local]="$BASE_BACKUP_DIR/local"
    [cache]="$BASE_BACKUP_DIR/cache"
)

# --- Arrays für zu sichernde Dateien ---
declare -a DOTFILES=(
    .zshrc
    .zsh_history
    .p10k.zsh
    .bashrc
    .bash_profile
    .bash_history
    .nvidia-settings-rc
    .gitconfig
    .gtkrc-2.0
    .xinitrc
    .Xresources
    .Xdefaults
    .dmrc
)

declare -a HOME_DIRS=(
    .vscode
    .thunderbird
    .mozilla
    .var
    .vmware
    .wine
    .icons
    .themes
    .fonts
    .docker
    Downloads
    Dokumente
    Bilder
    Desktop
    Musik
    Videos
    Vorlagen
    Öffentlich
)

declare -a SYSTEM_CONFIGS=(
    "fstab"
    "pacman.conf"
    "mkinitcpio.conf"
    "locale.conf"
    "hostname"
    "hosts"
    "resolv.conf"
    "sudoers"
    "default"
    "environment"
)

declare -a SYSTEM_CONFIG_DIRS=(
    "conf.d"
    "default"
    "ufw"
    "modprobe.d"
    "modules-load.d"
    "sysctl.d"
    "NetworkManager"
    "systemd"
    "X11"
    "apt"
    "pacman.d"
)

declare -a ICONS=(
    "Numix-Circle"
    "Numix"
    "Papirus"
    "breeze"
    "elementary"
)

declare -a THEMES=(
    "Adwaita"
    "Breeze"
    "Arc"
    "Numix"
    "elementary"
)

declare -a CACHE_EXCLUDES=(
    ".cache/yay"
    ".cache/mozilla"
    ".cache/chromium"
    ".cache/google-chrome"
    ".cache/thumbnails"
    ".cache/pip"
    ".cache/yarn"
    ".cache/npm"
)

declare -a LOCAL_EXCLUDES=(
    "share/Steam/steamapps/common"
    "share/Steam/ubuntu12_64"
    "share/Steam/steamapps/shadercache"
    "share/Trash"
    "share/lutris/runners"
    "share/lutris/runtime"
    "share/bottles/runners"
    "share/bottles/templates"
    "share/bottles/temp"
    "share/pnpm"
    "share/baloo"
    "share/webkit"
    "share/zeitgeist"
)

# --- Komprimierungsoptionen ---
COMPRESSION_LEVEL=1       # 1-9, wobei 1 schneller aber größer, 9 langsamer aber kleiner
COMPRESSION_THREADS=0     # 0 = automatisch (CPU Kerne - 1)

# ==============================================================================
# TEIL 2: LOGGING FUNKTIONEN
# ==============================================================================

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
    local max_logs="$MAX_LOG_FILES"
    local log_pattern="backup_*.log"
    
    cd "$LOG_DIR" || return
    if [ -f "$LOG_FILE" ]; then
        mv "$LOG_FILE" "${LOG_FILE%.log}_$(date +'%Y%m%d_%H%M%S').log"
    fi
    
    # Alte Logs entfernen
    ls -t $log_pattern 2>/dev/null | tail -n +$((max_logs + 1)) | xargs -r rm
    
    # Fehlerlog archivieren wenn vorhanden
    if [ -f "$ERROR_LOG" ]; then
        mv "$ERROR_LOG" "${ERROR_LOG%.log}_$(date +'%Y%m%d_%H%M%S').log"
    fi
}

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    local formatted_message
    local log_message="[$timestamp] $level: $message"
    local formatted_timestamp="${CYAN}[${timestamp}]${RESET}"
    
    # Terminal Ausgabe
    case "$level" in
        "ERROR")
            formatted_message="${formatted_timestamp} ${BOLD}${LIGHT_RED}ERROR:${RESET} ${RED}$message${RESET}"
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
            formatted_message="${formatted_timestamp} ${BOLD}${LIGHT_YELLOW}WARNING:${RESET} ${YELLOW}$message${RESET}"
            ;;
        "INFO")
            case "$message" in
                "Initialisiere"*|"Starte Backup"*)
                    formatted_message="${formatted_timestamp} ${BOLD}${LIGHT_GREEN}INFO:${RESET} ${GREEN}$message${RESET}"
                    ;;
                *"Verschlüssele"*|*"Komprimiere"*)
                    formatted_message="${formatted_timestamp} ${BOLD}${LIGHT_BLUE}INFO:${RESET} ${BLUE}$message${RESET}"
                    ;;
                *"Gefunden:"*)
                    if [[ $message =~ ([0-9]+)\ (.*)\ und\ ([0-9]+)\ (.*) ]]; then
                        formatted_message="${formatted_timestamp} ${BOLD}${LIGHT_GREEN}INFO:${RESET} ${GREEN}Gefunden: ${ORANGE}${BASH_REMATCH[1]}${GREEN} ${BASH_REMATCH[2]} und ${ORANGE}${BASH_REMATCH[3]}${GREEN} ${BASH_REMATCH[4]}${RESET}"
                    elif [[ $message =~ ([0-9]+)\ (.*) ]]; then
                        formatted_message="${formatted_timestamp} ${BOLD}${LIGHT_GREEN}INFO:${RESET} ${GREEN}Gefunden: ${ORANGE}${BASH_REMATCH[1]}${GREEN} ${BASH_REMATCH[2]}${RESET}"
                    else
                        formatted_message="${formatted_timestamp} ${BOLD}${LIGHT_GREEN}INFO:${RESET} ${GREEN}$message${RESET}"
                    fi
                    ;;
                "Sichere"*)
                    formatted_message="${formatted_timestamp} ${BOLD}${LIGHT_BLUE}INFO:${RESET} ${BLUE}$message${RESET}"
                    ;;
                *"Erstelle"*|*"Prüfe"*)
                    formatted_message="${formatted_timestamp} ${BOLD}${LIGHT_GREEN}INFO:${RESET} ${DARK_GREEN}$message${RESET}"
                    ;;
                *"GPG ist installiert:"*)
                    formatted_message="${formatted_timestamp} ${BOLD}${LIGHT_GREEN}INFO:${RESET} ${LIGHT_CYAN}$message${RESET}"
                    ;;
                *"Größe:"*|*"Size:"*)
                    formatted_message="${formatted_timestamp} ${BOLD}${LIGHT_GREEN}INFO:${RESET} ${MAGENTA}$message${RESET}"
                    ;;
                *"Abgeschlossen"*|*"Fertig"*)
                    formatted_message="${formatted_timestamp} ${BOLD}${LIGHT_GREEN}INFO:${RESET} ${GREEN}$message${RESET}"
                    ;;
                *)
                    formatted_message="${formatted_timestamp} ${BOLD}${LIGHT_GREEN}INFO:${RESET} $message"
                    ;;
            esac
            ;;
    esac
    
    echo -e "$formatted_message"
    [ "${LOG_TO_FILE,,}" = "yes" ] && echo "$log_message" >> "$LOG_FILE"
}

# Vereinfachte Log-Wrapper
log_error() { log "ERROR" "$1"; }
log_warning() { log "WARNING" "$1"; }
log_info() { log "INFO" "$1"; }

# ==============================================================================
# TEIL 3: SYSTEM-ERKENNUNG UND KONFIGURATION
# ==============================================================================

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
        log_info "Erkannte Distribution: ${BOLD}$DISTRO_NAME ($DISTRO_VERSION)${RESET}"
    else
        log_info "Erkannte Distribution: ${BOLD}$DISTRO_NAME${RESET}"
    fi
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
    log_info "Erkanntes Desktop Environment: ${BOLD}$DE${RESET}"
    export DE
}

configure_package_manager() {
    case "$DISTRO_NAME" in
        "arch"|"endeavouros"|"manjaro"|"cachyos"|"garuda")
            PKG_MANAGER="pacman"
            PKG_MANAGER_INSTALL="pacman -S --noconfirm"
            PKG_MANAGER_LIST="pacman -Qqe"
            PKG_MANAGER_UPDATE="pacman -Syy"
            PKG_MANAGER_QUERY="pacman -Qi"
            AUR_HELPER="yay"
            AUR_HELPER_LIST="sudo -u ${SUDO_USER} yay -Qm"
            AUR_HELPER_INSTALL="sudo -u ${SUDO_USER} yay -S --noconfirm"
            AUR_HELPER_QUERY="yay -Qi"
            USE_AUR=true
            ;;
        "ubuntu"|"debian"|"linuxmint"|"pop"|"kali")
            PKG_MANAGER="apt"
            PKG_MANAGER_INSTALL="apt-get install -y"
            PKG_MANAGER_LIST="dpkg --get-selections | grep -v deinstall | cut -f1"
            PKG_MANAGER_UPDATE="apt-get update"
            PKG_MANAGER_QUERY="dpkg -s"
            USE_AUR=false
            ;;
        "fedora")
            PKG_MANAGER="dnf"
            PKG_MANAGER_INSTALL="dnf install -y"
            PKG_MANAGER_LIST="dnf list installed | cut -d' ' -f1"
            PKG_MANAGER_UPDATE="dnf check-update"
            PKG_MANAGER_QUERY="rpm -qi"
            USE_AUR=false
            ;;
        "opensuse"|"suse")
            PKG_MANAGER="zypper"
            PKG_MANAGER_INSTALL="zypper install -y"
            PKG_MANAGER_LIST="zypper search -i | tail -n+5 | cut -d'|' -f2"
            PKG_MANAGER_UPDATE="zypper refresh"
            PKG_MANAGER_QUERY="rpm -qi"
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

    # Expac nur für Arch-basierte Systeme prüfen
    if [[ "$DISTRO_NAME" =~ ^(arch|endeavouros|manjaro|cachyos|garuda)$ ]]; then
        if ! command -v expac &> /dev/null; then
            missing_base_deps+=("expac")
        else
            local expac_version=$(expac -V 2>/dev/null || echo "nicht verfügbar")
            log_info "Expac Version: ${BOLD}${expac_version}${RESET}"
        fi
    else
        base_deps=("${base_deps[@]/expac}")
    fi

    # Weitere Basis-Abhängigkeiten prüfen
    for dep in "${base_deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_base_deps+=("$dep")
        fi
    done

    # GPG Prüfung und Installation
    if ! command -v gpg &> /dev/null || ! gpg --version &> /dev/null; then
        case "$DISTRO_NAME" in
            "arch"|"endeavouros"|"manjaro"|"cachyos"|"garuda") gpg_package="gnupg" ;;
            "ubuntu"|"debian"|"linuxmint"|"pop"|"kali") gpg_package="gnupg2" ;;
            "fedora") gpg_package="gnupg2" ;;
            "opensuse"|"suse") gpg_package="gpg2" ;;
        esac
        missing_base_deps+=("$gpg_package")
    fi

    # Fehlende Abhängigkeiten installieren
    if [ ${#missing_base_deps[@]} -ne 0 ]; then
        log_info "Installiere fehlende Basis-Abhängigkeiten: ${BOLD}${missing_base_deps[*]}${RESET}"
        if ! eval "$PKG_MANAGER_INSTALL ${missing_base_deps[*]}"; then
            log_error "Installation der Basis-Abhängigkeiten fehlgeschlagen"
            exit 1
        fi
    else
        log_info "Alle Basis-Abhängigkeiten sind bereits installiert"
    fi

    # Finale GPG-Version anzeigen
    if command -v gpg &> /dev/null; then
        local gpg_version=$(gpg --version | head -n 1)
        log_info "GPG ist installiert: ${BOLD}${gpg_version}${RESET}"
    fi
}

# ==============================================================================
# TEIL 4: BACKUP-FUNKTIONEN
# ==============================================================================

backup_desktop_settings() {
    case "$DE" in
        *"gnome"*)
            backup_gnome_settings
            ;;
        *"kde"*|*"plasma"*)
            backup_kde_settings
            ;;
        *"xfce"*)
            backup_xfce_settings
            ;;
        *"cinnamon"*)
            backup_cinnamon_settings
            ;;
        *"mate"*)
            backup_mate_settings
            ;;
    esac
}

backup_gnome_settings() {
    local gnome_dir="$BASE_BACKUP_DIR/gnome"
    mkdir -p "$gnome_dir"
    
    log_info "Sichere GNOME-Einstellungen..."
    
    # Extension-Einstellungen
    if [ -d "${USER_HOME}/.local/share/gnome-shell/extensions" ]; then
        cp_with_error_handling -r "${USER_HOME}/.local/share/gnome-shell/extensions" "$gnome_dir/"
    fi
    
    # GNOME Einstellungen via dconf
    local dconf_settings=(
        "/"
        "/org/gnome/desktop/"
        "/org/gnome/shell/"
        "/org/gnome/settings-daemon/"
        "/org/gnome/terminal/"
        "/org/gnome/nautilus/"
    )
    
    for setting in "${dconf_settings[@]}"; do
        local filename=$(echo "$setting" | tr '/' '_' | sed 's/^_//;s/_$//')
        sudo -u "$SUDO_USER" dconf dump "$setting" > "$gnome_dir/${filename}.dconf"
    done
    
    # Tastenkombinationen
    sudo -u "$SUDO_USER" dconf dump /org/gnome/desktop/wm/keybindings/ > "$gnome_dir/shortcuts-wm.dconf"
    sudo -u "$SUDO_USER" dconf dump /org/gnome/settings-daemon/plugins/media-keys/ > "$gnome_dir/shortcuts-media.dconf"
    sudo -u "$SUDO_USER" dconf dump /org/gnome/shell/keybindings/ > "$gnome_dir/shortcuts-shell.dconf"
    
    # Benutzerdefinierte Tastenkombinationen
    sudo -u "$SUDO_USER" dconf dump /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ > "$gnome_dir/custom-shortcuts.dconf"
}

backup_kde_settings() {
    local kde_dir="$BASE_BACKUP_DIR/kde"
    mkdir -p "$kde_dir"
    
    log_info "Sichere KDE-Einstellungen..."
    
    # KDE Konfigurationsdateien
    local kde_config_files=(
        "plasma*"
        "kde*"
        "kwin*"
        "k*rc"
        "kglobal*"
        "kdeglobal*"
        "kscreen*"
        "konsole*"
        "dolphin*"
    )
    
    if [ -d "${USER_HOME}/.config" ]; then
        for pattern in "${kde_config_files[@]}"; do
            find "${USER_HOME}/.config" -maxdepth 1 -name "$pattern" -exec cp -r {} "$kde_dir/" \; 2>/dev/null || true
        done
    fi
    
    # KDE Lokale Daten
    local kde_local_dirs=(
        "plasma*"
        "kde*"
        "akonadi*"
        "kactivity*"
        "klipper"
        "kmix"
        "konsole"
    )
    
    if [ -d "${USER_HOME}/.local/share" ]; then
        for pattern in "${kde_local_dirs[@]}"; do
            find "${USER_HOME}/.local/share" -maxdepth 1 -name "$pattern" -exec cp -r {} "$kde_dir/" \; 2>/dev/null || true
        done
    fi
    
    # Spezielle KDE-Verzeichnisse
    cp_with_error_handling -r "${USER_HOME}/.kde4" "$kde_dir/" 2>/dev/null || true
    cp_with_error_handling -r "${USER_HOME}/.kde" "$kde_dir/" 2>/dev/null || true
}

backup_xfce_settings() {
    local xfce_dir="$BASE_BACKUP_DIR/xfce"
    mkdir -p "$xfce_dir"
    
    log_info "Sichere XFCE-Einstellungen..."
    
    local xfce_configs=(
        "xfce4"
        "Thunar"
        "xfce4-session"
        "xfce4-panel"
        "xfconf"
        "xfwm4"
        "xfce4-power-manager"
        "xfce4-notifyd"
        "xfce4-screensaver"
        "xfce4-terminal"
    )
    
    for config in "${xfce_configs[@]}"; do
        if [ -d "${USER_HOME}/.config/$config" ]; then
            cp_with_error_handling -r "${USER_HOME}/.config/$config" "$xfce_dir/"
        fi
    done
}

backup_cinnamon_settings() {
    local cinnamon_dir="$BASE_BACKUP_DIR/cinnamon"
    mkdir -p "$cinnamon_dir"
    
    log_info "Sichere Cinnamon-Einstellungen..."
    
    # Dconf-Einstellungen
    sudo -u "$SUDO_USER" dconf dump /org/cinnamon/ > "$cinnamon_dir/cinnamon.dconf"
    sudo -u "$SUDO_USER" dconf dump /org/nemo/ > "$cinnamon_dir/nemo.dconf"
    
    # Konfigurationsdateien
    if [ -d "${USER_HOME}/.cinnamon" ]; then
        cp_with_error_handling -r "${USER_HOME}/.cinnamon" "$cinnamon_dir/"
    fi
    
    # Applets und Extensions
    local cinnamon_dirs=(
        ".local/share/cinnamon"
        ".local/share/nemo"
        ".local/share/cinnamon-background-properties"
    )
    
    for dir in "${cinnamon_dirs[@]}"; do
        if [ -d "${USER_HOME}/$dir" ]; then
            cp_with_error_handling -r "${USER_HOME}/$dir" "$cinnamon_dir/"
        fi
    done
}

backup_mate_settings() {
    local mate_dir="$BASE_BACKUP_DIR/mate"
    mkdir -p "$mate_dir"
    
    log_info "Sichere MATE-Einstellungen..."
    
    # Dconf-Einstellungen
    sudo -u "$SUDO_USER" dconf dump /org/mate/ > "$mate_dir/mate.dconf"
    
    # Konfigurationsdateien
    local mate_configs=(
        "mate"
        "pluma"
        "caja"
        "marco"
        "mate-terminal"
    )
    
    for config in "${mate_configs[@]}"; do
        if [ -d "${USER_HOME}/.config/$config" ]; then
            cp_with_error_handling -r "${USER_HOME}/.config/$config" "$mate_dir/"
        fi
    done
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
        
        # Standard SSH-Dateien
        local ssh_files=(
            "config"
            "known_hosts"
            "authorized_keys"
            "known_hosts.old"
            "config.d"
        )
        
        for file in "${ssh_files[@]}"; do
            if [ -e "${USER_HOME}/.ssh/$file" ]; then
                cp_with_error_handling -a "${USER_HOME}/.ssh/$file" "$ssh_dir/" 2>/dev/null || true
            fi
        done
        
        # Private Schlüssel nur wenn gewünscht und Backup verschlüsselt wird
        if [ "${BACKUP_SSH_KEYS,,}" = "yes" ] && [ "$ENCRYPT" = true ]; then
            log_info "Sichere SSH-Schlüssel..."
            for key in "${USER_HOME}/.ssh/id_"*; do
                if [ -f "$key" ] && [[ "$key" != *".pub" ]]; then
                    cp_with_error_handling "$key" "$ssh_dir/" 2>/dev/null || true
                    if [ -f "${key}.pub" ]; then
                        cp_with_error_handling "${key}.pub" "$ssh_dir/" 2>/dev/null || true
                    fi
                fi
            done
        fi
        
        # Berechtigungen setzen
        chmod 700 "$ssh_dir"
        find "$ssh_dir" -type f -exec chmod 600 {} \;
        find "$ssh_dir" -name "*.pub" -exec chmod 644 {} \;
    else
        log_info "Kein .ssh Verzeichnis gefunden, überspringe..."
    fi
}

# ==============================================================================
# TEIL 4: BACKUP-FUNKTIONEN
# ==============================================================================

backup_desktop_settings() {
    case "$DE" in
        *"gnome"*)
            backup_gnome_settings
            ;;
        *"kde"*|*"plasma"*)
            backup_kde_settings
            ;;
        *"xfce"*)
            backup_xfce_settings
            ;;
        *"cinnamon"*)
            backup_cinnamon_settings
            ;;
        *"mate"*)
            backup_mate_settings
            ;;
    esac
}

backup_gnome_settings() {
    local gnome_dir="$BASE_BACKUP_DIR/gnome"
    mkdir -p "$gnome_dir"
    
    log_info "Sichere GNOME-Einstellungen..."
    
    # Extension-Einstellungen
    if [ -d "${USER_HOME}/.local/share/gnome-shell/extensions" ]; then
        cp_with_error_handling -r "${USER_HOME}/.local/share/gnome-shell/extensions" "$gnome_dir/"
    fi
    
    # GNOME Einstellungen via dconf
    local dconf_settings=(
        "/"
        "/org/gnome/desktop/"
        "/org/gnome/shell/"
        "/org/gnome/settings-daemon/"
        "/org/gnome/terminal/"
        "/org/gnome/nautilus/"
    )
    
    for setting in "${dconf_settings[@]}"; do
        local filename=$(echo "$setting" | tr '/' '_' | sed 's/^_//;s/_$//')
        sudo -u "$SUDO_USER" dconf dump "$setting" > "$gnome_dir/${filename}.dconf"
    done
    
    # Tastenkombinationen
    sudo -u "$SUDO_USER" dconf dump /org/gnome/desktop/wm/keybindings/ > "$gnome_dir/shortcuts-wm.dconf"
    sudo -u "$SUDO_USER" dconf dump /org/gnome/settings-daemon/plugins/media-keys/ > "$gnome_dir/shortcuts-media.dconf"
    sudo -u "$SUDO_USER" dconf dump /org/gnome/shell/keybindings/ > "$gnome_dir/shortcuts-shell.dconf"
    
    # Benutzerdefinierte Tastenkombinationen
    sudo -u "$SUDO_USER" dconf dump /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ > "$gnome_dir/custom-shortcuts.dconf"
}

backup_kde_settings() {
    local kde_dir="$BASE_BACKUP_DIR/kde"
    mkdir -p "$kde_dir"
    
    log_info "Sichere KDE-Einstellungen..."
    
    # KDE Konfigurationsdateien
    local kde_config_files=(
        "plasma*"
        "kde*"
        "kwin*"
        "k*rc"
        "kglobal*"
        "kdeglobal*"
        "kscreen*"
        "konsole*"
        "dolphin*"
    )
    
    if [ -d "${USER_HOME}/.config" ]; then
        for pattern in "${kde_config_files[@]}"; do
            find "${USER_HOME}/.config" -maxdepth 1 -name "$pattern" -exec cp -r {} "$kde_dir/" \; 2>/dev/null || true
        done
    fi
    
    # KDE Lokale Daten
    local kde_local_dirs=(
        "plasma*"
        "kde*"
        "akonadi*"
        "kactivity*"
        "klipper"
        "kmix"
        "konsole"
    )
    
    if [ -d "${USER_HOME}/.local/share" ]; then
        for pattern in "${kde_local_dirs[@]}"; do
            find "${USER_HOME}/.local/share" -maxdepth 1 -name "$pattern" -exec cp -r {} "$kde_dir/" \; 2>/dev/null || true
        done
    fi
    
    # Spezielle KDE-Verzeichnisse
    cp_with_error_handling -r "${USER_HOME}/.kde4" "$kde_dir/" 2>/dev/null || true
    cp_with_error_handling -r "${USER_HOME}/.kde" "$kde_dir/" 2>/dev/null || true
}

backup_xfce_settings() {
    local xfce_dir="$BASE_BACKUP_DIR/xfce"
    mkdir -p "$xfce_dir"
    
    log_info "Sichere XFCE-Einstellungen..."
    
    local xfce_configs=(
        "xfce4"
        "Thunar"
        "xfce4-session"
        "xfce4-panel"
        "xfconf"
        "xfwm4"
        "xfce4-power-manager"
        "xfce4-notifyd"
        "xfce4-screensaver"
        "xfce4-terminal"
    )
    
    for config in "${xfce_configs[@]}"; do
        if [ -d "${USER_HOME}/.config/$config" ]; then
            cp_with_error_handling -r "${USER_HOME}/.config/$config" "$xfce_dir/"
        fi
    done
}

backup_cinnamon_settings() {
    local cinnamon_dir="$BASE_BACKUP_DIR/cinnamon"
    mkdir -p "$cinnamon_dir"
    
    log_info "Sichere Cinnamon-Einstellungen..."
    
    # Dconf-Einstellungen
    sudo -u "$SUDO_USER" dconf dump /org/cinnamon/ > "$cinnamon_dir/cinnamon.dconf"
    sudo -u "$SUDO_USER" dconf dump /org/nemo/ > "$cinnamon_dir/nemo.dconf"
    
    # Konfigurationsdateien
    if [ -d "${USER_HOME}/.cinnamon" ]; then
        cp_with_error_handling -r "${USER_HOME}/.cinnamon" "$cinnamon_dir/"
    fi
    
    # Applets und Extensions
    local cinnamon_dirs=(
        ".local/share/cinnamon"
        ".local/share/nemo"
        ".local/share/cinnamon-background-properties"
    )
    
    for dir in "${cinnamon_dirs[@]}"; do
        if [ -d "${USER_HOME}/$dir" ]; then
            cp_with_error_handling -r "${USER_HOME}/$dir" "$cinnamon_dir/"
        fi
    done
}

backup_mate_settings() {
    local mate_dir="$BASE_BACKUP_DIR/mate"
    mkdir -p "$mate_dir"
    
    log_info "Sichere MATE-Einstellungen..."
    
    # Dconf-Einstellungen
    sudo -u "$SUDO_USER" dconf dump /org/mate/ > "$mate_dir/mate.dconf"
    
    # Konfigurationsdateien
    local mate_configs=(
        "mate"
        "pluma"
        "caja"
        "marco"
        "mate-terminal"
    )
    
    for config in "${mate_configs[@]}"; do
        if [ -d "${USER_HOME}/.config/$config" ]; then
            cp_with_error_handling -r "${USER_HOME}/.config/$config" "$mate_dir/"
        fi
    done
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
        
        # Standard SSH-Dateien
        local ssh_files=(
            "config"
            "known_hosts"
            "authorized_keys"
            "known_hosts.old"
            "config.d"
        )
        
        for file in "${ssh_files[@]}"; do
            if [ -e "${USER_HOME}/.ssh/$file" ]; then
                cp_with_error_handling -a "${USER_HOME}/.ssh/$file" "$ssh_dir/" 2>/dev/null || true
            fi
        done
        
        # Private Schlüssel nur wenn gewünscht und Backup verschlüsselt wird
        if [ "${BACKUP_SSH_KEYS,,}" = "yes" ] && [ "$ENCRYPT" = true ]; then
            log_info "Sichere SSH-Schlüssel..."
            for key in "${USER_HOME}/.ssh/id_"*; do
                if [ -f "$key" ] && [[ "$key" != *".pub" ]]; then
                    cp_with_error_handling "$key" "$ssh_dir/" 2>/dev/null || true
                    if [ -f "${key}.pub" ]; then
                        cp_with_error_handling "${key}.pub" "$ssh_dir/" 2>/dev/null || true
                    fi
                fi
            done
        fi
        
        # Berechtigungen setzen
        chmod 700 "$ssh_dir"
        find "$ssh_dir" -type f -exec chmod 600 {} \;
        find "$ssh_dir" -name "*.pub" -exec chmod 644 {} \;
    else
        log_info "Kein .ssh Verzeichnis gefunden, überspringe..."
    fi
}

# ==============================================================================
# TEIL 6: KOMPRIMIERUNG, VERSCHLÜSSELUNG UND HILFSFUNKTIONEN
# ==============================================================================

compress_backup() {
    local source_dir="$1"
    local target_archive="$2"
    local use_encryption="$3"
    local compression_level="${COMPRESSION_LEVEL:-1}"
    local cpu_cores
    local temp_dir="${TEMP_BASE_DIR}/compress_$$"
    
    # CPU-Kerne für Komprimierung bestimmen
    if [ "${COMPRESSION_THREADS:-0}" -eq 0 ]; then
        cpu_cores=$(($(nproc) - 1))
        [ "$cpu_cores" -lt 1 ] && cpu_cores=1
    else
        cpu_cores="${COMPRESSION_THREADS}"
    fi
    
    # Ursprungsgröße ermitteln und formatieren
    local source_size=$(du -sb "$source_dir" | cut -f1)
    local formatted_size=$(numfmt --to=iec-i --suffix=B $source_size)
    log_info "Ursprungsgröße: ${BOLD}$formatted_size${RESET}"
    
    # Benötigten Speicherplatz berechnen (Original + 30% für Komprimierung und Temp-Dateien)
    local required_space=$(( source_size + (source_size * 30 / 100) ))
    
    mkdir -p "$temp_dir"
    
    # Prüfen ob genügend Speicherplatz verfügbar ist
    if ! check_disk_space "$(dirname "$target_archive")" "$required_space"; then
        rm -rf "$temp_dir"
        return 1
    fi
    
    log_info "Starte Komprimierung mit ${BOLD}$cpu_cores${RESET} CPU-Kernen..."
    
    if [ "$use_encryption" = true ]; then
        # Temporäres unverschlüsseltes Archiv erstellen
        local temp_archive="$temp_dir/backup.tar.gz"
        
        # Komprimierung mit Fortschrittsanzeige
        tar --use-compress-program="pigz -p $cpu_cores -$compression_level" \
            -cf "$temp_archive" \
            --totals \
            --checkpoint=1000 \
            --checkpoint-action=exec='printf "\rKomprimiere... %d MiB" $((${TAR_CHECKPOINT:-0}/1024))' \
            -C "$(dirname "$source_dir")" "$(basename "$source_dir")" 2>/dev/null
        echo # Neue Zeile nach Fortschrittsanzeige
        
        if [ -f "$temp_archive" ]; then
            local temp_size=$(du -sh "$temp_archive" | cut -f1)
            log_info "Zwischengröße nach Komprimierung: ${BOLD}${temp_size}${RESET}"
            
            log_info "Verschlüssele Backup..."
            # Verschlüsselung mit Fortschrittsanzeige
            (get_backup_password "$password_file" | gpg --batch --yes --passphrase-fd 0 \
                --cipher-algo AES256 \
                --compress-algo none \
                --progress --no-verbose \
                -c --output "$target_archive" "$temp_archive" 2>&1) | \
                grep -v "gpg: encrypted with" || true
        else
            log_error "Temporäres Archiv wurde nicht erstellt"
            rm -rf "$temp_dir"
            return 1
        fi
        
    else
        # Direkte Komprimierung ohne Verschlüsselung, mit Fortschrittsanzeige
        tar --use-compress-program="pigz -p $cpu_cores -$compression_level" \
            -cf "$target_archive" \
            --totals \
            --checkpoint=1000 \
            --checkpoint-action=exec='printf "\rKomprimiere... %d MiB" $((${TAR_CHECKPOINT:-0}/1024))' \
            -C "$(dirname "$source_dir")" "$(basename "$source_dir")" 2>/dev/null
        echo # Neue Zeile nach Fortschrittsanzeige
    fi
    
    # Finale Größe berechnen
    if [ -f "$target_archive" ]; then
        local final_size=$(du -sh "$target_archive" | cut -f1)
        log_info "Finale Größe: ${BOLD}${final_size}${RESET}"
        
        # Komprimierungsrate berechnen
        local final_bytes=$(du -sb "$target_archive" | cut -f1)
        local compression_ratio=$(echo "scale=2; $final_bytes * 100 / $source_size" | bc)
        log_info "Komprimierungsrate: ${BOLD}${compression_ratio}%${RESET}"
    else
        log_error "Backup-Archiv wurde nicht erstellt"
        rm -rf "$temp_dir"
        return 1
    fi
    
    rm -rf "$temp_dir"
    return 0
}

check_disk_space() {
    local path="$1"
    local required_space="$2"
    local available_space=$(df --output=avail -B1 "$path" | tail -n1)
    
    if [ "$available_space" -lt "$required_space" ]; then
        log_error "Nicht genügend Speicherplatz verfügbar"
        local formatted_available=$(numfmt --to=iec-i --suffix=B $available_space)
        local formatted_required=$(numfmt --to=iec-i --suffix=B $required_space)
        log_error "Verfügbar: ${BOLD}${formatted_available}${RESET}"
        log_error "Benötigt:  ${BOLD}${formatted_required}${RESET}"
        return 1
    fi
    return 0
}

get_backup_password() {
    local password_file="$1"
    local key_file="${USER_HOME}/.backup_key"
    
    if [ -n "${BACKUP_PASSWORD:-}" ]; then
        echo "$BACKUP_PASSWORD"
    elif [ -f "$password_file" ] && [ -f "$key_file" ]; then
        if ! openssl enc -aes-256-cbc -salt -pbkdf2 -d -in "$password_file" -pass file:"$key_file" 2>/dev/null; then
            log_error "Fehler beim Entschlüsseln der Passwortdatei"
            exit 1
        fi
    else
        log_error "Keine Passwortdatei oder Umgebungsvariable gefunden"
        log_error "Erstellen Sie eine Passwortdatei mit: $0 -create-pw"
        exit 1
    fi
}

create_password_file() {
    local password_file="$1"
    local temp_key_file="/tmp/backup_key_$$"
    local min_length=12
    
    # Zufälligen Schlüssel generieren
    openssl rand -hex 32 > "$temp_key_file"
    
    echo -e "${BOLD}Backup-Verschlüsselung einrichten${RESET}\n"
    echo "Das Passwort sollte mindestens ${min_length} Zeichen lang sein und"
    echo "Groß- und Kleinbuchstaben, Zahlen sowie Sonderzeichen enthalten."
    echo
    
    while true; do
        read -s -p "Backup-Passwort eingeben: " password
        echo
        
        # Passwort-Validierung
        if [ ${#password} -lt $min_length ]; then
            echo "Passwort muss mindestens ${min_length} Zeichen lang sein."
            continue
        fi
        
        read -s -p "Backup-Passwort wiederholen: " password2
        echo
        
        if [ "$password" = "$password2" ]; then
            break
        else
            echo -e "\n${RED}Passwörter stimmen nicht überein${RESET}. Bitte erneut versuchen.\n"
        fi
    done
    
    # Passwort verschlüsselt speichern
    echo "$password" | openssl enc -aes-256-cbc -salt -pbkdf2 -in - -out "$password_file" -pass file:"$temp_key_file"
    
    # Schlüssel sicher in Home-Verzeichnis speichern
    mv "$temp_key_file" "${USER_HOME}/.backup_key"
    chmod 600 "${USER_HOME}/.backup_key"
    chmod 600 "$password_file"
    
    echo -e "\n${GREEN}Passwortdatei und Schlüssel wurden erstellt:${RESET}"
    echo "Passwortdatei: $password_file"
    echo "Schlüsseldatei: ${USER_HOME}/.backup_key"
    echo -e "\n${YELLOW}WICHTIG: Bewahren Sie beide Dateien sicher auf!${RESET}"
    echo "Ohne diese Dateien können Sie das Backup nicht wiederherstellen."
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
        local rsync_cmd="rsync -a --info=progress2 $excludes \"$source/\" \"$target/\""
        eval $rsync_cmd
    else
        log_info "Verzeichnis $source existiert nicht, überspringe..."
    fi
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

# ==============================================================================
# TEIL 7: HAUPTLOGIK UND MENÜSYSTEM
# ==============================================================================

show_menu() {
    echo
    echo -e "${BOLD}╔═══════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}║   CachyOS Advanced System Backup Tool     ║${RESET}"
    echo -e "${BOLD}╚═══════════════════════════════════════════╝${RESET}"
    echo
    echo -e "${BOLD}=== BACKUP-OPTIONEN ===${RESET}"
    echo
    echo "1) Einfaches Backup (unverschlüsselt)"
    echo "2) Komprimiertes Backup (.tar.gz)"
    echo "3) Verschlüsseltes Backup (.tar.gz.gpg)"
    echo "4) Backup-Passwort ändern"
    echo "5) Erweiterte Einstellungen"
    echo "0) Beenden"
    echo
    
    while true; do
        read -p "Ihre Wahl (0-5): " choice
        case $choice in
            1)
                log_info "Starte einfaches Backup..."
                COMPRESS=false
                ENCRYPT=false
                return
                ;;
            2)
                log_info "Starte komprimiertes Backup..."
                COMPRESS=true
                ENCRYPT=false
                return
                ;;
            3)
                log_info "Starte verschlüsseltes Backup..."
                COMPRESS=true
                ENCRYPT=true
                return
                ;;
            4)
                create_password_file "$password_file"
                show_menu
                return
                ;;
            5)
                show_advanced_settings
                show_menu
                return
                ;;
            0)
                echo "Backup wird beendet."
                exit 0
                ;;
            *)
                echo -e "${RED}Ungültige Auswahl.${RESET} Bitte wählen Sie 0-5."
                ;;
        esac
    done
}

show_advanced_settings() {
    echo
    echo -e "${YELLOW}=== ERWEITERTE EINSTELLUNGEN ===${RESET}"
    echo
    echo -e "${CYAN}1)${RESET} ${GREEN}Zeitstempel aktivieren/deaktivieren${RESET} ${GRAY}(aktuell: ${YELLOW}$USE_TIMESTAMP${GRAY})${RESET}"
    echo -e "${CYAN}2)${RESET} ${GREEN}Zeitstempel-Format ändern${RESET} ${GRAY}(aktuell: ${YELLOW}$TIMESTAMP_FORMAT${GRAY})${RESET}"
    echo -e "${CYAN}3)${RESET} ${GREEN}Komprimierungslevel ändern${RESET} ${GRAY}(aktuell: ${YELLOW}$COMPRESSION_LEVEL${GRAY})${RESET}"
    echo -e "${CYAN}4)${RESET} ${GREEN}CPU-Threads für Komprimierung${RESET} ${GRAY}(aktuell: ${YELLOW}$COMPRESSION_THREADS${GRAY})${RESET}"
    echo -e "${CYAN}5)${RESET} ${GREEN}SSH-Backup aktivieren/deaktivieren${RESET} ${GRAY}(aktuell: ${YELLOW}$BACKUP_SSH${GRAY})${RESET}"
    echo -e "${CYAN}6)${RESET} ${GREEN}SSH-Schlüssel-Backup aktivieren/deaktivieren${RESET} ${GRAY}(aktuell: ${YELLOW}$BACKUP_SSH_KEYS${GRAY})${RESET}"
    echo -e "${CYAN}0)${RESET} ${BLUE}Zurück zum Hauptmenü${RESET}"
    echo
    
    while true; do
        read -p "$(echo -e "${YELLOW}Ihre Wahl (0-6):${RESET} ")" choice
        case $choice in
            1)
                if [ "$USE_TIMESTAMP" = "yes" ]; then
                    USE_TIMESTAMP="no"
                else
                    USE_TIMESTAMP="yes"
                fi
                echo "Zeitstempel ist nun: $USE_TIMESTAMP"
                ;;
            2)
                echo "Verfügbare Formate:"
                echo "1) YYYYMMDD         (z.B. 20241101)"
                echo "2) YYYY-MM-DD       (z.B. 2024-11-01)"
                echo "3) YYYYMMDD_HHMM    (z.B. 20241101_1430)"
                echo "4) YYYYMMDD_HH-MM-SS (z.B. 20241101_14-30-45)"
                read -p "Format wählen (1-4): " format_choice
                case $format_choice in
                    1) TIMESTAMP_FORMAT="%Y%m%d" ;;
                    2) TIMESTAMP_FORMAT="%Y-%m-%d" ;;
                    3) TIMESTAMP_FORMAT="%Y%m%d_%H%M" ;;
                    4) TIMESTAMP_FORMAT="%Y%m%d_%H-%M-%S" ;;
                    *) echo "Ungültige Auswahl." ;;
                esac
                ;;
            3)
                read -p "Komprimierungslevel (1-9, 1=schnell/groß, 9=langsam/klein): " level
                if [[ "$level" =~ ^[1-9]$ ]]; then
                    COMPRESSION_LEVEL=$level
                else
                    echo "Ungültige Eingabe. Bitte Zahl zwischen 1 und 9 eingeben."
                fi
                ;;
            4)
                read -p "CPU-Threads (0=auto, max=$(nproc)): " threads
                if [[ "$threads" =~ ^[0-9]+$ ]] && [ "$threads" -le "$(nproc)" ]; then
                    COMPRESSION_THREADS=$threads
                else
                    echo "Ungültige Eingabe. Bitte Zahl zwischen 0 und $(nproc) eingeben."
                fi
                ;;
            5)
                if [ "$BACKUP_SSH" = "yes" ]; then
                    BACKUP_SSH="no"
                else
                    BACKUP_SSH="yes"
                fi
                echo "SSH-Backup ist nun: $BACKUP_SSH"
                ;;
            6)
                if [ "$BACKUP_SSH_KEYS" = "yes" ]; then
                    BACKUP_SSH_KEYS="no"
                else
                    BACKUP_SSH_KEYS="yes"
                fi
                echo "SSH-Schlüssel-Backup ist nun: $BACKUP_SSH_KEYS"
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}Ungültige Auswahl.${RESET} Bitte wählen Sie 0-6."
                ;;
        esac
    done
}

init_backup() {
    log_info "Initialisiere Backup-Prozess..."
    log_info "Benutzer-Home-Verzeichnis: ${BOLD}$USER_HOME${RESET}"

    # Backup-Pfad vorbereiten
    BASE_BACKUP_DIR=$(get_backup_path "$BASE_BACKUP_DIR")
    mkdir -p "$TEMP_BASE_DIR"

    # Backup-Verzeichnisse erstellen
    log_info "Erstelle Backup-Verzeichnisse..."
    for dir in "${!BACKUP_SUBDIRS[@]}"; do
        mkdir -p "${BACKUP_SUBDIRS[$dir]}"
    done

    # Berechtigungen setzen
    chown -R "$SUDO_USER:$SUDO_USER" "$BASE_BACKUP_DIR"
    chmod -R u=rwX,g=rX,o= "$BASE_BACKUP_DIR"
}

perform_backup() {
    # System-Backups
    backup_system_configs

    # Benutzer-Backups
    backup_user_configs
    
    # Desktop-Environment spezifische Backups
    backup_desktop_settings
    
    # SSH-Konfiguration
    backup_ssh "$BASE_BACKUP_DIR"
    
    # Anwendungsdaten
    backup_application_data
    
    # Themes und Icons
    backup_themes_and_icons
    
    # Paketlisten erstellen
    create_package_lists "$BASE_BACKUP_DIR"
}

finalize_backup() {
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
        
        chown "$SUDO_USER:$SUDO_USER" "$backup_archive"
        chmod 600 "$backup_archive"
        
        log_info "Backup abgeschlossen. Archiv wurde erstellt: ${BOLD}$backup_archive${RESET}"
    else
        chown -R "$SUDO_USER:$SUDO_USER" "$BASE_BACKUP_DIR"
        chmod -R u=rwX,g=rX,o= "$BASE_BACKUP_DIR"
        backup_size=$(du -sh "$BASE_BACKUP_DIR" | cut -f1)
        log_info "Backup abgeschlossen. Dateien befinden sich in: ${BOLD}$BASE_BACKUP_DIR${RESET}"
        log_info "Backup-Größe: ${BOLD}$backup_size${RESET}"
    fi
}

main() {
    # Logging initialisieren
    init_logging

    # Menü anzeigen und Optionen wählen
    show_menu

    # System überprüfen
    log_info "Prüfe System und Abhängigkeiten..."
    detect_distro
    detect_desktop_environment
    check_base_dependencies
    configure_package_manager

    # Backup durchführen
    init_backup
    perform_backup
    finalize_backup
}

# Prüfen ob Script als root läuft
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Dieses Script muss mit sudo-Rechten ausgeführt werden!${RESET}"
    exit 1
fi

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

# Hauptprogramm starten
main