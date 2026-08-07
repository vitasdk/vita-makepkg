#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
repository_root=$(cd "$script_dir/.." && pwd -P)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/vita-makepkg-transactions.XXXXXXXX")
package_dir="$temporary_root/packages"
pacman_image='archlinux@sha256:c1829f370be8434135f43fb3acaef1256780804ac3b2d2eec90dfb1232e1ffdf'

cleanup() {
	chmod -R u+rwX "$temporary_root" 2>/dev/null || true
	rm -rf -- "$temporary_root"
}
trap cleanup EXIT

mkdir -p "$package_dir"

for fixture in base-v1 base-v2 addon conflict consumer; do
	fixture_work="$temporary_root/$fixture"
	mkdir -p "$fixture_work/build"
	cp "$script_dir/fixtures/$fixture/VITABUILD" "$fixture_work/VITABUILD"
	(
		cd "$fixture_work"
		VITASDK=/opt/vitasdk \
		MAKEPKG_CONF="$repository_root/makepkg.conf.sample" \
		BUILDDIR="$fixture_work/build" \
		PKGDEST="$package_dir" \
		PACKAGER='VitaSDK Tests <vitasdk@users.noreply.github.com>' \
		SOURCE_DATE_EPOCH=1700000000 \
		"$repository_root/vita-makepkg" --force --nodeps
	)
done

docker run --rm \
	--platform linux/amd64 \
	--mount "type=bind,source=$package_dir,target=/input,readonly" \
	--mount "type=bind,source=$script_dir/pacman.conf,target=/etc/pacman-vitasdk.conf,readonly" \
	"$pacman_image" \
	bash -euc '
		export LC_ALL=C
		install -d /repo /sdk/var/lib/pacman /sdk/var/cache/pacman/pkg
		cp /input/*.pkg.tar.* /repo/

		base_v1=/repo/vitasdk-transaction-fixture-1.0-1-vita.pkg.tar.xz
		base_v2=/repo/vitasdk-transaction-fixture-2.0-1-vita.pkg.tar.xz
		addon=/repo/vitasdk-transaction-addon-1.0-1-vita.pkg.tar.xz
		conflict=/repo/vitasdk-transaction-conflict-1.0-1-vita.pkg.tar.xz
		consumer=/repo/vitasdk-transaction-consumer-1.0-1-vita.pkg.tar.xz
		config=/etc/pacman-vitasdk.conf
		fixture_dir=/sdk/arm-vita-eabi/share/vitasdk-transaction-test

		repo-add /repo/vitasdk-test.db.tar.gz "$base_v1" "$addon" "$consumer"
		pacman --config "$config" --sync --refresh --refresh --noconfirm
		pacman --config "$config" --sync --noconfirm vitasdk-transaction-fixture
		pacman --config "$config" --query vitasdk-transaction-fixture |
			grep -qx "vitasdk-transaction-fixture 1.0-1"
		grep -qx "1.0" "$fixture_dir/version.txt"

		if pacman --config "$config" --sync --noconfirm vitasdk-transaction-consumer; then
			printf "versioned dependency was incorrectly satisfied by 1.0\n" >&2
			exit 1
		fi
		test ! -e "$fixture_dir/consumer.txt"
		pacman --config "$config" --query vitasdk-transaction-fixture |
			grep -qx "vitasdk-transaction-fixture 1.0-1"

		cp "$base_v2" "$base_v2.verified"
		repo-add /repo/vitasdk-test.db.tar.gz "$base_v2"
		pacman --config "$config" --sync --refresh --refresh --noconfirm
		printf "corrupted-download\n" >> "$base_v2"
		if pacman --config "$config" --sync --noconfirm vitasdk-transaction-consumer; then
			printf "package with a mismatched repository hash was accepted\n" >&2
			exit 1
		fi
		pacman --config "$config" --query vitasdk-transaction-fixture |
			grep -qx "vitasdk-transaction-fixture 1.0-1"
		if pacman --config "$config" --query vitasdk-transaction-consumer; then
			printf "consumer was installed by a failed transaction\n" >&2
			exit 1
		fi
		cp "$base_v2.verified" "$base_v2"

		pacman --config "$config" --sync --noconfirm vitasdk-transaction-consumer
		pacman --config "$config" --query vitasdk-transaction-fixture |
			grep -qx "vitasdk-transaction-fixture 2.0-1"
		pacman --config "$config" --query vitasdk-transaction-consumer |
			grep -qx "vitasdk-transaction-consumer 1.0-1"
		grep -qx "2.0" "$fixture_dir/version.txt"
		grep -qx "upgraded" "$fixture_dir/upgrade-marker.txt"
		grep -qx "consumer" "$fixture_dir/consumer.txt"

		if pacman --config "$config" --upgrade --noconfirm "$conflict"; then
			printf "file-conflicting package was accepted\n" >&2
			exit 1
		fi
		grep -qx "2.0" "$fixture_dir/version.txt"
		pacman --config "$config" --query vitasdk-transaction-fixture |
			grep -qx "vitasdk-transaction-fixture 2.0-1"

		pacman --config "$config" --remove --noconfirm vitasdk-transaction-consumer
		touch /sdk/var/lib/pacman/db.lck
		if pacman --config "$config" --sync --noconfirm vitasdk-transaction-addon; then
			printf "transaction proceeded while the database lock existed\n" >&2
			exit 1
		fi
		if pacman --config "$config" --query vitasdk-transaction-addon; then
			printf "addon was installed while the database was locked\n" >&2
			exit 1
		fi
		rm -f /sdk/var/lib/pacman/db.lck
		pacman --config "$config" --sync --noconfirm vitasdk-transaction-addon
		grep -qx "addon" "$fixture_dir/addon.txt"
		pacman --config "$config" --remove --noconfirm vitasdk-transaction-fixture
		test ! -e "$fixture_dir/version.txt"
		test ! -e "$fixture_dir/upgrade-marker.txt"
		grep -qx "addon" "$fixture_dir/addon.txt"
		pacman --config "$config" --remove --noconfirm vitasdk-transaction-addon
		test ! -e "$fixture_dir"
	'
