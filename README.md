# Linux System Backup Script

Ein Bash-Script zum Backup wichtiger System- und Benutzerdaten unter Linux. Das Script wurde primär für Arch Linux und dessen Derivate entwickelt und getestet.

## 🚀 Features

* Backup von Systemkonfigurationen (/etc)
* Backup von Benutzer-Dotfiles
* Backup von wichtigen Home-Verzeichnissen
* Sicherung von Paketlisten (Pacman/AUR/Flatpak)
* Desktop-Environment spezifische Backups (GNOME/KDE/XFCE)
* SSH-Konfiguration Backup (optional mit Schlüsseln)
* Komprimierung der Backups (optional)
* Verschlüsselung der Backups (optional)
* Detailliertes Logging
* Intelligente Fehlerbehandlung

## 📋 Voraussetzungen

* Arch Linux oder Arch-basierte Distribution
* sudo-Rechte
* Folgende Basis-Abhängigkeiten:

  * rsync
  * pigz (parallele Komprimierung)
  * gnupg (für Verschlüsselung)
  * expac (für detaillierte Paketinformationen)

## 🔧 Ersteinrichtung

1. Repository klonen:

```bash
git clone https://github.com/root9191/backuplinux.git
cd backuplinux
```

2. Script ausführbar machen:

```bash
chmod +x backup.sh
```

3. Konfiguration anpassen:

    * Öffnen Sie `backup.sh` in einem Texteditor
    * Passen Sie folgende Hauptvariablen an:

      ```bash
      BASE_BACKUP_DIR="/mnt/Daten/[username]/backup"  # Backup-Zielverzeichnis
      TEMP_BASE_DIR="/var/tmp/bkp"                    # Temporäres Verzeichnis
      LOG_DIR="/home/[username]/Dokumente"            # Log-Verzeichnis
      ```
4. Zu sichernde Elemente prüfen/anpassen:

    * Überprüfen Sie die Arrays `DOTFILES` und `HOME_DIRS`
    * Passen Sie `SYSTEM_CONFIGS` und `SYSTEM_CONFIG_DIRS` an
    * Überprüfen Sie die Ausschlusslisten:

      ```bash
      CACHE_EXCLUDES=( "yay" ".cache/mozilla" ... )
      LOCAL_EXCLUDES=( "share/Steam" "share/Trash" ... )
      ```
5. (Optional) Passwort für verschlüsselte Backups einrichten:

```bash
sudo ./backup.sh -create-pw
```

Dies erstellt zwei wichtige Dateien:

* `~/.backup_password`: Enthält das verschlüsselte Backup-Passwort
* `~/.backup_key`: Verschlüsselungsschlüssel für das Passwort

⚠️ **Wichtig**: Bewahren Sie beide Dateien sicher auf! Sie werden für die Wiederherstellung verschlüsselter Backups benötigt.

## 📦 Backup-Erstellung

### 1. Einfaches Backup (unverschlüsselt)

```bash
sudo ./backup.sh
```

* Erstellt ein unkomprimiertes Backup im konfigurierten Backup-Verzeichnis
* Alle Dateien bleiben im Klartext und sind direkt zugänglich

### 2. Komprimiertes Backup

```bash
sudo ./backup.sh -zip
```

* Erstellt ein komprimiertes `.tar.gz` Archiv
* Spart Speicherplatz, Dateien müssen zum Zugriff entpackt werden

### 3. Verschlüsseltes Backup

```bash
sudo ./backup.sh -pw
```

* Erstellt ein verschlüsseltes `.tar.gz.gpg` Archiv
* Maximale Sicherheit für sensitive Daten
* Benötigt das eingerichtete Backup-Passwort zur Wiederherstellung

### Backup-Protokollierung

* Alle Backup-Vorgänge werden protokolliert in:

  * `$LOG_DIR/backup.log`: Hauptprotokoll
  * `$LOG_DIR/backup_error.log`: Fehlerprotokoll
* Die letzten 5 Protokolldateien werden automatisch rotiert

## 🔄 Backup-Wiederherstellung

### 1. Unverschlüsselte Backups

#### A. Unkomprimiertes Backup

* Dateien können direkt aus dem Backup-Verzeichnis kopiert werden

```bash
# Beispiel: Wiederherstellen von Dotfiles
cp -a /pfad/zum/backup/.zshrc ~/.zshrc
cp -a /pfad/zum/backup/.config ~/
```

#### B. Komprimiertes Backup

1. Backup entpacken:

```bash
tar xzf backup.tar.gz
```

2. Dateien wie gewünscht wiederherstellen

### 2. Verschlüsselte Backups

1. Backup entschlüsseln:

```bash
# Wenn Passwortdateien vorhanden sind:
gpg --output backup.tar.gz --decrypt backup.tar.gz.gpg

# Wenn manuelles Passwort eingegeben werden soll:
gpg --decrypt backup.tar.gz.gpg > backup.tar.gz
```

2. Entpacken:

```bash
tar xzf backup.tar.gz
```

### 3. Spezifische Wiederherstellungen

#### System-Konfigurationen

```bash
# fstab (Vorsicht!)
sudo cp backup/etc/fstab /etc/fstab
sudo mount -a  # Zum Testen

# NetworkManager-Verbindungen
sudo cp -r backup/etc/NetworkManager/system-connections/* /etc/NetworkManager/system-connections/
sudo chmod 600 /etc/NetworkManager/system-connections/*
sudo systemctl restart NetworkManager
```

#### Paketinstallation

```bash
# System-Pakete
sudo pacman -S --needed - < pacman_packages.txt

# AUR-Pakete
yay -S --needed - < aur_packages.txt

# Flatpak
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
while read -r app; do flatpak install -y flathub $app; done < flatpak_packages.txt
```

#### Desktop-Umgebung

GNOME:

```bash
# Komplette Einstellungen
dconf load / < backup/gnome/all-settings.dconf

# Tastenkürzel
dconf load /org/gnome/desktop/wm/keybindings/ < backup/gnome/keyboard-shortcuts.dconf
dconf load /org/gnome/settings-daemon/plugins/media-keys/ < backup/gnome/media-keys.dconf

# Extensions
cp -r backup/gnome/extensions/* ~/.local/share/gnome-shell/extensions/
```

KDE:

```bash
cp -r backup/kde/plasma* ~/.config/
cp -r backup/kde/kde* ~/.config/
```

#### Persönliche Daten

```bash
# Wichtige Verzeichnisse
cp -r backup/Documents ~/
cp -r backup/Pictures ~/
cp -r backup/.config ~/

# Browser-Profile
cp -r backup/.mozilla ~/
cp -r backup/.config/google-chrome ~/.config/
```

## ⚙️ Anpassung und Erweiterung

### Eigene Verzeichnisse hinzufügen

Fügen Sie Ihre eigenen Verzeichnisse zum Backup hinzu, indem Sie die Arrays im Script erweitern:

```bash
# Für Home-Verzeichnisse
declare -a HOME_DIRS=(
    # Existierende Einträge...
    "MeineSpiele"
    "Entwicklung"
)

# Für System-Konfigurationen
declare -a SYSTEM_CONFIGS=(
    # Existierende Einträge...
    "meine-config"
)
```

### Ausschlüsse hinzufügen

Fügen Sie Verzeichnisse hinzu, die vom Backup ausgeschlossen werden sollen:

```bash
declare -a CACHE_EXCLUDES=(
    # Existierende Einträge...
    "node_modules"
    "tmp"
)
```

## ⚠️ Bekannte Einschränkungen

* Das Script wurde primär für Arch Linux und dessen Derivate entwickelt
* Verschlüsselte Backups benötigen zusätzlichen Speicherplatz während der Erstellung
* Bei großen Backup-Verzeichnissen kann der Prozess einige Zeit in Anspruch nehmen

## ⚖️ Lizenz

Dieses Projekt ist unter der MIT-Lizenz lizenziert - siehe die [LICENSE](LICENSE) Datei für Details.

## 🤝 Beitragen

Beiträge sind willkommen! Bitte lesen Sie [CONTRIBUTING.md](CONTRIBUTING.md) für Details zum Prozess für Pull Requests.
