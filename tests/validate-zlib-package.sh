#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
	printf 'usage: %s <zlib-*.pkg.tar.*> [--pacman]\n' "$0" >&2
	exit 2
fi

package=$1
run_pacman=${2:-}
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
package_dir=$(cd "$(dirname "$package")" && pwd -P)
package_name=$(basename "$package")
pacman_image='archlinux@sha256:c1829f370be8434135f43fb3acaef1256780804ac3b2d2eec90dfb1232e1ffdf'

if [[ ! -f $package ]]; then
	printf 'package not found: %s\n' "$package" >&2
	exit 1
fi

case $package_name in
	zlib-*-vita.pkg.tar.*) ;;
	*)
		printf 'unexpected package name: %s\n' "$package_name" >&2
		exit 1
		;;
esac

archive_entries=$(bsdtar -tf "$package")
for metadata in .PKGINFO .BUILDINFO .MTREE; do
	grep -qx "$metadata" <<< "$archive_entries"
done

if grep -Ev '^(\.PKGINFO|\.BUILDINFO|\.MTREE|arm-vita-eabi(/.*)?)$' \
		<<< "$archive_entries"; then
	printf 'package contains paths outside the VitaSDK root\n' >&2
	exit 1
fi

pkginfo=$(bsdtar -xOf "$package" .PKGINFO)
grep -qx 'pkgname = zlib' <<< "$pkginfo"
grep -qx 'pkgbase = zlib' <<< "$pkginfo"
grep -qx 'xdata = pkgtype=pkg' <<< "$pkginfo"
grep -qx 'arch = vita' <<< "$pkginfo"

buildinfo=$(bsdtar -xOf "$package" .BUILDINFO)
grep -qx 'format = 2' <<< "$buildinfo"
grep -qx 'pkgname = zlib' <<< "$buildinfo"
grep -qx 'pkgarch = vita' <<< "$buildinfo"

bsdtar -xOf "$package" .MTREE | gzip -t
grep -qx 'arm-vita-eabi/lib/libz.a' <<< "$archive_entries"
grep -qx 'arm-vita-eabi/include/zlib.h' <<< "$archive_entries"

if [[ -z $run_pacman ]]; then
	exit 0
fi
if [[ $run_pacman != --pacman ]]; then
	printf 'unknown option: %s\n' "$run_pacman" >&2
	exit 2
fi

docker run --rm \
	--platform linux/amd64 \
	--mount "type=bind,source=$package_dir,target=/input,readonly" \
	--mount "type=bind,source=$script_dir/pacman.conf,target=/etc/pacman-vitasdk.conf,readonly" \
	--env "PACKAGE_NAME=$package_name" \
	"$pacman_image" \
	bash -euc '
		pacman --version
		install -d /repo /sdk/var/lib/pacman /sdk/var/cache/pacman/pkg
		cp "/input/$PACKAGE_NAME" /repo/
		repo-add /repo/vitasdk-test.db.tar.gz "/repo/$PACKAGE_NAME"
		pacman --config /etc/pacman-vitasdk.conf --sync --refresh --noconfirm
		install_output=$(pacman --config /etc/pacman-vitasdk.conf --sync --noconfirm zlib 2>&1)
		printf "%s\n" "$install_output"
		if grep -q "^warning:" <<< "$install_output"; then
			exit 1
		fi
		pacman --config /etc/pacman-vitasdk.conf --query zlib
		test -f /sdk/arm-vita-eabi/lib/libz.a
		test -f /sdk/arm-vita-eabi/include/zlib.h
		pacman --config /etc/pacman-vitasdk.conf --remove --noconfirm zlib
		test ! -e /sdk/arm-vita-eabi/lib/libz.a
		test ! -e /sdk/arm-vita-eabi/include/zlib.h
	'
