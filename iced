#!/bin/sh -e

trap 'rm -rf $TMPDIR || :' EXIT

TMPDIR=$(mktemp -d)
CACHE="$HOME/.cache/iced"

usage() {
	printf 'Usage: iced [-e VERSION] [-c] {install,remove,run,clear,wrap,ls,upgrade} PKG|TOOL\n'
	printf '    -e VERSION: use specific Alpine version (e.g. edge, 3.21, etc)'
	printf '    -c        : run the tool outside of the chroot, it may fail to find configs'
}

if ! command -v mkosi-sandbox >/dev/null; then
	printf 'mkosi-sandbox not found, please install mkosi!\n'
fi

VERSION=edge
TOOL_CHROOT=true

while getopts ":e:c" opt; do
	case $opt in
	e)
		VERSION=$OPTARG
		;;
	c)
		TOOL_CHROOT=false
		;;
	esac
	shift
done

mkdir -p "$CACHE/apk-cache"
ROOTFS="$CACHE/alpine-root-$VERSION"
mkdir -p "$ROOTFS"

install_apk() {
	local ver
	
	# Find the package version in the APKBUILD
	ver=$(curl --silent "https://dl-cdn.alpinelinux.org/alpine/edge/main/$(uname -m)/APKINDEX.tar.gz" | zcat | grep --binary-files=text -A 1 apk-tools-static | tail -n +2 | cut -d":" -f2)
	printf 'Installing apk.static version %s\n' "$ver"
	curl --silent -o "$TMPDIR/apk-tools-static-${ver}.tar.xz" "https://dl-cdn.alpinelinux.org/alpine/edge/main/$(uname -m)/apk-tools-static-${ver}.apk"
	tar -C $CACHE -xzf "$TMPDIR/apk-tools-static-${ver}.tar.xz" sbin/apk.static
}

if [ -f "$CACHE/sbin/apk.static" ]; then
	APK="$CACHE/sbin/apk.static"
fi
if [ -z "$APK" ]; then
	install_apk
	APK="$CACHE/sbin/apk.static"
fi

sbox() {
	local failed
	failed=""
	mkosi-sandbox $@ || failed=$?
	if [ -n "$failed" ]; then
		printf 'mkosi-sandbox failed: %d\n' $failed
	fi
}

run() {
	sbox \
		--bind / / \
		--become-root \
		--suppress-chown -- $@
}

run_chroot() {
	sbox \
		--bind "$ROOTFS" / \
		--dev /dev --proc /proc \
		--bind /home /home \
		--bind /run /run \
		--bind /etc/passwd /etc/passwd \
		--setenv PATH "/bin:/usr/bin:/sbin:/usr/sbin:$PATH" \
		-- $@
}

apk() {
	local cmd exe
	cmd="$1"
	shift
	exe="$APK $cmd \
	--repository http://dl-cdn.alpinelinux.org/alpine/edge/main \
	--repository http://dl-cdn.alpinelinux.org/alpine/edge/community \
	--repository http://dl-cdn.alpinelinux.org/alpine/edge/testing \
	--cache-dir "$CACHE/apk-cache" \
	--no-interactive \
	--progress-fd 3 \
	--root "$ROOTFS"
	$@" >/dev/null 3>&1
	# printf 'Running APK command: %s\n' "$exe"
	run $exe
}

apk_install() {
	local tool

	tool="$1"
	apk add "$tool" >/dev/null
	for bin in $(apk info -L "$tool" | grep -E "^(bin|sbin|usr/bin|usr/sbin)/"); do
		printf 'Installed binary /%s\n' $bin
	done
}

symlink_fixup() {
	# Fixup symlinks by making absolute ones relative
	realbin=$("$ROOTFS/$(readlink $1)")
	if [ "$(basename $realbin)" = "busybox" ]; then
		realbin="$realbin $(basename $1)"
	fi
	echo "$realbin"
}

if ! [ -f "$ROOTFS/etc/os-release" ]; then
	printf 'Setting up base rootfs...\n'
	apk add --initdb --allow-untrusted alpine-base
fi

iced_cmd=$1
if [ $# -gt 1 ]; then
	tool=$2
	shift 2
	tool_args=$@
fi

case $iced_cmd in
install|add)
	printf 'Installing %s\n' "$tool"
	apk_install $tool
	;;
remove|del)
	printf 'Uninstalling %s\n' "$tool"
	apk del "$tool"
	;;
run)
	if $TOOL_CHROOT; then
		bin="$tool"
		run_chroot $bin $tool_args
	else
		bin=$(find "$ROOTFS/bin" "$ROOTFS/sbin" "$ROOTFS/usr/bin" "$ROOTFS/usr/sbin" -not -type d -name "$tool" | head -n1)
		if [ -z "$bin" ]; then
			printf 'Tool %s not found! Is it installed?\n' "$tool"
			exit 1
		fi
		# bin=$(symlink_fixup $bin)
		LD_LIBRARY_PATH="$ROOTFS/lib:$ROOTFS/usr/lib" PATH="$ROOTFS/bin:$ROOTFS/usr/bin:$ROOTFS/sbin:$ROOTFS/usr/sbin" \
			"$ROOTFS/lib/ld-musl-$(uname -m).so.1" $bin $tool_args
	fi
	;;
wrap)
	if [ -f "$HOME/.local/bin/$tool" ]; then
		printf '%s already exists!\n' "$HOME/.local/bin/$tool"
		exit 1
	fi

	cat <<- EOF > "$HOME/.local/bin/$tool"
	#!/bin/sh

	exec $(realpath $0) run $tool \$@
	EOF
	chmod +x "$HOME/.local/bin/$tool"
	;;
search)
	apk search $tool
	;;
upgrade)
	apk upgrade -a
	;;
ls)
	progs="$(cat "$ROOTFS/etc/apk/world" | grep -v "alpine-base")"
	printf 'Installed tools:\n'
	printf ' * %s\n' $progs
	;;
clear)
	printf 'Destroying Alpine rootfs!\n'
	[[ -n "$CACHE" ]] && rm -rf "$ROOTFS"
	;;
esac

