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
echo "[1/6] Installing required packages..."
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
echo "[2/6] Configuring silent automatic updates..."
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
echo "[3/6] Disabling update popups..."
echo "---------------------------------"

# Mask update-notifier and plasma-discover-notifier autostart entries
# Symlinking to /dev/null means the file is always empty regardless
# of what package updates do to the original files
mkdir -p /etc/xdg/autostart
ln -sf /dev/null /etc/xdg/autostart/update-notifier.desktop
ln -sf /dev/null /etc/xdg/autostart/plasma-discover-notifier.desktop
ln -sf /dev/null /etc/xdg/autostart/org.kde.discover.notifier.desktop



echo ""
echo "[4/6] Disabling confusing keyboard keys..."
echo "-------------------------------------------"

# Disable Caps Lock system-wide via keyboard config
KB_CONF="/etc/default/keyboard"
if grep -q "^XKBOPTIONS" "$KB_CONF" 2>/dev/null; then
  if ! grep -q "caps:none" "$KB_CONF"; then
    sed -i 's|^XKBOPTIONS="\(.*\)"|XKBOPTIONS="\1,caps:none"|' "$KB_CONF"
    sed -i 's|^XKBOPTIONS="",caps:none|XKBOPTIONS="caps:none"|' "$KB_CONF"
  fi
else
  echo 'XKBOPTIONS="caps:none"' >> "$KB_CONF"
fi

# Disable Insert, Scroll Lock and Pause/Break via xmodmap at login
# xmodmap runs under X11 which is the default on Kubuntu
# keycodes: 118=Insert, 78=Scroll Lock, 127=Pause/Break
# Written as the actual user so ownership is correct without chown
sudo -u $ACTUAL_USER bash << 'USEREOF'
cat > "$HOME/.Xmodmap" << 'EOF'
! Disable Insert key (prevents accidental overtype mode in text editors)
keycode 118 = NoSymbol

! Disable Scroll Lock (does nothing useful for regular users)
keycode 78 = NoSymbol

! Disable Pause/Break key (does nothing useful for regular users)
keycode 127 = NoSymbol
EOF
USEREOF
# KDE automatically applies ~/.Xmodmap at login - no autostart entry needed



echo ""
echo "[5/6] Disabling auto-lock, screen blanking and sleep..."
echo "--------------------------------------------------------"

# Login screen (SDDM) is kept so user logs in normally with password
# But once logged in: no auto-lock, no screen blanking, no sleep

sudo -u $ACTUAL_USER bash << 'USEREOF'
# Disable screen locker
kwriteconfig5 --file kscreenlockerrc --group Daemon --key Autolock false
kwriteconfig5 --file kscreenlockerrc --group Daemon --key LockOnResume false
kwriteconfig5 --file kscreenlockerrc --group Daemon --key LockOnLidClose false
kwriteconfig5 --file kscreenlockerrc --group Daemon --key Timeout 0

# Disable display power management (screen blanking and turning off)
# DPMSEnabled false = no screen off; StandbyDefault/SuspendDefault/OffDefault = 0 = never
kwriteconfig5 --file powermanagementprofilesrc --group AC --group DPMSControl --key idleTime 0
kwriteconfig5 --file powermanagementprofilesrc --group AC --group DPMSControl --key lockBeforeTurnOff false
kwriteconfig5 --file powermanagementprofilesrc --group AC --group SuspendSession --key idleTime 0
kwriteconfig5 --file powermanagementprofilesrc --group AC --group SuspendSession --key suspendThenHibernate false
kwriteconfig5 --file powermanagementprofilesrc --group AC --group SuspendSession --key suspendType 0
USEREOF



echo ""
echo "[6/6] Setting up end-of-life notification..."
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
sudo -u $ACTUAL_USER bash << 'USEREOF'
mkdir -p "$HOME/.config/autostart"
cat > "$HOME/.config/autostart/eol-notification.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=EOL Notification Check
Exec=/usr/local/bin/check-eol-notification.sh
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
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
echo "  - Caps Lock permanently disabled"
echo "  - Insert, Scroll Lock, Pause/Break disabled"
echo "  - Login screen kept (user logs in with password)"
echo "  - Auto-lock after login disabled (session never locks)"
echo "  - Screen blanking and sleep disabled"
echo "  - Firefox installed"
echo "  - EOL notification configured (weekly 3-6 months before, daily under 3 months)"
echo ""
echo " NEXT STEPS:"
echo "  1. Reboot the system: sudo reboot"
echo ""
echo " To manually trigger updates anytime:"
echo "  sudo unattended-upgrade -v"
echo ""
echo ""
echo "TODO:"
echo "- Remove extra apps from task bar"
echo "- Remove extra icons from the bottom right panel"
echo "- Change desktop background"
echo "- Firefox to taskbar and desktop"
echo "- Firefox favourites"





