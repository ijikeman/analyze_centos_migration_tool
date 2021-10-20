#!/bin/bash

# 元に戻す
# /etc/migrate2ml/backup_release_file /etc/*-releaseファイルのバックアップ先から戻す
# /etc/migrate2ml 実行履歴保存先
# BRAND_PKGS 商材名が含まれているパッケージを元に戻す。
# REMOVE_PKGS CentOS独自のパッケージ(バグレポート等)を元に戻す
# BOOTLOADER_PKGS grub2関連のbootloaderを元に戻す
# shim-x86をCentOSの物に戻す
# sos-releasesをCentOSの物に戻す

# Copyright 2021 Cybertrust Japan Co., Ltd.
#
#Permission is hereby granted, free of charge, to any person obtaining a copy
#of this software and associated documentation files (the "Software"), to deal
#in the Software without restriction, including without limitation the rights
#to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#copies of the Software, and to permit persons to whom the Software is
#furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all
#copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#SOFTWARE.

LANG=C

VERSION='1.0.1'
ML_BASEOS_REPO_FILE='/etc/yum.repos.d/MIRACLE-LINUX-BaseOS.repo'
ML_APPSTREAM_REPO_FILE='/etc/yum.repos.d/MIRACLE-LINUX-AppStream.repo'
ML_BASEOS_MEDIA_REPO_FILE='/etc/yum.repos.d/MIRACLE-LINUX-Media-BaseOS.repo'
ML_APPSTREAM_MEDIA_REPO_FILE='/etc/yum.repos.d/MIRACLE-LINUX-Media-AppStream.repo'

# BRAND PKGS means trademark included package generally.
BRAND_PKGS=("centos-backgrounds" "centos-logos" "centos-indexhtml" \
            "centos-logos-ipa" "centos-logos-httpd")
ML_BRAND_PKGS=("miraclelinux-backgrounds" "miraclelinux-logos" "miraclelinux-indexhtml" \
            "miraclelinux-logos-ipa" "miraclelinux-logos-httpd")
# Mainly grub2
BOOTLOADER_PKGS=("grub2-common" "grub2-efi-ia32" "grub2-efi-ia32-cdboot" \
            "grub2-efi-x64-modules" "grub2-pc" "grub2-tools" "grub2-tools-efi" \
            "grub2-tools-extra" "grub2-tools-minimal" "grub2-pc-modules")
GRUB_VERSION="2.02-99.el8.ML.2"
SHIM_VERSION="15.4-2.ML.2"
SOSREPORT_VERSION="4.0-11.el8.ML.1"
ML_RELEASE_VERSION="8.4-0.1.el8.ML.3"
RH_RELEASE_VERSION="8.4-0.1.el8.ML.1"
# These packages should uninstall for dependency(only exist in centos)
REMOVE_PKGS=("libreport-plugin-rhtsupport" "libreport-rhel" \
            "libreport-rhel-anaconda-bugzilla" "libreport-rhel-bugzilla" \
            "subscription-manager" "subscription-manager-rhsm-certificates" \
            "python3-subscription-manager-rhsm" "dnf-plugin-subscription-manager" \
            "python3-syspurpose")

show_usage() {
    echo 'Migrate script to MIRACLE LINUX from CentOS'
    echo 'Usage: migrate2ml.sh [OPTION]...'
    echo '  -h, --help                  :show this message and exit'
    echo '  --media-repo                :Change repository path to /media/cdrom'
    echo '  Mode)'
    echo '  --core                      :Replace some brand packages, bootloaders, and others'
    echo '  --minimal                   :Minimal migration(Only change repository to ML)'
    echo '  --reconfigure-bootloader    :Reconfigure bootloader'
}

show_version() {
    message "migrate2ml.sh VERSION: $VERSION"
}

MIGRATE_MINIMAL=no
MIGRATE_CORE=no
RECONFIGURE_BOOTLOADER=no
MEDIA_REPO=no

parse_option() {
    local opt
    for opt in "$@"; do
        case ${opt} in
        -h | --help)
            show_usage
            exit 0
            ;;
        --minimal)
            MIGRATE_MINIMAL=yes
            ;;
        --core)
            MIGRATE_CORE=yes
            ;;
        --reconfigure-bootloader)
            RECONFIGURE_BOOTLOADER=yes
            MIGRATE_MINIMAL=no
            ;;
        --media-repo)
            MEDIA_REPO=yes
            ;;
        -v | --version)
            echo "${VERSION}"
            exit 0
            ;;
        *)
            echo "Error: unknown option ${opt}" >&2
            exit 2
            ;;
        esac
    done
    # Exclusive options checks
    if [ "$MIGRATE_CORE" = 'yes' -a "$RECONFIGURE_MINIMAL" = 'yes' ]; then
        echo "Error: specified options are exclusive." >&2
        exit 2
    fi
    if [ "$MIGRATE_MINIMAL" = 'yes' -a "$RECONFIGURE_BOOTLOADER" = 'yes' ]; then
        echo "Error: specified options are exclusive." >&2
        exit 2
    fi
    if [ "$MIGRATE_MINIMAL" = 'no' -a "$MIGRATE_CORE" = 'no' -a "$RECONFIGURE_BOOTLOADER" = 'no' ]; then
        echo "Error: please select one of the mode options." >&2
        exit 2
    fi
}

set_logging() {
    LOG_FILE="/var/log/migration2ml-$(date '+%Y%m%d%H%M%S').log"
    touch $LOG_FILE
    exec > >(tee $LOG_FILE)
}

PROGRESS_RECORD_DIR="/etc/migrate2ml"
record_progress() {
    local progress=$1
    if [[ ! -d "${PROGRESS_RECORD_DIR}" ]]; then
        mkdir -p "${PROGRESS_RECORD_DIR}"
    fi
    touch "${PROGRESS_RECORD_DIR}/${progress}"
}

check_record() {
    local progress=$1
    if [[ ! -f "${PROGRESS_RECORD_DIR}/${progress}" ]]; then
        return 1
    fi
    return 0
}

BACKUP_RELEASE_FILE_DIR="/etc/migrate2ml/backup_release_file"
backup_release_file() {
    if [[ ! -d "${BACKUP_RELEASE_FILE_DIR}" ]]; then
        mkdir -p "${BACKUP_RELEASE_FILE_DIR}"
    fi
    cp /etc/*-release "$BACKUP_RELEASE_FILE_DIR/"
}

message() {
    echo "$*"
}

warning() {
    echo -e "\033[31m$*\033[m"
}

debug() {
    echo "[DEBUG:$(date '+%Y-%m-%d %H:%M:%S'): $1" >> $LOG_DEBUG_FILE
}

check_root_user() {
    if [[ $(id -u) -ne 0 ]]; then
        echo 'Must be run as root user.'
        exit 2
    fi
}

# /etc/os-releaseファイルでチェック。miracle or centos8.x86_64のみ
check_supported_os() {
    local ID=$(cat /etc/os-release | grep "^ID=" | cut -f 2 -d '=')
    local VERSION_ID=$(cat /etc/os-release | grep "^VERSION_ID=" | cut -f 2 -d '=')
    local ARCH=$(uname -m)
    if [ "$ID" != '"centos"' -a "$ID" != '"miraclelinux"' ]; then
        warning 'This script only support on CentOS or MIRACLE LINUX.'
        warning "ID: $ID"
        exit 2
    fi
    if [ -e "/etc/centos-release" ]; then
        message "centos-release: $(cat /etc/centos-release)"
    fi
    if [ "$VERSION_ID" != '"8"' ]; then
        warning 'This script only support on major version 8 of CentOS.'
        warning "VERSION_ID: $VERSION_ID"
        exit 2
    fi
    if [ "$ARCH" != 'x86_64' ]; then
        warning 'This script only support on x86_64.'
        exit 2
    fi
}

check_secureboot_disable() {
    if LC_ALL='C' mokutil --sb-state 2>/dev/null | grep -P '^SecureBoot\s+enabled' 1>/dev/null; then
        warning "This script will exit when SecureBoot is enabled."
        warning "Please disable SecureBoot on UEFI configuration."
        warning 'You can check "mokutil --sb-state" to ensure SecureBoot feature is enabled or not.'
        exit 1
    fi
}

check_ml_media_mount() {
    # Make sure MIRACLE LINUX ISO is mounted to "/media/cdrom"
    if findmnt --mountpoint /media/cdrom/ 1>/dev/null ; then
        if cat /media/cdrom/.discinfo  | grep "MIRACLE LINUX" 1> /dev/null; then
            message "Checked MIRACLE LINUX media is mounted."
            return
        fi
    fi
    warning 'MIRACLE LINUX media is not mounted to "/media/cdrom" path.'
    warning "Please mount MIRACLE LINUX media to this path."
    warning "Exit."
    exit 2
}

minimal_migrate() {
    disable_centos_repo
    if [ "$MEDIA_REPO" = 'yes' ]; then
        put_ml_media_repo
    else
        put_ml_repo
    fi
    put_gpg_pubkey
    exclude_aware_packages
}

core_migrate() {
    message "Start download pkgs"
    migrate_release_pkg
    replace_brand_packages
    remove_specific_pkg
    upgrade_grub2_pkg # grub2当bootloaderパッケージ
    upgrade_shim_pkg # bootloader関連
    upgrade_sos_report_pkg
}

configure_bootloaders() {
    setup_grub2_config
    register_efi_boot_record
}

# 引数によりmain処理の分岐
migrate() {
    # Disable some signals during migration by trap
    trap "" SIGINT SIGTERM
    if [ "$MIGRATE_MINIMAL" = 'yes' ]; then
        minimal_migrate
        message "Minimal migration is completed!"
    elif [ "$MIGRATE_CORE" = 'yes' ]; then
        minimal_migrate
        core_migrate
        configure_bootloaders
        message "Core package migration is completed!"
    elif [ "$RECONFIGURE_BOOTLOADER" =  'yes' ]; then
        # When --reconfigure-bootloader is specified, pass other migration
        configure_bootloaders
        message "Reconfigured bootloaders."
    fi
    trap SIGINT SIGTERM
}

# ブランドパッケージの入れ替え
replace_brand_packages() {
    message "Replace brand pkgs."
    for i in "${!BRAND_PKGS[@]}"; do
        if ! rpm -q "${BRAND_PKGS[i]}" &> /dev/null; then
            unset "BRAND_PKGS[i]"
            unset "ML_BRAND_PKGS[i]"
        fi
    done
    if [[ "${#BRAND_PKGS[@]}" -ne 0 ]]; then
        # Pre-download ML BRAND PKGS
        dnf --disablerepo=* --enablerepo=ML8-* --downloadonly install -y "${ML_BRAND_PKGS[@]}"
        if [ $? -ne 0 ]; then
            warning "Failed to download ML brand pkgs"
            exit 2
        fi
        rpm -e --nodeps --allmatches "${BRAND_PKGS[@]}"
        if [ $? -eq 0 ]; then
            message "Uninstalled:" "${BRAND_PKGS[@]}"
        fi
        # Install coressponding packages
        dnf --disablerepo=* --enablerepo=ML8-* install -y "${ML_BRAND_PKGS[@]}"
        message "Replaced brand pkgs to ML."
    fi
}

replace_os_release() {
    if check_record "replace_os_release" ; then
        message "miraclelinux-release is already installed."
        return
    fi
    backup_release_file
    # Pre-download miraclelinux-release
    # miracle-linuxのリリースファイルをダウンロード(checkの為)
    dnf --releasever 8 --disablerepo=* --enablerepo=ML8-* --downloadonly install -y miraclelinux-release-${ML_RELEASE_VERSION} redhat-release-${RH_RELEASE_VERSION}
    if [ $? -ne 0 ]; then
        warning "Failed to download miraclelinux-release"
        exit 2
    fi
    
    # centos-release, centos-linux-releaseを削除
    # Uninstall centos's release pkg
    if rpm -q "centos-release" &> /dev/null; then
        rpm -e --nodeps --allmatches "centos-release"
    fi
    if rpm -q "centos-linux-release" &> /dev/null; then
        rpm -e --nodeps --allmatches "centos-linux-release"
    fi
    # Install miraclelinux-release
    # 
    # miracle-linuxのリリースファイルをダウンロード(実行)
    dnf --releasever 8 --disablerepo=* --enablerepo=ML8-* --setopt=module_platform_id=platform:el8 install -y miraclelinux-release-${ML_RELEASE_VERSION} redhat-release-${RH_RELEASE_VERSION}
    if [ $? -eq 0 -a -e "/etc/miraclelinux-release" ]; then
        message "Replaced os-release pkgs."
    else
        warning "Failed to install miraclelinux-release."
        warning "Exit."
        exit 2
    fi
    record_progress "replace_os_release"
}

upgrade_grub2_pkg() {
    if check_record "upgrade_grub2_pkg" ; then
        message "grub2 packages already upgraded."
        return
    fi
    for i in "${!BOOTLOADER_PKGS[@]}"; do
        if ! rpm -q "${BOOTLOADER_PKGS[i]}" &> /dev/null; then
            unset "BOOTLOADER_PKGS[i]"
        fi
    done
    # Install specified version
    for i in "${!BOOTLOADER_PKGS[@]}"; do
        BOOTLOADER_PKGS[i]="${BOOTLOADER_PKGS[i]}-${GRUB_VERSION}"
    done
    dnf --disablerepo=* --enablerepo=ML8-* install -y "${BOOTLOADER_PKGS[@]}"
    if [ $? -eq 0 ]; then
        message "Upgraded of grub2 packages."
    else
        warning "Failed to upgrade grub2 packages"
        warning "Exit."
        exit 2
    fi
    record_progress "upgrade_grub2_pkg"
}

upgrade_shim_pkg() {
    if check_record "upgrade_shim_pkg" ; then
        message "Already upgraded shim."
        return
    fi
    # Only upgrade when shim-x64 was installed,
    if rpm -q "shim-x64" &> /dev/null; then
        dnf --disablerepo=* --enablerepo=ML8-* install -y "shim-x64-${SHIM_VERSION}"
        if [ $? -eq 0 ]; then
            message "Upgraded of shim-x64 package."
        else
            warning "Failed to upgrade shim-x64 package"
            exit 2
        fi
    fi
    record_progress "upgrade_shim_pkg"
}

# sosreport RedHatの診断情報収集ツールの置き換え
upgrade_sos_report_pkg() {
    if check_record "upgrade_sos_report_pkg" ; then
        message "Already upgraded sos."
        return
    fi
    # Only upgrade when sosreport was installed,
    if rpm -q "sos" &> /dev/null; then
        dnf --disablerepo=* --enablerepo=ML8-* install -y "sos-${SOSREPORT_VERSION}"
        if [ $? -eq 0 ]; then
            message "Upgraded of sos package."
        else
            warning "Failed to upgrade sos package"
            exit 2
        fi
    fi
    record_progress "upgrade_sos_report_pkg"
}

# CentOS独自パッケージの削除
remove_specific_pkg() {
    if check_record "remove_specific_pkg" ; then
        message "Skip specific package removing."
        return
    fi
    for i in "${!REMOVE_PKGS[@]}"; do
        if ! rpm -q "${REMOVE_PKGS[i]}" &> /dev/null; then
            unset "REMOVE_PKGS[i]"
        fi
    done
    if [[ "${#REMOVE_PKGS[@]}" -ne 0 ]]; then
        rpm -e --nodeps --allmatches "${REMOVE_PKGS[@]}"
        message "Uninstalled specific packages."
    fi
    record_progress "remove_specific_pkg"
}

migrate_release_pkg() {
    replace_os_release
}

# CentOS-*.repoをdiasbleに変更
disable_centos_repo() {
    for repofile in /etc/yum.repos.d/CentOS-*.repo
    do
       sed 's/^enabled=1$/enabled=0/' -i "$repofile"
    done
    message "Disabled CentOS repo files."
}

put_ml_repo() {
    cat <<EOF > $ML_BASEOS_REPO_FILE
[ML8-BaseOS]
name=MIRACLE LINUX $releasever - BaseOS
mirrorlist=https://repo.dist.miraclelinux.net/miraclelinux/mirrorlist/8/x86_64/baseos
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-ML
EOF
    cat <<EOF > $ML_APPSTREAM_REPO_FILE
[ML8-AppStream]
name=MIRACLE LINUX $releasever - AppStream
mirrorlist=https://repo.dist.miraclelinux.net/miraclelinux/mirrorlist/8/x86_64/appstream
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-ML
EOF
    message "Copied MIRACLE LINUX repo files."
}

put_ml_media_repo() {
    cat <<EOF > $ML_BASEOS_MEDIA_REPO_FILE
[ML8-media-BaseOS]
name=MIRACLE LINUX $releasever Media - BaseOS
baseurl=file:///media/cdrom/BaseOS
gpgcheck=1
enabled=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-ML
EOF
    cat <<EOF > $ML_APPSTREAM_MEDIA_REPO_FILE
[ML8-media-AppStream]
name=MIRACLE LINUX $releasever Media - AppStream
baseurl=file:///media/cdrom/AppStream
gpgcheck=1
enabled=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-ML
EOF
    message "Copied MIRACLE LINUX Media repo files."
}

put_gpg_pubkey() {
    cat <<EOF > /etc/pki/rpm-gpg/RPM-GPG-KEY-ML
-----BEGIN PGP PUBLIC KEY BLOCK-----

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
DFjrPpRKz0Y1
=3y4n
-----END PGP PUBLIC KEY BLOCK-----
EOF
    message "Clean dnf cache."
    dnf clean all
    # Register ML GPG public key to rpm
    rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-ML
    message "Imported MIRACLE LINUX GPG key."
}


exclude_aware_packages() {
    for repofile in /etc/yum.repos.d/MIRACLE-LINUX-*.repo
    do
        echo -n 'exclude=axtsn-client* subscription-manager* python3-syspurpose libreport-rhel* libreport-plugin-rhtsupport insights-client ' >> "$repofile"
        # On minimal migrate, bootloader packages should be exclude.
        if [ "$MIGRATE_MINIMAL" = 'yes' ]; then
            echo 'shim* grub2*' >> "$repofile"
        fi
    done
}

setup_grub2_config() {
    # Check UEFI ennvironment
    if [ -d /sys/firmware/efi ]; then
        # NOTE: We use asianux name to uefi vendor dir for historical reasons.
        mkdir -p /boot/efi/EFI/asianux
        grub2-mkconfig -o /boot/efi/EFI/asianux/grub.cfg
        if [ $? -ne 0 ]; then
            warning "Failed to generate grub2 config."
            warning "# grub2-mkconfig -o /boot/efi/EFI/asianux/grub.cfg"
            return
        fi
        message "Success to generate grub.cfg for ML."
    else
        message "Skipped grub2-mkconfig."
    fi
}

register_efi_boot_record() {
    # Check UEFI ennvironment
    if [ -d /sys/firmware/efi ]; then
        # Skip if already registered by this script.
        if check_record "register_efi_boot_record"; then
            message "Skipped registering EFI Boot Record."
            return
        fi
        # Warning duplicate entry
        if efibootmgr 2>/dev/null | grep "MIRACLE LINUX" > /dev/null ; then
            warning "Notice: EFI entry for MIRACLE LINUX is already registered for some reason."
        fi
        local device_name=$(findmnt -n -o SOURCE /boot/efi)
        local disk_name=$(lsblk -inspT -o NAME ${device_name} | tail -1 | cut -b3-)
        local part_number=$(echo ${device_name#$disk_name} | sed 's|[^0-9]||g')

        message "Setup of efibootmgr."
        # NOTE: We use asianux name to uefi vendor dir, same reason as setup_grub2_config
        efibootmgr -c -L "MIRACLE LINUX" -l "\EFI\asianux\shimx64.efi" -d "${disk_name}" -p "${part_number}"
        if [ $? -ne 0 ]; then
            warning "Failed to register EFI Boot Record."
            warning "Maybe you can't boot after shutdown."
            return
        fi
        record_progress "register_efi_boot_record"
    else
        message "Not UEFI environment, skipped registering EFI Boot Record."
    fi
}

main() {
    parse_option "$@"
    check_root_user
    set_logging
    show_version
    check_supported_os
    check_secureboot_disable
    if [ "$MEDIA_REPO" = 'yes' ]; then
        check_ml_media_mount
    fi
    migrate
}

main "$@"
