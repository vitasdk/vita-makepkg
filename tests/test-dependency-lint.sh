#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/vita-makepkg-lint.XXXXXXXX")
sdk_root="$temporary_root/sdk"
work_root="$temporary_root/work"

cleanup() {
	rm -rf -- "$temporary_root"
}
trap cleanup EXIT

mkdir -p "$sdk_root" "$work_root"

cat > "$temporary_root/makepkg.conf" <<'EOF'
PREFIX=/unused
CARCH=vita
CHOST=arm-vita-eabi
BUILDENV=(!distcc !color !ccache !check !sign)
OPTIONS=(!strip !docs !libtool !staticlibs !emptydirs !zipman !purge !debug)
INTEGRITY_CHECK=(sha256)
PKGEXT='.pkg.tar.xz'
SRCEXT='.src.tar.gz'
EOF

cat > "$work_root/VITABUILD" <<'EOF'
pkgname=malformed-dependency-fixture
pkgver=1
pkgrel=1
arch=('vita')
depends=('zlib libpng')

package() {
	:
}
EOF

if (
	cd "$work_root"
	VITASDK="$sdk_root" MAKEPKG_CONF="$temporary_root/makepkg.conf" \
		"$repository_root/vita-makepkg" --printsrcinfo
) >"$temporary_root/output.log" 2>&1; then
	printf 'malformed dependency entry was unexpectedly accepted\n' >&2
	exit 1
fi

grep -Fq "depends entries must name one package each: 'zlib libpng'" \
	"$temporary_root/output.log"

printf 'vita-makepkg dependency lint contract passed\n'
