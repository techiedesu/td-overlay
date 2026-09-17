# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop linux-info optfeature pax-utils unpacker xdg

DESCRIPTION="Official Claude desktop application: Chat, Cowork and Claude Code"
HOMEPAGE="https://claude.com/download"
# Anthropic ships Linux builds only as a .deb from their own apt repository.
# The payload is a stock Electron tree plus the Cowork VM assets, so nothing
# needs patching: we repack it and drop the Debian-specific parts.
SRC_URI="
	amd64? (
		https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop/claude-desktop_${PV}_amd64.deb
			-> ${P}-amd64.deb
	)
	arm64? (
		https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop/claude-desktop_${PV}_arm64.deb
			-> ${P}-arm64.deb
	)
"
S="${WORKDIR}"

LICENSE="all-rights-reserved"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"
IUSE="appindicator cowork gnome +pulseaudio"
# Cowork's VM launcher only knows x86_64 and aarch64 firmware paths, and the
# aarch64 firmware Gentoo ships is qcow2 while the app passes the path to QEMU
# as a raw pflash image, so the compat symlinks below can only be honest on
# amd64.
REQUIRED_USE="cowork? ( amd64 )"
RESTRICT="bindist mirror strip test"

# Everything here is either a NEEDED entry of the shipped ELFs or a library the
# Electron binary dlopens by soname (checked with objdump -p and strings).
RDEPEND="
	>=app-accessibility/at-spi2-core-2.46.0:2
	app-crypt/libsecret[crypt]
	app-misc/ca-certificates
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/nspr
	dev-libs/nss
	media-libs/alsa-lib
	media-libs/fontconfig
	media-libs/libglvnd
	media-libs/mesa[gbm(+)]
	net-print/cups
	sys-apps/dbus
	sys-apps/xdg-desktop-portal
	virtual/libudev
	x11-libs/cairo
	x11-libs/gdk-pixbuf:2
	x11-libs/gtk+:3
	x11-libs/libX11
	x11-libs/libXcomposite
	x11-libs/libXcursor
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libXrandr
	x11-libs/libdrm
	x11-libs/libnotify
	x11-libs/libxcb
	x11-libs/libxkbcommon
	x11-libs/pango
	x11-misc/xdg-utils
	appindicator? ( dev-libs/libayatana-appindicator )
	cowork? (
		app-emulation/qemu[qemu_softmmu_targets_x86_64]
		app-emulation/virtiofsd
		|| (
			sys-firmware/edk2-bin[qemu_softmmu_targets_x86_64(+)]
			sys-firmware/edk2
		)
	)
	gnome? ( dev-libs/gjs )
	pulseaudio? ( media-libs/libpulse )
"

DESTDIR="/opt/${PN}"

QA_PREBUILT="opt/${PN}/*"

# Chromium's namespace sandbox. chrome-sandbox is installed setuid as the
# fallback for kernels without unprivileged user namespaces.
CONFIG_CHECK="~USER_NS"

pkg_setup() {
	# Cowork talks to its guest over AF_VSOCK, so /dev/vhost-vsock has to exist.
	use cowork && CONFIG_CHECK+=" ~VHOST_VSOCK"

	linux-info_pkg_setup
}

src_prepare() {
	default

	# Debian packaging leftovers. The copyright file is reinstalled by dodoc,
	# the lintian overrides have no consumer here, and /usr/bin/claude-desktop
	# is a symlink into Debian's /usr/lib prefix that the launcher replaces.
	rm -r usr/share/lintian usr/bin || die

	# The D-Bus service is generated for that same prefix.
	sed -i -e "s:/usr/lib/${PN}:${DESTDIR}:" \
		usr/lib/${PN}/resources/gnome-search-provider/com.anthropic.Claude.SearchProvider.service || die
}

src_install() {
	# Installed from ${S} before the tree moves out from under them.
	if use gnome; then
		insinto /usr/share/gnome-shell/search-providers
		doins usr/lib/${PN}/resources/gnome-search-provider/com.anthropic.Claude.search-provider.ini
		insinto /usr/share/dbus-1/services
		doins usr/lib/${PN}/resources/gnome-search-provider/com.anthropic.Claude.SearchProvider.service
	fi

	# 553 MiB of Electron, a 28 MiB VM image and a 20 MiB MCP server: move the
	# tree into place instead of copying it through doins.
	dodir /opt
	mv usr/lib/${PN} "${ED}${DESTDIR}" || die

	# The Chromium sandbox helper only works setuid, see
	# https://github.com/electron/electron/issues/17972
	fowners root:root "${DESTDIR}/chrome-sandbox"
	fperms 4755 "${DESTDIR}/chrome-sandbox"

	# V8 writes and then executes its own JIT pages.
	pax-mark m "${ED}${DESTDIR}/${PN}"

	# Upstream's /usr/bin entry is a bare symlink to the Electron binary, which
	# leaves the app on Chromium's X11 default: under a Wayland compositor that
	# means XWayland, i.e. no native fractional scaling and no Wayland text
	# input. The hint is resolved by Chromium itself, so an X11 session still
	# gets X11.
	# <<- strips leading tabs, so the wrapper's own indentation is spaces.
	newbin - "${PN}" <<-EOF
		#!/bin/sh
		# Wrapper installed by app-misc/${PN}-${PVR}.
		# CLAUDE_DESKTOP_OZONE=0 restores upstream's XWayland behaviour;
		# CLAUDE_DESKTOP_FLAGS is appended to the command line.
		set -eu

		ozone=
		if [ "\${CLAUDE_DESKTOP_OZONE:-1}" = 1 ] && [ -n "\${WAYLAND_DISPLAY:-}" ]; then
		    ozone=--ozone-platform-hint=auto
		fi

		# Unquoted on purpose: both variables carry whole arguments.
		exec ${DESTDIR}/${PN} \${ozone} \${CLAUDE_DESKTOP_FLAGS:-} "\${@}"
	EOF

	if use cowork; then
		# The VM launcher probes /usr/share/OVMF/OVMF_CODE_4M.fd and then
		# /usr/share/OVMF/OVMF_CODE.fd, and derives the variable store by
		# replacing OVMF_CODE with OVMF_VARS. Gentoo keeps the raw 2 MiB images
		# in /usr/share/edk2/OvmfX64 (its 4 MiB build is qcow2, which QEMU
		# cannot use as a raw pflash drive), so only the 2 MiB pair is linked.
		dosym -r /usr/share/edk2/OvmfX64/OVMF_CODE.fd /usr/share/OVMF/OVMF_CODE.fd
		dosym -r /usr/share/edk2/OvmfX64/OVMF_VARS.fd /usr/share/OVMF/OVMF_VARS.fd
	fi

	domenu usr/share/applications/com.anthropic.Claude.desktop
	insinto /usr/share/icons
	doins -r usr/share/icons/hicolor
	dodoc usr/share/doc/${PN}/copyright
}

pkg_postinst() {
	xdg_pkg_postinst

	elog "Claude Desktop shares its login state with dev-util/claude-code"
	elog "through ~/.claude, and keeps its own configuration (including MCP"
	elog "servers) in ~/.config/Claude. Neither is removed on unmerge."

	if use cowork; then
		elog ""
		elog "Cowork runs its agent sandbox in a QEMU VM. It needs read/write"
		elog "access to /dev/kvm (be in the kvm group) and the vhost_vsock"
		elog "module loaded:"
		elog "  modprobe vhost_vsock"
	else
		elog ""
		elog "Cowork (the VM-backed agent sandbox) is disabled. Rebuild with"
		elog "USE=cowork to pull in QEMU, virtiofsd and the UEFI firmware."
	fi

	if ! use gnome; then
		elog ""
		elog "USE=gnome registers the GNOME Shell search provider that surfaces"
		elog "Claude Code sessions in the shell's search results."
	fi

	optfeature "storing credentials in a keyring" virtual/secret-service
	optfeature "moving files to the trash from file dialogs" gnome-base/gvfs kde-apps/kio-extras
	optfeature "reading pages aloud" app-accessibility/speech-dispatcher
	optfeature "uploading crash reports" net-misc/curl
}
