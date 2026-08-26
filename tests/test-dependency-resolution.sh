#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/vita-makepkg-deps.XXXXXXXX")
sdk_root="$temporary_root/sdk"
work_root="$temporary_root/work"
package_root="$temporary_root/packages"
pacman_log="$temporary_root/pacman.log"
pacman_state="$temporary_root/dependencies-installed"

cleanup() {
	chmod -R u+rwX "$temporary_root" 2>/dev/null || true
	rm -rf -- "$temporary_root"
}
trap cleanup EXIT

mkdir -p "$sdk_root/bin" "$sdk_root/etc" "$work_root/build" "$package_root"

cat > "$sdk_root/etc/pacman.conf" <<'EOF'
[options]
Architecture = vita
SigLevel = Never
EOF

cat > "$sdk_root/bin/pacman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${FAKE_PACMAN_LOG:?}"
: "${FAKE_PACMAN_STATE:?}"

printf '%q ' "$@" >> "$FAKE_PACMAN_LOG"
printf '\n' >> "$FAKE_PACMAN_LOG"

operation=
operation_index=0
index=0
for argument in "$@"; do
	case "$argument" in
		-T|-S|-Qq|-Qi|-U|-Rn)
			operation=$argument
			operation_index=$index
			break
			;;
	esac
	index=$((index + 1))
done

case "$operation" in
	-T)
		if [[ ! -e $FAKE_PACMAN_STATE ]]; then
			arguments=("$@")
			printf '%s\n' "${arguments[@]:operation_index+1}"
			exit 127
		fi
		;;
	-S)
		: > "$FAKE_PACMAN_STATE"
		;;
	-Qq)
		[[ -e $FAKE_PACMAN_STATE ]] && printf 'runtime\nbuilder\n'
		;;
	-Qi)
		cat <<'INFO'
Name            : runtime
Version         : 2.1-1
Architecture    : vita
INFO
		;;
	*)
		printf 'unexpected pacman operation\n' >&2
		exit 2
		;;
esac
EOF
chmod +x "$sdk_root/bin/pacman"

cat > "$temporary_root/makepkg.conf" <<EOF
PREFIX="$sdk_root/arm-vita-eabi"
CARCH=vita
CHOST=arm-vita-eabi
BUILDENV=(!distcc !color !ccache !check !sign)
OPTIONS=(!strip !docs !libtool !staticlibs !emptydirs !zipman !purge !debug)
INTEGRITY_CHECK=(sha256)
PKGEXT='.pkg.tar.xz'
SRCEXT='.src.tar.gz'
PACKAGER='VitaSDK Tests <vitasdk@users.noreply.github.com>'
EOF

cat > "$work_root/VITABUILD" <<'EOF'
pkgname=vitasdk-dependency-fixture
pkgver=1.0
pkgrel=1
pkgdesc='VitaSDK dependency integration fixture'
arch=('vita')
license=('MIT')
depends=('runtime>=2')
makedepends=('builder')

package() {
	install -Dm644 /dev/null \
		"$pkgdir$VITASDK/arm-vita-eabi/share/vitasdk-dependency-fixture"
}
EOF

run_makepkg() {
	(
		cd "$work_root"
		VITASDK="$sdk_root" \
		MAKEPKG_CONF="$temporary_root/makepkg.conf" \
		BUILDDIR="$work_root/build" \
		PKGDEST="$package_root" \
		SOURCE_DATE_EPOCH=1700000000 \
		FAKE_PACMAN_LOG="$pacman_log" \
		FAKE_PACMAN_STATE="$pacman_state" \
		"$repository_root/vita-makepkg" "$@"
	)
}

if run_makepkg --force --noconfirm >"$temporary_root/missing.log" 2>&1; then
	printf 'build unexpectedly accepted a missing dependency\n' >&2
	exit 1
fi
grep -Fq 'Could not resolve all dependencies.' "$temporary_root/missing.log"

build_fixture() {
	run_makepkg --force --syncdeps --noconfirm --noprogressbar
}

build_fixture

package="$package_root/vitasdk-dependency-fixture-1.0-1-vita.pkg.tar.xz"
test -f "$package"
first_hash=$(sha256sum "$package")
first_hash=${first_hash%% *}

sleep 1
build_fixture
second_hash=$(sha256sum "$package")
second_hash=${second_hash%% *}
test "$first_hash" = "$second_hash"

buildinfo=$(bsdtar -xOf "$package" .BUILDINFO)
grep -qx 'installed = runtime-2.1-1-vita' <<< "$buildinfo"
grep -Fq -- "--root $sdk_root" "$pacman_log"
grep -Fq -- "--dbpath $sdk_root/var/lib/pacman" "$pacman_log"
grep -Fq -- '--noconfirm --noprogressbar -T runtime\>=2' "$pacman_log"
grep -Fq -- '--noscriptlet --noconfirm --noprogressbar -S --asdeps runtime\>=2' "$pacman_log"
grep -Fq -- '--noconfirm --noprogressbar -T builder' "$pacman_log"
# --noscriptlet belongs to a transaction; pacman rejects it outright on a
# query. run_pacman stopped passing it there in 32f863c and these three
# lines went on asserting that it did, so nothing watched either half.
if grep -E -- ' (-T|-Q[a-z]*) ' "$pacman_log" | grep -Fq -- '--noscriptlet'; then
	printf 'a query was invoked with --noscriptlet\n' >&2
	exit 1
fi

printf 'vita-makepkg dependency and reproducibility contracts passed\n'
