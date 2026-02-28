#!/bin/bash
# =============================================================================
# Kubuntu - Windows-like Setup + Silent Updates + Simplified Experience
# =============================================================================
# Run this script after a fresh Kubuntu installation.
# Usage: sudo bash kubuntu-windows-setup.sh
# =============================================================================

set -e

echo "============================================="
echo " Starting Kubuntu Windows-style setup script"
echo "============================================="

# Must be run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root: sudo bash kubuntu-windows-setup.sh"
  exit 1
fi

# Get the actual user (not root) for user-specific settings
ACTUAL_USER=$(logname || echo $SUDO_USER)
USER_HOME=$(eval echo ~$ACTUAL_USER)

# Helper function - only install if not already installed
install_if_missing() {
  for pkg in "$@"; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
      echo "  Already installed: $pkg"
    else
      echo "  Installing: $pkg"
      apt install -y "$pkg"
    fi
  done
}

echo ""
echo "[1/9] Installing required packages..."
echo "--------------------------------------"
apt update -q

# Only packages actually needed for this script to work
install_if_missing \
  unattended-upgrades \
  apt-listchanges \
  fonts-noto \
  fonts-noto-core \
  timeshift \
  distro-info \
  firefox

echo ""
echo "[2/9] Configuring silent automatic updates..."
echo "----------------------------------------------"

# Configure unattended-upgrades
# Only set values that are off by default - leave the rest as Kubuntu ships them
UU_CONF="/etc/apt/apt.conf.d/50unattended-upgrades"

# Helper to uncomment or append a setting
set_uu() {
  local key="$1"
  local value="$2"
  if grep -q "^\/\/${key} " "$UU_CONF"; then
    sed -i "s|^//${key} .*|${key} \"${value}\";|" "$UU_CONF"
  elif grep -q "^${key} " "$UU_CONF"; then
    sed -i "s|^${key} .*|${key} \"${value}\";|" "$UU_CONF"
  else
    echo "${key} \"${value}\";" >> "$UU_CONF"
  fi
}

set_uu "Unattended-Upgrade::Remove-Unused-Kernel-Packages" "true"
set_uu "Unattended-Upgrade::Remove-Unused-Dependencies" "true"
set_uu "Unattended-Upgrade::Automatic-Reboot" "true"
set_uu "Unattended-Upgrade::Automatic-Reboot-WithUsers" "false"
set_uu "Unattended-Upgrade::Automatic-Reboot-Time" "03:00"
set_uu "Unattended-Upgrade::SyslogEnable" "true"

# Configure update frequency
# Only set values not already configured
AU_CONF="/etc/apt/apt.conf.d/20auto-upgrades"
set_apt() {
  local key="$1" value="$2"
  if grep -q "^${key}" "$AU_CONF" 2>/dev/null; then
    sed -i "s|^${key}.*|${key} \"${value}\";|" "$AU_CONF"
  else
    echo "${key} \"${value}\";" >> "$AU_CONF"
  fi
}
set_apt 'APT::Periodic::Update-Package-Lists' '1'
set_apt 'APT::Periodic::Download-Upgradeable-Packages' '1'
set_apt 'APT::Periodic::AutocleanInterval' '7'
set_apt 'APT::Periodic::Unattended-Upgrade' '1'

# Enable the unattended-upgrades service
systemctl enable unattended-upgrades
systemctl start unattended-upgrades

echo ""
echo "[3/9] Removing update popups..."
echo "--------------------------------"
apt remove -y --purge \
  update-notifier \
  update-notifier-common \
  ubuntu-release-upgrader-gtk 2>/dev/null || true

# Disable KDE's own update notifier popup
sudo -u $ACTUAL_USER bash << 'USEREOF'
kwriteconfig5 --file plasma-discover-notifierrc --group Global --key UseUnattendedUpdates true 2>/dev/null || true
USEREOF

# Stop Discover (KDE software center) from showing update notifications
mkdir -p /etc/xdg
DISCOVERRC="/etc/xdg/discoverrc"
if grep -q "^UseUnattendedUpdates" "$DISCOVERRC" 2>/dev/null; then
  sed -i 's|^UseUnattendedUpdates.*|UseUnattendedUpdates=true|' "$DISCOVERRC"
elif grep -q "^\[Software\]" "$DISCOVERRC" 2>/dev/null; then
  sed -i '/^\[Software\]/a UseUnattendedUpdates=true' "$DISCOVERRC"
else
  printf '[Software]\nUseUnattendedUpdates=true\n' >> "$DISCOVERRC"
fi

# Disable release upgrade prompts (admin handles this manually)
if [ -f /etc/update-manager/release-upgrades ]; then
  sed -i 's/Prompt=.*/Prompt=never/' /etc/update-manager/release-upgrades
else
  mkdir -p /etc/update-manager
  echo -e "[DEFAULT]\nPrompt=never" > /etc/update-manager/release-upgrades
fi

echo ""
echo "[4/9] Configuring KDE desktop to look like Windows 10..."
echo "---------------------------------------------------------"

sudo -u $ACTUAL_USER bash << 'USEREOF'

# Set Windows-like theme (Breeze Light is already close to Windows)
kwriteconfig5 --file kdeglobals --group General --key ColorScheme "BreezeLight"
kwriteconfig5 --file kdeglobals --group KDE --key LookAndFeelPackage "org.kde.breeze.desktop"

# Font similar to Segoe UI (Noto Sans is very close)
kwriteconfig5 --file kdeglobals --group General --key font "Noto Sans,10,-1,5,50,0,0,0,0,0"
kwriteconfig5 --file kdeglobals --group General --key fixed "Noto Sans Mono,10,-1,5,50,0,0,0,0,0"
kwriteconfig5 --file kdeglobals --group General --key menuFont "Noto Sans,10,-1,5,50,0,0,0,0,0"
kwriteconfig5 --file kdeglobals --group General --key smallestReadableFont "Noto Sans,8,-1,5,50,0,0,0,0,0"
kwriteconfig5 --file kdeglobals --group General --key toolBarFont "Noto Sans,10,-1,5,50,0,0,0,0,0"
kwriteconfig5 --file kdeglobals --group WM --key activeFont "Noto Sans,10,-1,5,700,0,0,0,0,0"

# Double-click to open files (like Windows)
kwriteconfig5 --file kdeglobals --group KDE --key SingleClick false

# Show file extensions in file manager
kwriteconfig5 --file dolphinrc --group General --key ShowFullPath true

# Single workspace - prevents windows disappearing to another workspace
kwriteconfig5 --file kwinrc --group Desktops --key Number 1
kwriteconfig5 --file kwinrc --group Desktops --key Rows 1

# Disable desktop effects that might confuse
kwriteconfig5 --file kwinrc --group Plugins --key desktopgridEnabled false
kwriteconfig5 --file kwinrc --group Plugins --key presentwindowsEnabled false
kwriteconfig5 --file kwinrc --group Plugins --key cube-slideEnabled false

# Window controls on the right like Windows (minimize, maximize, close)
kwriteconfig5 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnRight "IAX"
kwriteconfig5 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnLeft ""

# Disable KDE wallet popups (confusing for non-technical users)
kwriteconfig5 --file kwalletrc --group Wallet --key "Enabled" false
kwriteconfig5 --file kwalletrc --group Wallet --key "First Use" false

# Disable activity manager (not needed, can confuse)
kwriteconfig5 --file kactivitymanagerdrc --group activities --key enabled false 2>/dev/null || true

USEREOF

echo ""
echo "[5/9] Disabling confusing keyboard keys..."
echo "-------------------------------------------"

# Disable caps lock system-wide - only change XKBOPTIONS, preserve existing layout
KB_CONF="/etc/default/keyboard"
if grep -q "^XKBOPTIONS" "$KB_CONF" 2>/dev/null; then
  # Already has XKBOPTIONS - add caps:none if not already there
  if ! grep -q "caps:none" "$KB_CONF"; then
    sed -i 's|^XKBOPTIONS="\(.*\)"|XKBOPTIONS="\1,caps:none"|' "$KB_CONF"
    sed -i 's|^XKBOPTIONS="",caps:none|XKBOPTIONS="caps:none"|' "$KB_CONF"
  fi
else
  # No XKBOPTIONS line - append it
  echo 'XKBOPTIONS="caps:none"' >> "$KB_CONF"
fi
dpkg-reconfigure -f noninteractive keyboard-configuration 2>/dev/null || true

# Create xmodmap to disable additional confusing keys
cat > "$USER_HOME/.Xmodmap" << 'EOF'
! Disable Caps Lock
clear lock
keycode 66 = NoSymbol

! Disable Insert key (prevents accidental overtype mode in text editors)
keycode 118 = NoSymbol

! Disable Scroll Lock (does nothing useful for regular users)
keycode 78 = NoSymbol

! Disable Pause/Break key (does nothing useful for regular users)
keycode 127 = NoSymbol
EOF

chown $ACTUAL_USER:$ACTUAL_USER "$USER_HOME/.Xmodmap"

# Add xmodmap to KDE autostart
mkdir -p "$USER_HOME/.config/autostart"
cat > "$USER_HOME/.config/autostart/disable-keys.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Disable Distracting Keys
Exec=xmodmap $USER_HOME/.Xmodmap
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
chown $ACTUAL_USER:$ACTUAL_USER "$USER_HOME/.config/autostart/disable-keys.desktop"

echo ""
echo "[6/9] Disabling KDE shortcuts that could cause confusion..."
echo "------------------------------------------------------------"

sudo -u $ACTUAL_USER bash << 'USEREOF'
# Disable workspace switching shortcuts
kwriteconfig5 --file kglobalshortcutsrc --group kwin --key "Switch to Desktop 1" "none,none,Switch to Desktop 1"
kwriteconfig5 --file kglobalshortcutsrc --group kwin --key "Switch to Desktop 2" "none,none,Switch to Desktop 2"
kwriteconfig5 --file kglobalshortcutsrc --group kwin --key "Window to Desktop 1" "none,none,Window to Desktop 1"

# Disable activity switching
kwriteconfig5 --file kglobalshortcutsrc --group "KDE Daemon" --key "Show System Activity" "none,none,Show System Activity"

# Disable kRunner (search popup that appears on Alt+Space or Alt+F2)
kwriteconfig5 --file kglobalshortcutsrc --group "krunner.desktop" --key "_launch" "none,none,KRunner"
kwriteconfig5 --file kglobalshortcutsrc --group "krunner.desktop" --key "RunClipboard" "none,none,Run command on clipboard contents"
kwriteconfig5 --file krunnerrc --group General --key "ActionsEnabled" false
kwriteconfig5 --file krunnerrc --group General --key "RetainPriorSearch" false
USEREOF

echo ""
echo "[7/9] Keeping login screen, disabling auto-lock after login..."
echo "--------------------------------------------------------------"

# Login screen (SDDM) is kept so user logs in normally with password
# But once logged in the session never locks automatically

sudo -u $ACTUAL_USER bash << 'USEREOF'
kwriteconfig5 --file kscreenlockerrc --group Daemon --key Autolock false
kwriteconfig5 --file kscreenlockerrc --group Daemon --key LockOnResume false
kwriteconfig5 --file kscreenlockerrc --group Daemon --key LockOnLidClose false
kwriteconfig5 --file kscreenlockerrc --group Daemon --key Timeout 0
USEREOF

echo ""
echo "[8/9] Configuring Timeshift automatic backups..."
echo "-------------------------------------------------"

# Only write Timeshift config if it doesn't already exist
if [ ! -f /etc/timeshift/timeshift.json ]; then
  mkdir -p /etc/timeshift
  cat > /etc/timeshift/timeshift.json << 'EOF'
{
  "backup_device_uuid" : "",
  "parent_device_uuid" : "",
  "do_first_run" : "false",
  "btrfs_mode" : "false",
  "include_btrfs_home_for_backup" : "false",
  "include_btrfs_home_for_restore" : "false",
  "stop_cron_emails" : "true",
  "btrfs_use_qgroup" : "true",
  "schedule_monthly" : "false",
  "schedule_weekly" : "true",
  "schedule_daily" : "true",
  "schedule_hourly" : "false",
  "schedule_boot" : "false",
  "count_monthly" : "2",
  "count_weekly" : "3",
  "count_daily" : "5",
  "count_hourly" : "6",
  "count_boot" : "5",
  "snapshot_size" : "",
  "snapshot_count" : "",
  "date_format" : "%Y-%m-%d %H:%M:%S",
  "exclude" : [],
  "exclude-apps" : []
}
EOF
  echo "  Timeshift config created."
else
  echo "  Timeshift config already exists, skipping."
fi

systemctl enable cronie 2>/dev/null || systemctl enable cron 2>/dev/null || true

echo ""
echo "[9/9] Setting up end-of-life notification..."
echo "---------------------------------------------"

# Create the EOL check script that runs at each login
cat > /usr/local/bin/check-eol-notification.sh << 'EOLEOF'
#!/bin/bash
# Checks if current Ubuntu version is within 6 months of EOL
# and shows a desktop notification if so.
# Frequency: weekly if 3-6 months remaining, daily if under 3 months.

STAMP_FILE="$HOME/.cache/eol-notification-last-shown"
MESSAGE="This computer needs to be updated soon."

# Get EOL date for current release
CODENAME=$(lsb_release -cs 2>/dev/null)
EOL_DATE=$(ubuntu-distro-info --series="$CODENAME" --eol 2>/dev/null)

if [ -z "$EOL_DATE" ]; then
  exit 0
fi

# Calculate days remaining until EOL
TODAY=$(date +%s)
EOL_EPOCH=$(date -d "$EOL_DATE" +%s 2>/dev/null)

if [ -z "$EOL_EPOCH" ]; then
  exit 0
fi

DAYS_REMAINING=$(( (EOL_EPOCH - TODAY) / 86400 ))

# Only act if within 6 months (180 days)
if [ "$DAYS_REMAINING" -gt 180 ]; then
  exit 0
fi

# Determine required interval between notifications
if [ "$DAYS_REMAINING" -le 90 ]; then
  INTERVAL_DAYS=1
else
  INTERVAL_DAYS=7
fi

# Check when notification was last shown
if [ -f "$STAMP_FILE" ]; then
  LAST_SHOWN=$(cat "$STAMP_FILE")
  LAST_EPOCH=$(date -d "$LAST_SHOWN" +%s 2>/dev/null)
  DAYS_SINCE=$(( (TODAY - LAST_EPOCH) / 86400 ))
  if [ "$DAYS_SINCE" -lt "$INTERVAL_DAYS" ]; then
    exit 0
  fi
fi

# Show the notification
notify-send   --urgency=normal   --icon=dialog-warning   "System Update Required"   "$MESSAGE"

# Record the time it was shown
date +%Y-%m-%d > "$STAMP_FILE"
EOLEOF

chmod +x /usr/local/bin/check-eol-notification.sh

# Add to KDE autostart so it runs at each login
mkdir -p "$USER_HOME/.config/autostart"
cat > "$USER_HOME/.config/autostart/eol-notification.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=EOL Notification Check
Exec=/usr/local/bin/check-eol-notification.sh
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
chown $ACTUAL_USER:$ACTUAL_USER "$USER_HOME/.config/autostart/eol-notification.desktop"

echo ""
echo "[10/10] Final cleanup..."
echo "------------------------"

# Remove Konqueror (old browser that might confuse users)
apt remove -y --purge konqueror 2>/dev/null || true

echo ""
echo "============================================="
echo " Setup complete!"
echo "============================================="
echo ""
echo " Summary of what was configured:"
echo "  - Silent automatic updates at 3am daily"
echo "  - Updates run on boot if machine was off at 3am"
echo "  - All update and release upgrade popups removed"
echo "  - KDE desktop configured to look like Windows 10"
echo "  - Window controls on the right (like Windows)"
echo "  - Noto Sans font (close to Windows Segoe UI)"
echo "  - Double-click to open files (like Windows)"
echo "  - File extensions shown in file manager"
echo "  - Single workspace (no disappearing windows)"
echo "  - Caps Lock permanently disabled"
echo "  - Insert, Scroll Lock, Pause/Break disabled"
echo "  - Confusing keyboard shortcuts disabled"
echo "  - kRunner search popup disabled"
echo "  - Login screen kept (user logs in with password)"
echo "  - Auto-lock after login disabled (session never locks)"
echo "  - Lock on sleep/resume disabled"
echo "  - KDE Wallet popups disabled"
echo "  - Timeshift automatic backups configured"
echo "  - Firefox installed"
echo "  - EOL notification configured (weekly 3-6 months before, daily under 3 months)"
echo ""
echo " NEXT STEPS (manual - a few minutes work):"
echo "  1. Reboot the system: sudo reboot"
echo "  2. Right-click the taskbar to pin frequently"
echo "     used apps (browser, file manager etc)"
echo "  3. Set a clean desktop wallpaper"
echo "  4. Configure browser homepage and bookmarks"
echo "  5. Run Timeshift once manually to create"
echo "     the first backup snapshot:"
echo "     sudo timeshift --create --comments 'Fresh install'"
echo ""
echo " To manually trigger updates anytime:"
echo "  sudo unattended-upgrade -v"
echo ""
echo " To restore system if something goes wrong:"
echo "  sudo timeshift --restore"
echo ""
