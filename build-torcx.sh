#!/bin/bash
set -e -v -x

# Continue if package name and version is provided
if [ $# -ne 2 ]; then
  echo "ERROR: INCORRECT NUMBER OF ARFUMNETS"
  exit 1
fi

# package name
PKG=$1

# wireguard version
BUILD_TAG=$2

# constants
wireguard_src="https://github.com/WireGuard/WireGuard.git"

echo "Cloning wireguard version: ${BUILD_TAG}"
git clone "$wireguard_src" "/tmp/$PKG"
cd "/tmp/$PKG"
git checkout "${BUILD_TAG}"

# fix kernel path
sed -i -e 's#[ \t]*depmod.*##g' "/tmp/$PKG/src/Makefile"
# fix order of commands
perl -0pe 's/(set_config\n)(.*do\n\t\tadd_addr "\$i"\n\tdone\n)(\tset_mtu.*\n)/$1$3$2/' -i "/tmp/$PKG/src/tools/wg-quick/linux.bash"

# build modules
echo "Building from sources"

# set variables
KERNEL_BASEDIR=$(find /lib/modules/* -maxdepth 0)
export KERNELDIR="$KERNEL_BASEDIR/build"
# buils sources
make -C "/tmp/$PKG/src" -j$(nproc) all V=1
make -C "/tmp/$PKG/src" install module-install DESTDIR=/tmp/root V=1


# prepare packahe
echo "Making a package"
cp --parents "$KERNEL_BASEDIR/extra/wireguard.ko" /tmp/root
# Edit the service to be torcx-aware.
sed -i \
    -e '/^\[Unit]/aRequires=torcx.target\nAfter=torcx.target' \
    -e "/^\\[Service]/aEnvironmentFile=/run/metadata/torcx\\nExecStartPre=-/sbin/modprobe ip6_udp_tunnel\\nExecStartPre=-/sbin/modprobe udp_tunnel\\nExecStartPre=-/sbin/insmod \${TORCX_UNPACKDIR}/${PKG}/lib/modules/%v/extra/wireguard.ko" \
    -e 's,/usr/s\?bin/,${TORCX_BINDIR}/,g' \
    -e 's,^\([^ ]*=\)\(.{TORCX_BINDIR}\)/,\1/usr/bin/env PATH=\2:${PATH} \2/,' \
    /tmp/root/usr/lib/systemd/system/wg-quick@.service

# Prepare a torcx package manifest.
mkdir -p /tmp/root/.torcx
cat << 'EOF' > /tmp/root/.torcx/manifest.json
{
    "kind": "image-manifest-v0",
    "value": {
        "bin": [
            "/usr/bin/wg",
            "/usr/bin/wg-quick"
        ],
        "units": [
            "/usr/lib/systemd/system/wg-quick@.service"
        ]
    }
}
EOF

# Write the torcx package.
tar --force-local -C /tmp/root -czf "/host/${PKG}:${BUILD_TAG}.torcx.tgz" .
