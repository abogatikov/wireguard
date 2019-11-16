#!/bin/bash
set -e -v -x

# Continue if CoreOS group and version is provided
if [ $# -ne 2 ]; then
  echo "ERROR: INCORRECT NUMBER OF ARFUMNETS"
  exit 1
fi

# CoreOS group
GROUP=$1

# CoreOS version
VERSION=$2

# coreos variables
URL="https://$GROUP.release.core-os.net/amd64-usr/${VERSION}/coreos_developer_container.bin.bz2"
URL_IMAGE_SIG_KEY="https://coreos.com/security/image-signing-key/CoreOS_Image_Signing_Key.asc"
localimage="coreos_developer_container-${GROUP}_${VERSION}.bin"

# wireguard variables
PKG="wireguard"
wireguard_src="https://github.com/WireGuard/WireGuard.git"
wireguard="$PWD/${PKG}-${GROUP}-${VERSION}"

# prepare coreos build image
echo "Downloading CoreOS Developer Container: $URL"
curl -Ls "$URL" -o "$localimage.bz2"
curl -Ls "$URL.sig" -o "$localimage.bz2.sig"

echo "Downloading CoreOS image key: $URL_IMAGE_SIG_KEY"
curl -Ls "$URL_IMAGE_SIG_KEY" -o CoreOS_Image_Signing_Key.asc
gpg2 --import --keyid-format LONG CoreOS_Image_Signing_Key.asc

echo "Checking CoreOS Developer Container siganture"
gpg2 -q --verify "$localimage.bz2.sig" "$localimage.bz2"

echo "Unpacking CoreOS Developer Container"
bzip2 -df "$localimage.bz2"

# prepare wireguard sources
echo "Cloning $wireguard"
git clone "$wireguard_src" "$wireguard"

# fallback to previous versions until one is built successfully
for BUILD_TAG in $(git -C "$wireguard" tag --sort=-refname | head -15)
do
  # fallback to version
  git -C "$wireguard" checkout -q "${BUILD_TAG}"

  # set
  REFERENCE="CoreOS_${VERSION}"
  ITEM="WireGuard release ${BUILD_TAG} for CoreOS ${GROUP} ${VERSION}"

  echo "Trying to build ${ITEM} for build tag: ${BUILD_TAG}"
  if sudo systemd-nspawn -q --bind="$PWD:/host" --image="$localimage" /bin/bash /host/build-torcx.sh "${PKG}" "${BUILD_TAG}"
  then
    RELEASE_FILE="${PKG}.${REFERENCE}.torcx.tgz"
    sudo mv -f "${PKG}:${BUILD_TAG}.torcx.tgz" "${RELEASE_FILE}"
    echo "Success building: $ITEM"

    # publish an artifact if process run by GitHub Action
    if [ -v GITHUB_WORKSPACE ]
			then
				echo "Uploading to GitHub releases: $ITEM"
				ghr -b "CoreOS WireGuard automatic build." -replace "${GROUP}-${VERSION}" "${RELEASE_FILE}"
				echo "Done."

        # cleanup
				sudo rm -f "${RELEASE_FILE}"
		fi

    break
  else
    echo "Error building: ${ITEM}"
  fi
done

# cleanup
rm "$localimage"