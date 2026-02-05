#!/system/bin/sh
# =========================================
# Linux Chroot Manager v6.0.6
# Multi-distro support: Alpine, Ubuntu, Debian, ArchLinux
# =========================================

# ---------------------------
# Color-Coded Message Function
# ---------------------------
print_message() {
    local type="$1"
    local message="$2"
    local RED='\033[91m'
    local PURPLE='\033[95m'
    local CYAN='\033[96m'
    local GREEN='\033[92m'
    local YELLOW='\033[93m'
    local RESET='\033[0m'
    
    # Check if terminal supports colors
    if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
        case "$type" in
            error)   printf "${RED}%s${RESET}\n" "$message" >&2 ;;
            warning) printf "${PURPLE}%s${RESET}\n" "$message" ;;
            note)    printf "${CYAN}%s${RESET}\n" "$message" ;;
            success) printf "${GREEN}%s${RESET}\n" "$message" ;;
            info)    printf "${YELLOW}%s${RESET}\n" "$message" ;;
            *)       printf "%s\n" "$message" ;;
        esac
    else
        # Fallback to plain text if no color support
        printf "%s\n" "$message"
    fi
}

# ---------------------------
# Version Configuration
# ---------------------------
SCRIPT_VERSION="6.0.4"

# Alpine versions
ALPINE_VERSION="3.21.3"
ALPINE_BRANCH="v3.21"

# Ubuntu versions (use full version number from cdimage)
UBUNTU_VERSION="24.04.1"  # Check https://cdimage.ubuntu.com/ubuntu-base/releases/
UBUNTU_CODENAME="noble"   # noble=24.04, jammy=22.04, focal=20.04

# Debian versions (from proot-distro)
DEBIAN_VERSION="v4.29.0"
DEBIAN_RELEASE="trixie"  # trixie=13, bookworm=12, bullseye=11

# ArchLinux version (from proot-distro)
ARCH_VERSION="v4.34.2"

# ---------------------------
# Base Configuration
# ---------------------------
BASE_ROOT=/data/adb/chroot
USER_NAME=user
WORKSPACE_HOST=/data/data/com.termux/files/home/workspace

# Mirrors
ALPINE_MIRROR="${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine}"
UBUNTU_MIRROR="${UBUNTU_MIRROR:-https://cdimage.ubuntu.com}"
PROOT_MIRROR="${PROOT_MIRROR:-https://github.com/termux/proot-distro/releases/download}"

# Detect Termux UID/GID
ANDROID_UID=$(id -u)
ANDROID_GID=$(id -g)

# ---------------------------
# Architecture Detection
# ---------------------------
detect_arch() {
    local machine=$(uname -m)
    case "$machine" in
        aarch64|arm64)
            echo "aarch64"
            ;;
        armv7l|armv8l)
            echo "armv7"
            ;;
        armhf)
            echo "armhf"
            ;;
        x86_64|amd64)
            echo "x86_64"
            ;;
        i386|i686)
            echo "x86"
            ;;
        ppc64le)
            echo "ppc64le"
            ;;
        riscv64)
            echo "riscv64"
            ;;
        s390x)
            echo "s390x"
            ;;
        *)
            echo "[!] Unsupported architecture: $machine" >&2
            exit 1
            ;;
    esac
}

ARCH=$(detect_arch)

# ---------------------------
# Distro-specific Architecture Mapping
# ---------------------------
get_ubuntu_arch() {
    case "$ARCH" in
        aarch64) echo "arm64" ;;
        armv7|armhf) echo "armhf" ;;
        x86_64) echo "amd64" ;;
        i386|x86) echo "i386" ;;
        ppc64le) echo "ppc64el" ;;
        riscv64) echo "riscv64" ;;
        s390x) echo "s390x" ;;
        *) echo "$ARCH" ;;
    esac
}

# ---------------------------
# Root Command Detection & Auto-Elevation
# ---------------------------
check_root_commands() {
    # Check if we have su command
    if ! command -v su >/dev/null 2>&1; then
        echo ""
        echo "╔════════════════════════════════════════════════════╗"
        echo "║                  ERROR: No Root Access             ║"
        echo "╠════════════════════════════════════════════════════╣"
        echo "║  This script requires root access via 'su'.       ║"
        echo "║                                                    ║"
        echo "║  Requirements:                                     ║"
        echo "║    - Rooted Android device (Magisk recommended)    ║"
        echo "║    - Grant root permission when prompted           ║"
        echo "║                                                    ║"
        echo "║  Then run this script again:                       ║"
        echo "║    bash start.sh --install alpine                  ║"
        echo "╚════════════════════════════════════════════════════╝"
        echo ""
        exit 1
    fi
    
    # Test if we can actually use su
    if ! su -c "id -u" >/dev/null 2>&1; then
        echo ""
        echo "╔════════════════════════════════════════════════════╗"
        echo "║              ERROR: Root Access Denied             ║"
        echo "╠════════════════════════════════════════════════════╣"
        echo "║  Device needs to be rooted (Magisk recommended)    ║"
        echo "║                                                    ║"
        echo "║  Common issues:                                    ║"
        echo "║    - Device not rooted                             ║"
        echo "║    - Root access denied to Termux                  ║"
        echo "║    - Magisk app needs to grant permission          ║"
        echo "╚════════════════════════════════════════════════════╝"
        echo ""
        exit 1
    fi
    
    ROOT_SU="su -c"
}

# ---------------------------
# Check if running with sufficient privileges
# ---------------------------
auto_elevate() {
    # If already running as root (uid 0), we're good
    if [ "$(id -u)" = "0" ]; then
        ROOT_SU=""
        return 0
    fi
    
    # Check if we have su available
    check_root_commands
    
    # We'll use su for all root operations
    ROOT_SU="su -c"
}

# ---------------------------
# Helper Functions
# ---------------------------
print_banner() {
    local title="$1"
    echo ""
    echo "╔════════════════════════════════════════════════════╗"
    printf "║ %-50s ║\n" "$title"
    echo "╚════════════════════════════════════════════════════╝"
    echo ""
}

print_info_box() {
    local title="$1"
    shift
    echo ""
    echo "╔════════════════════════════════════════════════════╗"
    printf "║ %-50s ║\n" "$title"
    echo "╠════════════════════════════════════════════════════╣"
    while [ $# -gt 0 ]; do
        printf "║ %-18s %-31s ║\n" "$1" "$2"
        shift 2
    done
    echo "╚════════════════════════════════════════════════════╝"
    echo ""
}

cleanup_mounts() {
    local base="$1"
    $ROOT_SU "umount -l $base/mnt/workspace 2>/dev/null || true"
    $ROOT_SU "umount -l $base/mnt/sdcard 2>/dev/null || true"
    $ROOT_SU "umount -l $base/dev/pts 2>/dev/null || true"
    $ROOT_SU "umount -l $base/dev 2>/dev/null || true"
    $ROOT_SU "umount -l $base/sys 2>/dev/null || true"
    $ROOT_SU "umount -l $base/proc 2>/dev/null || true"
    
    # Restore nosuid on /data for security
    echo "[*] Restoring nosuid on /data..."
    $ROOT_SU "mount -o remount,nodev,nosuid /data 2>/dev/null || true"
}

chroot_exec() {
    local base="$1"
    shift
    $ROOT_SU "chroot $base /usr/bin/env -i \
HOME=/root \
USER=root \
SHELL=/bin/sh \
TERM=$TERM \
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
/bin/sh -c \"$*\""
}

chroot_exec_user() {
    local base="$1"
    shift
    $ROOT_SU "chroot $base /usr/bin/env -i \
HOME=/home/$USER_NAME \
USER=$USER_NAME \
SHELL=/bin/zsh \
TERM=$TERM \
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
su - $USER_NAME -c \"$*\""
}

# ---------------------------
# Version Info Functions
# ---------------------------
get_installed_version() {
    local distro="$1"
    local base="${BASE_ROOT}/${distro}"
    
    if ! is_distro_installed "$distro"; then
        return 1
    fi
    
    case "$distro" in
        alpine)
            if [ -n "$ROOT_SU" ]; then
                $ROOT_SU "cat $base/etc/alpine-release 2>/dev/null" 2>/dev/null
            else
                cat "$base/etc/alpine-release" 2>/dev/null
            fi
            ;;
        ubuntu|debian)
            if [ -n "$ROOT_SU" ]; then
                $ROOT_SU "cat $base/etc/lsb-release 2>/dev/null | grep DISTRIB_RELEASE | cut -d'=' -f2" 2>/dev/null
            else
                cat "$base/etc/lsb-release" 2>/dev/null | grep DISTRIB_RELEASE | cut -d'=' -f2
            fi
            ;;
        archlinux)
            if [ -n "$ROOT_SU" ]; then
                $ROOT_SU "cat $base/etc/os-release 2>/dev/null | grep '^NAME=' | cut -d'=' -f2 | tr -d '\"'" 2>/dev/null
            else
                cat "$base/etc/os-release" 2>/dev/null | grep '^NAME=' | cut -d'=' -f2 | tr -d '"'
            fi
            ;;
    esac
}

is_distro_installed() {
    local distro="$1"
    local base="${BASE_ROOT}/${distro}"
    
    # Use su to check if directory exists (handles permission issues)
    if [ -n "$ROOT_SU" ]; then
        if $ROOT_SU "[ -d '$base/bin' ] && echo 1 || echo 0" 2>/dev/null | grep -q "1"; then
            return 0
        else
            return 1
        fi
    else
        # Running as root already
        if [ -d "$base/bin" ]; then
            return 0
        else
            return 1
        fi
    fi
}

# ---------------------------
# Alpine Installation
# ---------------------------
install_alpine() {
    local base="${BASE_ROOT}/alpine"
    local rootfs_filename="alpine-minirootfs-${ALPINE_VERSION}-${ARCH}.tar.gz"
    local rootfs_url="${ALPINE_MIRROR}/${ALPINE_BRANCH}/releases/${ARCH}/${rootfs_filename}"
    
    print_info_box "Installing Alpine Linux" \
        "Architecture:" "$ARCH" \
        "Version:" "$ALPINE_VERSION" \
        "Branch:" "$ALPINE_BRANCH"
    
    echo "[*] Creating base directories..."
    $ROOT_SU "mkdir -p $base/mnt/workspace $base/mnt/sdcard"
    $ROOT_SU "mkdir -p $WORKSPACE_HOST"
    
    echo "[*] Downloading Alpine rootfs..."
    echo "    $rootfs_filename"
    
    curl -fL --progress-bar -o ./rootfs.tar.gz "$rootfs_url"
    if [ $? -ne 0 ]; then
        echo "[!] Download failed, aborting."
        $ROOT_SU "rm -rf $base"
        exit 1
    fi
    
    echo "[*] Extracting rootfs..."
    $ROOT_SU "tar -xpf ./rootfs.tar.gz --numeric-owner -C $base"
    rm -f ./rootfs.tar.gz
    
    echo "[*] Configuring DNS..."
    chroot_exec "$base" "echo 'nameserver 8.8.8.8' > /etc/resolv.conf"
    chroot_exec "$base" "echo 'nameserver 1.1.1.1' >> /etc/resolv.conf"
    
    echo "[*] Installing essential packages..."
    chroot_exec "$base" "apk update && apk add --no-cache bash zsh sudo openssh-client wget nano vim git curl ncurses libstdc++ libgcc"
    
    configure_user "$base" "alpine"
    configure_zsh "$base"
    
    # Save version info
    chroot_exec "$base" "cat > /etc/distro-info << EOF
Distro: Alpine Linux
Version: $ALPINE_VERSION
Branch: $ALPINE_BRANCH
Architecture: $ARCH
Installed: \$(date '+%Y-%m-%d %H:%M:%S')
EOF"
    
    echo ""
    echo "[✓] Alpine Linux $ALPINE_VERSION installed successfully!"
    echo ""
}

# ---------------------------
# Ubuntu Installation
# ---------------------------
install_ubuntu() {
    local base="${BASE_ROOT}/ubuntu"
    local ubuntu_arch=$(get_ubuntu_arch)
    local rootfs_filename="ubuntu-base-${UBUNTU_VERSION}-base-${ubuntu_arch}.tar.gz"
    local rootfs_url="${UBUNTU_MIRROR}/ubuntu-base/releases/${UBUNTU_VERSION}/release/${rootfs_filename}"
    
    print_info_box "Installing Ubuntu Linux" \
        "Architecture:" "$ubuntu_arch" \
        "Version:" "$UBUNTU_VERSION" \
        "Codename:" "$UBUNTU_CODENAME"
    
    echo "[*] Creating base directories..."
    $ROOT_SU "mkdir -p $base/mnt/workspace $base/mnt/sdcard"
    $ROOT_SU "mkdir -p $WORKSPACE_HOST"
    
    echo "[*] Downloading Ubuntu rootfs..."
    echo "    $rootfs_filename"
    echo "    URL: $rootfs_url"
    
    curl -fL --progress-bar -o ./rootfs.tar.gz "$rootfs_url"
    if [ $? -ne 0 ]; then
        echo "[!] Download failed, aborting."
        echo "[!] Check if version exists at: ${UBUNTU_MIRROR}/ubuntu-base/releases/"
        $ROOT_SU "rm -rf $base"
        exit 1
    fi
    
    echo "[*] Extracting rootfs..."
    $ROOT_SU "tar -xpf ./rootfs.tar.gz --numeric-owner -C $base"
    rm -f ./rootfs.tar.gz
    
    echo "[*] Configuring DNS..."
    chroot_exec "$base" "echo 'nameserver 8.8.8.8' > /etc/resolv.conf"
    chroot_exec "$base" "echo 'nameserver 1.1.1.1' >> /etc/resolv.conf"
    
    # Mount /dev before running apt (needed for /dev/null access)
    echo "[*] Mounting essential filesystems for package installation..."
    $ROOT_SU "mount -t proc proc $base/proc 2>/dev/null || true"
    $ROOT_SU "mount --rbind /sys $base/sys 2>/dev/null || true"
    $ROOT_SU "mount --rbind /dev $base/dev 2>/dev/null || true"
    $ROOT_SU "mount -t devpts devpts $base/dev/pts 2>/dev/null || true"
    
    echo "[*] Updating package lists..."
    chroot_exec "$base" "apt-get update"
    
    echo "[*] Installing essential packages..."
    chroot_exec "$base" "DEBIAN_FRONTEND=noninteractive apt-get install -y bash zsh sudo openssh-client wget nano vim git curl locales"
    
    echo "[*] Configuring locales..."
    chroot_exec "$base" "locale-gen en_US.UTF-8"
    chroot_exec "$base" "update-locale LANG=en_US.UTF-8"
    
    # Unmount before configure_user (will be remounted when starting)
    cleanup_mounts "$base"
    
    configure_user "$base" "ubuntu"
    configure_zsh "$base"
    
    # Save version info
    chroot_exec "$base" "cat > /etc/distro-info << EOF
Distro: Ubuntu Linux
Version: $UBUNTU_VERSION
Codename: $UBUNTU_CODENAME
Architecture: $ubuntu_arch
Installed: \$(date '+%Y-%m-%d %H:%M:%S')
EOF"
    
    echo ""
    echo "[✓] Ubuntu $UBUNTU_VERSION installed successfully!"
    echo ""
}

# ---------------------------
# Debian Installation
# ---------------------------
install_debian() {
    local base="${BASE_ROOT}/debian"
    # Debian uses same arch naming as proot-distro: aarch64, x86_64, i686, arm
    local debian_arch=$(echo "$ARCH" | sed 's/armv7/arm/g; s/armhf/arm/g')
    local rootfs_filename="debian-${DEBIAN_RELEASE}-${debian_arch}-pd-${DEBIAN_VERSION}.tar.xz"
    local rootfs_url="${PROOT_MIRROR}/${DEBIAN_VERSION}/${rootfs_filename}"
    
    print_info_box "Installing Debian Linux" \
        "Architecture:" "$debian_arch" \
        "Version:" "13 (${DEBIAN_RELEASE})" \
        "Release:" "$DEBIAN_VERSION"
    
    echo "[*] Creating base directories..."
    $ROOT_SU "mkdir -p $base/mnt/workspace $base/mnt/sdcard"
    $ROOT_SU "mkdir -p $WORKSPACE_HOST"
    
    echo "[*] Downloading Debian rootfs..."
    echo "    $rootfs_filename"
    echo "    URL: $rootfs_url"
    
    curl -fL --progress-bar -o ./rootfs.tar.xz "$rootfs_url"
    if [ $? -ne 0 ]; then
        echo "[!] Download failed, aborting."
        echo "[!] Check if version exists at: ${PROOT_MIRROR}/${DEBIAN_VERSION}/"
        $ROOT_SU "rm -rf $base"
        exit 1
    fi
    
    echo "[*] Extracting rootfs..."
        # Fallback: try tar auto-detection (may not work on all systems)
    $ROOT_SU "busybox tar -xpf ./rootfs.tar.xz --numeric-owner --strip-components=1 -C $base" 2>/dev/null || {
      echo "[!] xz decompression not available."
      echo "[!] Install xz-utils in Termux: pkg install xz-utils"
      echo "[!] Then try again: bash $0 --install debian"
      $ROOT_SU "rm -rf $base"
      rm -f ./rootfs.tar.xz
      exit 1
    }
    rm -f ./rootfs.tar.xz
    
    echo "[*] Configuring DNS..."
    chroot_exec "$base" "echo 'nameserver 8.8.8.8' > /etc/resolv.conf"
    chroot_exec "$base" "echo 'nameserver 1.1.1.1' >> /etc/resolv.conf"
    
    # Mount /dev temporarily for apt operations
    echo "[*] Mounting essential filesystems for package installation..."
    $ROOT_SU "mount -t proc proc $base/proc 2>/dev/null || true"
    $ROOT_SU "mount --rbind /sys $base/sys 2>/dev/null || true"
    $ROOT_SU "mount --rbind /dev $base/dev 2>/dev/null || true"
    $ROOT_SU "mount -t devpts devpts $base/dev/pts 2>/dev/null || true"
    
    echo "[*] Updating package lists..."
    chroot_exec "$base" "apt-get update"
    
    echo "[*] Installing essential packages..."
    chroot_exec "$base" "DEBIAN_FRONTEND=noninteractive apt-get install -y bash zsh sudo openssh-client wget nano vim git curl"
    
    configure_user "$base" "debian"
    configure_zsh "$base"
    
    # Save version info
    chroot_exec "$base" "cat > /etc/distro-info << EOF
Distro: Debian Linux
Version: 13 (${DEBIAN_RELEASE})
Release: $DEBIAN_VERSION
Architecture: $debian_arch
Installed: \$(date '+%Y-%m-%d %H:%M:%S')
EOF"
    cleanup_mounts "$base"
    
    echo ""
    echo "[✓] Debian ${DEBIAN_RELEASE} installed successfully!"
    echo ""
}

# ---------------------------
# ArchLinux Installation
# ---------------------------
install_archlinux() {
    local base="${BASE_ROOT}/archlinux"
    local arch_arch=$(get_ubuntu_arch)  # ArchLinux uses aarch64, x86_64, etc
    # Convert to proot-distro naming
    case "$arch_arch" in
        arm64) arch_arch="aarch64" ;;
        amd64) arch_arch="x86_64" ;;
        armhf) arch_arch="arm" ;;
        i386) arch_arch="i686" ;;
    esac
    
    local rootfs_filename="archlinux-${arch_arch}-pd-${ARCH_VERSION}.tar.xz"
    local rootfs_url="${PROOT_MIRROR}/${ARCH_VERSION}/${rootfs_filename}"
    
    print_info_box "Installing ArchLinux" \
        "Architecture:" "$arch_arch" \
        "Version:" "$ARCH_VERSION"
    
    echo "[*] Creating base directories..."
    $ROOT_SU "mkdir -p $base/mnt/workspace $base/mnt/sdcard"
    $ROOT_SU "mkdir -p $WORKSPACE_HOST"
    
    echo "[*] Downloading ArchLinux rootfs..."
    echo "    $rootfs_filename"
    echo "    URL: $rootfs_url"
    
    curl -fL --progress-bar -o ./rootfs.tar.xz "$rootfs_url"
    if [ $? -ne 0 ]; then
        echo "[!] Download failed, aborting."
        echo "[!] Check if version exists at: ${PROOT_MIRROR}/${ARCH_VERSION}/"
        $ROOT_SU "rm -rf $base"
        exit 1
    fi
    
    echo "[*] Extracting rootfs..."
        # Fallback: try tar auto-detection (may not work on all systems)
    $ROOT_SU "busybox tar -xpf ./rootfs.tar.xz --numeric-owner --strip-components=1 -C $base" 2>/dev/null || {
      echo "[!] xz decompression not available."
      echo "[!] Install xz-utils in Termux: pkg install xz-utils"
      echo "[!] Then try again: bash $0 --install archlinux"
      $ROOT_SU "rm -rf $base"
      rm -f ./rootfs.tar.xz
      exit 1
    }
    rm -f ./rootfs.tar.xz
    
    echo "[*] Configuring DNS..."
    chroot_exec "$base" "echo 'nameserver 8.8.8.8' > /etc/resolv.conf"
    chroot_exec "$base" "echo 'nameserver 1.1.1.1' >> /etc/resolv.conf"
    
    echo "[*] Mounting essential filesystems for package installation..."
    $ROOT_SU "mount -t proc proc $base/proc 2>/dev/null || true"
    $ROOT_SU "mount --rbind /sys $base/sys 2>/dev/null || true"
    $ROOT_SU "mount --rbind /dev $base/dev 2>/dev/null || true"
    $ROOT_SU "mount -t devpts devpts $base/dev/pts 2>/dev/null || true"
    
    echo "[*] Initializing pacman keyring..."
    mkdir -p $base/var/cache/pacman/pkg
    $ROOT_SU "mount -t tmpfs tmpfs $base/var/cache/pacman/pkg"
    chroot_exec "$base" "chmod 755 /var/cache /var/cache/pacman /var/cache/pacman/pkg"


    chroot_exec "$base" "pacman-key --init"
    chroot_exec "$base" "pacman-key --populate archlinux"
    
    echo "[*] Updating package database..."
    chroot_exec "$base" "pacman -Sy"
    
    echo "[*] Installing essential packages..."
    chroot_exec "$base" "pacman -S --noconfirm bash zsh sudo openssh wget nano vim git curl"
    
    configure_user "$base" "archlinux"
    configure_zsh "$base"
    
    # Save version info
    chroot_exec "$base" "cat > /etc/distro-info << EOF
Distro: Arch Linux
Version: $ARCH_VERSION
Architecture: $arch_arch
Installed: \$(date '+%Y-%m-%d %H:%M:%S')
EOF"
    cleanup_mounts "$base"
    
    echo ""
    echo "[✓] ArchLinux installed successfully!"
    echo ""
}

# ---------------------------
# User Configuration (common)
# ---------------------------
configure_user() {
    local base="$1"
    local distro="$2"
    
    echo "[*] Creating user '$USER_NAME'..."
    
    case "$distro" in
        alpine)
            chroot_exec "$base" "addgroup -g $ANDROID_GID $USER_NAME 2>/dev/null || true"
            chroot_exec "$base" "adduser -h /home/$USER_NAME -s /bin/zsh -u $ANDROID_UID -G $USER_NAME -D $USER_NAME 2>/dev/null || true"
            ;;
        ubuntu|debian)
            chroot_exec "$base" "groupadd -g $ANDROID_GID $USER_NAME 2>/dev/null || true"
            chroot_exec "$base" "useradd -m -d /home/$USER_NAME -s /bin/zsh -u $ANDROID_UID -g $ANDROID_GID $USER_NAME 2>/dev/null || true"
            ;;
        archlinux)
            chroot_exec "$base" "groupadd -g $ANDROID_GID $USER_NAME 2>/dev/null || true"
            chroot_exec "$base" "useradd -m -d /home/$USER_NAME -s /bin/zsh -u $ANDROID_UID -g $ANDROID_GID $USER_NAME 2>/dev/null || true"
            ;;
    esac
    
    chroot_exec "$base" "mkdir -p /home/$USER_NAME && chown -R $USER_NAME:$USER_NAME /home/$USER_NAME"
    
    echo "[*] Configuring sudoers..."
    chroot_exec "$base" "mkdir -p /etc/sudoers.d"
    chroot_exec "$base" "echo '$USER_NAME ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/$USER_NAME"
    chroot_exec "$base" "chmod 440 /etc/sudoers.d/$USER_NAME"
}

# ---------------------------
# Zsh Configuration (common)
# ---------------------------
configure_zsh() {
    local base="$1"
    
    echo "[*] Configuring Termux key bindings..."
    
    # Configure root .zshrc
    chroot_exec "$base" "cat > /root/.zshrc << 'ZSHRC_EOF'
# Termux key bindings for Home and End keys
bindkey '^[[H' beginning-of-line  # Home key
bindkey '^[[F' end-of-line        # End key
bindkey '^[[1~' beginning-of-line # Alternative Home
bindkey '^[[4~' end-of-line       # Alternative End
bindkey '^[[3~' delete-char       # Delete key

# History configuration
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY
setopt APPEND_HISTORY
setopt INC_APPEND_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_REDUCE_BLANKS
setopt HIST_VERIFY
ZSHRC_EOF"
    
    echo "[*] Installing Oh-My-Zsh for '$USER_NAME'..."
    
    # Mount /dev temporarily for git (needs /dev/urandom)
    echo "[*] Mounting /dev for git operations..."
    $ROOT_SU "mount --rbind /dev $base/dev 2>/dev/null || true"
    
    # Clone Oh-My-Zsh
    chroot_exec "$base" "git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git /home/$USER_NAME/.oh-my-zsh"
    
    if [ $? -ne 0 ]; then
        echo "[!] Oh-My-Zsh installation failed, creating basic .zshrc instead"
        chroot_exec "$base" "cat > /home/$USER_NAME/.zshrc << 'BASIC_ZSHRC_EOF'
# Basic zsh configuration
# Termux key bindings
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[[3~' delete-char

# History
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY
setopt APPEND_HISTORY
setopt INC_APPEND_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_REDUCE_BLANKS

# Auto-cd to workspace on login
if [ -d /mnt/workspace ]; then
  cd /mnt/workspace
fi
BASIC_ZSHRC_EOF"
    else
        # Oh-My-Zsh installed successfully
        chroot_exec "$base" "cp /home/$USER_NAME/.oh-my-zsh/templates/zshrc.zsh-template /home/$USER_NAME/.zshrc"
        
        chroot_exec "$base" "cat >> /home/$USER_NAME/.zshrc << 'OMZ_EOF'

# --- Custom Android-Linux Config ---

# Key Bindings
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[[3~' delete-char

# History
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY

# Auto-cd to workspace on login
if [ -d /mnt/workspace ]; then
  cd /mnt/workspace
fi
OMZ_EOF"
        echo "[✓] Oh-My-Zsh installed successfully!"
    fi
    
    # Unmount /dev (will be remounted when starting)
    $ROOT_SU "umount -l $base/dev 2>/dev/null || true"
    
    chroot_exec "$base" "chown -R $USER_NAME:$USER_NAME /home/$USER_NAME"
    chroot_exec "$base" "touch /home/$USER_NAME/.zsh_history && chown $USER_NAME:$USER_NAME /home/$USER_NAME/.zsh_history"
    chroot_exec "$base" "touch /root/.zsh_history"
    
    echo "[✓] Zsh configuration complete!"
}

# ---------------------------
# Mount Filesystems
# ---------------------------
mount_filesystems() {
    local base="$1"
    
    $ROOT_SU "mount -t proc proc $base/proc 2>/dev/null || true"
    $ROOT_SU "mount --rbind /sys $base/sys 2>/dev/null || true"
    $ROOT_SU "mount --rbind /dev $base/dev 2>/dev/null || true"
    $ROOT_SU "mount -t devpts devpts $base/dev/pts 2>/dev/null || true"
    $ROOT_SU "mount --rbind $WORKSPACE_HOST $base/mnt/workspace 2>/dev/null || true"
    $ROOT_SU "mount --rbind /sdcard $base/mnt/sdcard 2>/dev/null || true"
}

# ---------------------------
# Start Chroot
# ---------------------------
start_chroot() {
    local distro="$1"
    local base="${BASE_ROOT}/${distro}"
    
    if ! is_distro_installed "$distro"; then
        echo "[!] $distro is not installed. Use: bash $0 --install $distro"
        exit 1
    fi
    
    # Setup cleanup trap
    trap "cleanup_mounts $base" EXIT
    
    # Fix nosuid on /data so sudo/su works inside chroot
    echo "[*] Enabling suid on /data for sudo/su support..."
    $ROOT_SU "mount -o remount,dev,suid /data 2>/dev/null || true"
    
    # Mount filesystems
    mount_filesystems "$base"
    
    print_banner "Starting ${distro^} Linux"
    echo "  User: $USER_NAME"
    echo "  Workspace: /mnt/workspace"
    echo "  SD Card: /mnt/sdcard"
    echo "  sudo/su: ✓ Enabled"
    echo ""
    
    $ROOT_SU "chroot $base /usr/bin/env -i \
HOME=/home/$USER_NAME \
USER=$USER_NAME \
SHELL=/bin/zsh \
TERM=$TERM \
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
su - $USER_NAME"
}

# ---------------------------
# Uninstall Distro
# ---------------------------
uninstall_distro() {
    local distro="$1"
    local base="${BASE_ROOT}/${distro}"
    
    if ! is_distro_installed "$distro"; then
        echo "[!] $distro is not installed."
        exit 1
    fi
    
    echo "[*] Uninstalling $distro..."
    cleanup_mounts "$base"
    
    # Remove everything except /mnt directory
    echo "[*] Removing system files (preserving /mnt directory)..."
    $ROOT_SU "find $base -mindepth 1 -maxdepth 1 ! -name 'mnt' -exec rm -rf {} +"
    
    # Check if directory is empty except for mnt
    if [ -d "$base/mnt" ]; then
        echo "[✓] $distro uninstalled (workspace and sdcard mount points preserved)"
    else
        $ROOT_SU "rm -rf $base"
        echo "[✓] $distro uninstalled completely"
    fi
}

# ---------------------------
# Reinstall Distro
# ---------------------------
reinstall_distro() {
    local distro="$1"
    
    echo "[*] Reinstalling $distro..."
    echo ""
    
    if is_distro_installed "$distro"; then
        uninstall_distro "$distro"
    fi
    
    case "$distro" in
        alpine)
            install_alpine
            ;;
        ubuntu)
            install_ubuntu
            ;;
        debian)
            install_debian
            ;;
        archlinux)
            install_archlinux
            ;;
        *)
            echo "[!] Unknown distro: $distro"
            exit 1
            ;;
    esac
}

# ---------------------------
# Show Version
# ---------------------------
show_version() {
    echo ""
    echo "╔════════════════════════════════════════════════════╗"
    echo "║          Linux Chroot Manager v${SCRIPT_VERSION}                ║"
    echo "╠════════════════════════════════════════════════════╣"
    echo "║  Supported Distributions:                          ║"
    echo "║                                                    ║"
    printf "║    Alpine:    %-36s ║\n" "v${ALPINE_VERSION}"
    printf "║    Ubuntu:    %-36s ║\n" "v${UBUNTU_VERSION} (${UBUNTU_CODENAME})"
    printf "║    Debian:    %-36s ║\n" "v13 (${DEBIAN_RELEASE})"
    printf "║    ArchLinux: %-36s ║\n" "${ARCH_VERSION}"
    echo "║                                                    ║"
    echo "╠════════════════════════════════════════════════════╣"
    echo "║  Installed Distributions:                          ║"
    echo "║                                                    ║"
    
    for distro in alpine ubuntu debian archlinux; do
        if is_distro_installed "$distro"; then
            local version=$(get_installed_version "$distro")
            printf "║    %-10s %-35s ║\n" "$distro:" "✓ v$version"
        else
            printf "║    %-10s %-35s ║\n" "$distro:" "✗ Not installed"
        fi
    done
    
    echo "╚════════════════════════════════════════════════════╝"
    echo ""
}

# ---------------------------
# Show Help
# ---------------------------
show_help() {
    echo "Linux Chroot Manager v${SCRIPT_VERSION}"
    echo "Multi-distro support: Alpine, Ubuntu, Debian, ArchLinux"
    echo ""
    echo "Usage: bash $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  --install <distro>      Install distro (alpine/ubuntu/debian/archlinux)"
    echo "  --uninstall <distro>    Uninstall specified distro (preserves /mnt)"
    echo "  --reinstall <distro>    Reinstall specified distro (preserves /mnt)"
    echo "  --start <distro>        Start specified distro"
    echo "  --version               Show version information"
    echo "  --help                  Show this help message"
    echo ""
    echo "Requirements:"
    echo "  - Rooted Android device (Magisk recommended)"
    echo "  - Internet connection for installation"
    echo "  - For Debian/ArchLinux: pkg install xz-utils (in Termux)"
    echo ""
    echo "Note: Script automatically elevates privileges using 'su'"
    echo "      No need to run with sudo or install additional tools!"
    echo ""
    echo "Features:"
    echo "  - 4 distributions: Alpine, Ubuntu, Debian, ArchLinux"
    echo "  - Termux key bindings (Home/End keys)"
    echo "  - Persistent zsh history"
    echo "  - Oh-My-Zsh integration"
    echo "  - Workspace & SD card mounting"
    echo "  - sudo/su works inside chroot (dev,suid mount)"
    echo ""
    echo "Examples:"
    echo "  bash $0 --install alpine       # Install Alpine Linux"
    echo "  bash $0 --install ubuntu       # Install Ubuntu Linux"
    echo "  bash $0 --install debian       # Install Debian Linux"
    echo "  bash $0 --install archlinux    # Install ArchLinux"
    echo "  bash $0 --start alpine         # Start Alpine"
    echo "  bash $0 --start archlinux      # Start ArchLinux"
    echo "  bash $0 --reinstall debian     # Reinstall Debian"
    echo "  bash $0 --uninstall ubuntu     # Uninstall Ubuntu"
    echo "  bash $0 --version              # Show version info"
    echo ""
    echo "Default behavior (no args):"
    echo "  Starts Alpine if installed, otherwise shows help"
    echo ""
}

# ---------------------------
# Main Script Logic
# ---------------------------

# Initialize root command wrapper (auto-elevate if needed)
auto_elevate

# Parse arguments
if [ $# -eq 0 ]; then
    # Default behavior: start alpine if installed
    if is_distro_installed "alpine"; then
        start_chroot "alpine"
    else
        echo "[!] No distro installed. Use --help for usage information."
        echo ""
        show_version
        exit 1
    fi
fi

# Parse commands
COMMAND=""
DISTRO=""

while [ $# -gt 0 ]; do
    case "$1" in
        --install|--uninstall|--reinstall|--start)
            COMMAND="${1#--}"
            shift
            if [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; then
                DISTRO="$1"
                shift
            else
                echo "[!] $COMMAND requires a distro argument (alpine/ubuntu)"
                exit 1
            fi
            ;;
        --version)
            show_version
            exit 0
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "[!] Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate distro
if [ -n "$DISTRO" ] && [ "$DISTRO" != "alpine" ] && [ "$DISTRO" != "ubuntu" ] && [ "$DISTRO" != "debian" ] && [ "$DISTRO" != "archlinux" ]; then
    echo "[!] Unknown distro: $DISTRO"
    echo "Supported distros: alpine, ubuntu, debian, archlinux"
    exit 1
fi

# Execute command
case "$COMMAND" in
    install)
        if is_distro_installed "$DISTRO"; then
            echo "[!] $DISTRO is already installed."
            echo "Use --reinstall to reinstall, or --uninstall to remove it first."
            exit 1
        fi
        
        case "$DISTRO" in
            alpine) install_alpine ;;
            ubuntu) install_ubuntu ;;
            debian) install_debian ;;
            archlinux) install_archlinux ;;
        esac
        ;;
    
    uninstall)
        uninstall_distro "$DISTRO"
        ;;
    
    reinstall)
        reinstall_distro "$DISTRO"
        ;;
    
    start)
        start_chroot "$DISTRO"
        ;;
    
    *)
        echo "[!] Unknown command: $COMMAND"
        echo "Use --help for usage information"
        exit 1
        ;;
esac
