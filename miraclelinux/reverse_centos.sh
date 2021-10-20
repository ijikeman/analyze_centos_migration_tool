# disabled MIRACLE-LINUX-*.repo
ls /etc/yum.repos.d/MIRACLE-LINUX-*.repo|xargs sed -i 's/enabled=1/enabled=0/s'
# enabled CentOS-*.repo
ls /etc/yum.repos.d/CentOS-*.repo|xargs sed -i 's/enabled=0/enabled=1/g'

# migrate_release_pkg
dnf --releasever 8 --disablerepo=* --enablerepo=baseos,appstream,extras --downloadonly install -y centos-linux-release
rpm -e --nodeps --allmatches redhat-release miraclelinux-release
dnf --releasever 8 --disablerepo=* --enablerepo=baseos,appstream,extras install -y centos-release # 8.4に変わるので8.1のcentos-linux-release.rpmが必要

# もともと入っていたものを精査する必要あり
dnf --releasever 8 --disablerepo=* --enablerepo=baseos,appstream,extras install -y "centos-backgrounds" "centos-logos" "centos-indexhtml" "centos-logos-ipa" "centos-logos-httpd"

# もともと入っていたものを精査する必要あり
dnf --releasever 8 --disablerepo=* --enablerepo=baseos,appstream,extras install -y "libreport-plugin-rhtsupport" "libreport-rhel"             "libreport-rhel-anaconda-bugzilla" "libreport-rhel-bugzilla"             "subscription-manager" "subscription-manager-rhsm-certificates"

#
dnf --releasever 8 --disablerepo=* --enablerepo=baseos,appstream,extras --downloadonly install grub2
