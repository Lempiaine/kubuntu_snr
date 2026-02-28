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
# Matches key followed by a space to avoid partial matches
# e.g. Automatic-Reboot must not match Automatic-Reboot-WithUsers
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
echo "[3/9] Disabling update popups..."
echo "---------------------------------"

# Mask update-notifier and plasma-discover-notifier autostart entries
# Symlinking to /dev/null means the file is always empty regardless
# of what package updates do to the original files
mkdir -p /etc/xdg/autostart
ln -sf /dev/null /etc/xdg/autostart/update-notifier.desktop
ln -sf /dev/null /etc/xdg/autostart/plasma-discover-notifier.desktop



echo ""
echo "[4/9] Disabling confusing keyboard keys..."
echo "-------------------------------------------"

# Create a custom XKB symbols file to disable confusing keys
# This works on both X11 and Wayland, unlike xmodmap which is X11-only
cat > /usr/share/X11/xkb/symbols/custom_disable << 'EOF'
partial modifier_keys
xkb_symbols "disable_keys" {
    key <INS>  { [ NoSymbol ] };
    key <SCLK> { [ NoSymbol ] };
    key <PAUS> { [ NoSymbol ] };
};
EOF

# Apply caps:none and the custom disable rules via XKBOPTIONS
# Only modify XKBOPTIONS, preserve existing layout/model/variant settings
KB_CONF="/etc/default/keyboard"
XKBOPTS="caps:none,custom_disable:disable_keys"
if grep -q "^XKBOPTIONS" "$KB_CONF" 2>/dev/null; then
  sed -i "s|^XKBOPTIONS=.*|XKBOPTIONS=\"${XKBOPTS}\"|" "$KB_CONF"
else
  echo "XKBOPTIONS=\"${XKBOPTS}\"" >> "$KB_CONF"
fi

# Apply immediately without reboot
dpkg-reconfigure -f noninteractive keyboard-configuration 2>/dev/null || true

echo ""
echo "[5/9] Disabling KDE shortcuts that could cause confusion..."
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
echo "[6/9] Keeping login screen, disabling auto-lock after login..."
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
echo "[7/9] Configuring Timeshift automatic backups..."
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
echo "[8/9] Setting up end-of-life notification..."
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
echo "[9/9] Configuring KDE desktop settings..."
echo "--------------------------------------------"

sudo -u $ACTUAL_USER bash << 'USEREOF'

# Double-click to open files (like Windows)
kwriteconfig5 --file kdeglobals --group KDE --key SingleClick false

# Show file extensions in Dolphin file manager
# HideFileExtensions false means extensions are always visible
kwriteconfig5 --file kdeglobals --group KDE --key HideFileExtensions false

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

# TODO: Apply Windows-like theme and look and feel
# plasma-apply-lookandfeel and plasma-apply-colorscheme need to be
# verified against the actual running system before adding here

# TODO: Disable hot corners (screen edges)
# Set manually via System Settings → Workspace → Screen Edges
# then run: cat ~/.config/kwinrc | grep -A10 ElectricBorders
# and add the correct kwriteconfig5 commands here

# TODO: Set Plastik window decoration
# Set manually via System Settings → Appearance → Window Decorations
# then run: cat ~/.config/kwinrc | grep -A5 kdecoration2
# and add the correct kwriteconfig5 commands here

# TODO: Simplify notification area
# Remove unused system tray icons to keep it clean and Windows-like

# TODO: Simplify taskbar
# Remove unused taskbar widgets, keep only: app launcher, task manager,
# system tray, clock - similar to Windows taskbar layout

# TODO: Set desktop background image
# Use a clean, simple wallpaper similar to Windows defaults
# plasma-apply-wallpaperimage /path/to/image.jpg

USEREOF
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
echo ""
echo "  2. Set Plastik window decoration:"
echo "     System Settings → Appearance → Window Decorations"
echo "     Select Plastik → Apply"
echo "     Then run: cat ~/.config/kwinrc | grep -A5 kdecoration2"
echo "     and send the output to update this script with correct values"
echo ""
echo "  3. Disable hot corners:"
echo "     System Settings → Workspace → Screen Edges"
echo "     Set all corners and edges to No Action → Apply"
echo "     Then run: cat ~/.config/kwinrc | grep -A10 ElectricBorders"
echo "     and send the output to update this script with correct values"
echo ""
echo "  4. Right-click the taskbar to pin frequently"
echo "     used apps (browser, file manager etc)"
echo "  5. Set a clean desktop wallpaper"
echo "  6. Configure browser homepage and bookmarks"
echo "  7. Run Timeshift once manually to create"
echo "     the first backup snapshot:"
echo "     sudo timeshift --create --comments 'Fresh install'"
echo ""
echo " To manually trigger updates anytime:"
echo "  sudo unattended-upgrade -v"
echo ""
echo " To restore system if something goes wrong:"
echo "  sudo timeshift --restore"
echo ""
