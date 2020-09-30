#!/usr/bin/env sh

set -e -u

export cwd="`realpath | sed 's|/scripts||g'`"
# Only run as superuser
if [ "$(id -u)" != "0" ]; then
  echo "This script must be run as root" 1>&2
  exit 1
fi

kernrel="`uname -r`"

case $kernrel in
  '12.2-STABLE'|'12.1-PRERELEASE'|'12.0-STABLE') ;;
  *)
    echo "Using wrong kernel release. Use TrueOS 18.12 or GhostBSD 19 to build iso."
    exit 1
    ;;
esac

desktop_list=`ls ${cwd}/packages | tr '\n' ' '`

helpFunction()
{
   echo "Usage: $0 -d desktop -r release type"
   echo -e "\t-h for help"
   echo -e "\t-d Desktop: ${desktop_list}"
   echo -e "\t-r Release: devel or release"
   exit 1 # Exit script after printing help
}

# Set mate and release to be default
export desktop="mate"
export release_type="release"

while getopts "d:r:" opt
do
   case "$opt" in
      'd') export desktop="$OPTARG" ;;
      'r') export release_type="$OPTARG" ;;
      'h') helpFunction ;;
      '?') helpFunction ;;
      *) helpFunction ;;
   esac
done


validate_desktop()
{
  if [ ! -f "${cwd}/packages/${desktop}" ] ; then
    echo "Invalid choice specified"
    echo "Possible choices are:"
    echo $desktop_list
    echo "Usage: ./build.sh mate"
    exit 1
  fi
}

validate_desktop

if [ "${desktop}" != "mate" ] ; then
  DESKTOP=$(echo ${desktop} | tr [a-z] [A-Z])
  community="-${DESKTOP}"
else
  community=""
fi

workdir="/usr/local"
livecd="${workdir}/ghostbsd-build"
base="${livecd}/base"
iso="${livecd}/iso"
software_packages="${livecd}/software_packages"
base_packages="${livecd}/base_packages"
release="${livecd}/release"
cdroot="${livecd}/cdroot"
liveuser="taubsd"

version=`date "+-%y.%m.%d"`
time_stamp=""
release_stamp=""

label="SoloBSD"
isopath="${iso}/${label}${version}${release_stamp}${time_stamp}${community}.iso"
if [ "$desktop" = "mate" ] ; then
  union_dirs=${union_dirs:-"bin boot compat dev etc include lib libdata libexec man media mnt net proc rescue root sbin share tests tmp usr/home usr/local/etc usr/local/share/mate-panel var www"}
elif [ "$desktop" = "kde" ] ; then
  union_dirs=${union_dirs:-"bin boot compat dev etc include lib libdata libexec man media mnt net proc rescue root sbin share tests tmp usr/home usr/local/etc usr/local/share/plasma var www"}
else
  union_dirs=${union_dirs:-"bin boot compat dev etc include lib libdata libexec man media mnt net proc rescue root sbin share tests tmp usr/home usr/local/etc var www"}
fi

workspace()
{
  if [ -d ${release}/var/cache/pkg ]; then
    if [ "$(ls -A ${release}/var/cache/pkg)" ]; then
      umount ${release}/var/cache/pkg
    fi
  fi

  if [ -d "${release}" ] ; then
    if [ -d ${release}/dev ]; then
      if [ "$(ls -A ${release}/dev)" ]; then
        umount ${release}/dev
      fi
    fi
    chflags -R noschg ${release}
    rm -rf ${release}
  fi

  if [ -d "${cdroot}" ] ; then
    chflags -R noschg ${cdroot}
    rm -rf ${cdroot}
  fi
  mkdir -p ${livecd} ${base} ${iso} ${software_packages} ${base_packages} ${release}
}

base()
{
  mkdir -p ${release}/etc
  cp /etc/resolv.conf ${release}/etc/resolv.conf
  mkdir -p ${release}/var/cache/pkg
  mount_nullfs ${base_packages} ${release}/var/cache/pkg
  pkg-static -r ${release} -R ${cwd}/pkg/ -C GhostBSD_PKG install -y -g os-generic-kernel os-generic-userland os-generic-userland-lib32 os-generic-userland-devtools

  rm ${release}/etc/resolv.conf
  umount ${release}/var/cache/pkg
  touch ${release}/etc/fstab
  mkdir ${release}/cdrom
}

packages_software()
{
  cp /etc/resolv.conf ${release}/etc/resolv.conf
  mkdir -p ${release}/var/cache/pkg
  mount_nullfs ${software_packages} ${release}/var/cache/pkg
  mount -t devfs devfs ${release}/dev
  cat ${cwd}/packages/${desktop} | xargs pkg -c ${release} install -y
  mkdir -p ${release}/compat/linux/proc
  rm ${release}/etc/resolv.conf
  umount ${release}/var/cache/pkg
}

rc()
{
  chroot ${release} sysrc -f /etc/rc.conf rc_parallel="NO"
  chroot ${release} sysrc -f /etc/rc.conf hostname='livecd'
  chroot ${release} sysrc -f /etc/rc.conf sendmail_enable="NONE"
  chroot ${release} sysrc -f /etc/rc.conf sendmail_submit_enable="NO"
  chroot ${release} sysrc -f /etc/rc.conf sendmail_outbound_enable="NO"
  chroot ${release} sysrc -f /etc/rc.conf sendmail_msp_queue_enable="NO"
  # DEVFS rules
  chroot ${release} sysrc -f /etc/rc.conf devfs_system_ruleset="devfsrules_common"
  # Load the following kernel modules
  chroot ${release} sysrc -f /etc/rc.conf kld_list="linux linux64 cuse"
  chroot ${release} rc-update add devfs default
  chroot ${release} rc-update add moused default
  chroot ${release} rc-update add dbus default
  chroot ${release} rc-update add webcamd default
  chroot ${release} rc-update add powerd default
  chroot ${release} rc-update add ipfw default
  chroot ${release} rc-update delete netmount default
  chroot ${release} rc-update add cupsd default
  chroot ${release} rc-update add avahi-daemon default
  chroot ${release} rc-update add avahi-dnsconfd default
  chroot ${release} rc-update add ntpd default
  chroot ${release} sysrc -f /etc/rc.conf ntpd_sync_on_start="YES"
  chroot ${release} sysrc -f /etc/rc.conf vboxservice_flags="--disable-timesync"
}

user()
{
  chroot ${release} pw useradd ${liveuser} \
  -c "TauBSD Live User" -d "/usr/home/${liveuser}"\
  -g wheel -G operator -m -s /usr/local/bin/mksh -k /usr/share/skel -w none
}

extra_config()
{
  . ${cwd}/extra/common-live-setting.sh
  . ${cwd}/extra/common-base-setting.sh
  . ${cwd}/extra/setuser.sh
  . ${cwd}/extra/dm.sh
  . ${cwd}/extra/finalize.sh
  . ${cwd}/extra/autologin.sh
  . ${cwd}/extra/gitpkg.sh
  . ${cwd}/extra/mate-live-settings.sh
  set_live_system
  # git_pc_sysinstall
  ## git_gbi is for development testing and gbi should be
  ## remove from the package list to avoid conflict
  # git_gbi
  setup_liveuser
  setup_base
  lightdm_setup
  if [ "${desktop}" == "mate" ] ; then
    mate_schemas
  fi
  setup_autologin
  final_setup
  echo "gop set 0" >> ${release}/boot/loader.rc.local
  # To fix lightdm crashing to be remove on the new base update.
  sed -i '' -e 's/memorylocked=128M/memorylocked=256M/g' ${release}/etc/login.conf
  chroot ${release} cap_mkdb /etc/login.conf
  mkdir -p ${release}/usr/local/share/ghostbsd
  echo "${desktop}" > ${release}/usr/local/share/ghostbsd/desktop
  echo "${liveuser}" > ${release}/usr/local/share/ghostbsd/liveuser
  # bypass automount for live
  mv ${release}/usr/local/etc/devd-openrc/automount_devd.conf ${release}/usr/local/etc/devd-openrc/automount_devd.conf.skip
}

xorg()
{
  if [ -n "${desktop}" ] ; then
    install -o root -g wheel -m 755 "${cwd}/xorg/bin/xconfig" "${release}/usr/local/bin/"
    # install -o root -g wheel -m 755 "${cwd}/xorg/rc.d/xconfig" "${release}/usr/local/etc/rc.d/"
    # if [ -f "${release}/sbin/openrc-run" ] ; then
    #   install -o root -g wheel -m 755 "${cwd}/xorg/init.d/xconfig" "${release}/usr/local/etc/init.d/"
    # fi
    if [ ! -d "${release}/usr/local/etc/X11/cardDetect/" ] ; then
      mkdir -p ${release}/usr/local/etc/X11/cardDetect
    fi
    install -o root -g wheel -m 755 "${cwd}/xorg/cardDetect/XF86Config.vesa" "${release}/usr/local/etc/X11/cardDetect/"
    install -o root -g wheel -m 755 "${cwd}/xorg/cardDetect/XF86Config.scfb" "${release}/usr/local/etc/X11/cardDetect/"
    install -o root -g wheel -m 755 "${cwd}/xorg/cardDetect/XF86Config.virtualbox" "${release}/usr/local/etc/X11/cardDetect/"
    install -o root -g wheel -m 755 "${cwd}/xorg/cardDetect/XF86Config.vmware" "${release}/usr/local/etc/X11/cardDetect/"
  fi
}

uzip()
{
  umount ${release}/dev
  install -o root -g wheel -m 755 -d "${cdroot}"
  mkdir "${cdroot}/data"
  # makefs -t ffs -m 4000m -f '10%' -b '10%' "${cdroot}/data/usr.ufs" "${release}/usr"
  makefs -t ffs -f '10%' -b '10%' "${cdroot}/data/usr.ufs" "${release}/usr"
  # makefs "${cdroot}/data/usr.ufs" "${release}/usr"
  mkuzip -o "${cdroot}/data/usr.uzip" "${cdroot}/data/usr.ufs"
  rm -r "${cdroot}/data/usr.ufs"
}

ramdisk()
{
  ramdisk_root="${cdroot}/data/ramdisk"
  mkdir -p "${ramdisk_root}"
  cd "${release}"
  tar -cf - rescue | tar -xf - -C "${ramdisk_root}"
  cd "${cwd}"
  install -o root -g wheel -m 755 "init.sh.in" "${ramdisk_root}/init.sh"
  sed "s/@VOLUME@/GHOSTBSD/" "init.sh.in" > "${ramdisk_root}/init.sh"
  mkdir "${ramdisk_root}/dev"
  mkdir "${ramdisk_root}/etc"
  touch "${ramdisk_root}/etc/fstab"
  cp ${release}/etc/login.conf ${ramdisk_root}/etc/login.conf
  makefs -b '10%' "${cdroot}/data/ramdisk.ufs" "${ramdisk_root}"
  gzip "${cdroot}/data/ramdisk.ufs"
  rm -rf "${ramdisk_root}"
}

mfs()
{
  for dir in ${union_dirs}; do
    echo ${dir} >> ${cdroot}/data/uniondirs
    cd ${release} && tar -cpzf ${cdroot}/data/mfs.tgz ${union_dirs}
  done
}

boot()
{
  cd "${release}"
  tar -cf - boot | tar -xf - -C "${cdroot}"
  cp COPYRIGHT ${cdroot}/COPYRIGHT
  cd "${cwd}"
  cp LICENSE ${cdroot}/LICENSE
  cp -R boot/ ${cdroot}/boot/
  mkdir ${cdroot}/etc
  cd ${cdroot}
  cd "${cwd}"
}

image()
{
  sh mkisoimages.sh -b $label $isopath ${cdroot}
  ls -lh $isopath
  cd ${iso}
  shafile=$(echo ${isopath} | cut -d / -f6).sha256
  torrent=$(echo ${isopath} | cut -d / -f6).torrent
  tracker1="http://tracker.openbittorrent.com:80/announce"
  tracker2="udp://tracker.opentrackr.org:1337"
  tracker3="udp://tracker.coppersurfer.tk:6969"
  echo "Creating sha256 \"${iso}/${shafile}\""
  sha256 `echo ${isopath} | cut -d / -f6` > ${iso}/${shafile}
  transmission-create -o ${iso}/${torrent} -t ${tracker1} -t ${tracker3} -t ${tracker3} ${isopath}
  chmod 644 ${iso}/${torrent}
  cd -
}

workspace
base
packages_software
user
rc
extra_config
uzip
ramdisk
mfs
boot
image
