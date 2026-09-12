# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop linux-info optfeature xdg

# Upstream switched to a bootstrapper model around 1.0.188x: the tarball no
# longer ships the Electron application (~100MB with chrome-sandbox, *.pak,
# locales/, resources/ and the bundled libs). It now contains a ~2MB launcher
# plus updater_bootstrap, which downloads the real app into
# ${XDG_CONFIG_HOME}/discordcanary on first run.
MY_TARBALL_DIR="DiscordCanary"

DESCRIPTION="All-in-one voice and text chat for gamers (canary channel)"
HOMEPAGE="https://discord.com"
SRC_URI="https://dl-canary.discordapp.net/apps/linux/${PV}/${PN}-${PV}.tar.gz"

LICENSE="all-rights-reserved"
SLOT="0"
KEYWORDS="amd64"
RESTRICT="bindist mirror strip test"
IUSE="appindicator +seccomp"

# The application itself is fetched at runtime by updater_bootstrap, but it is
# a stock Electron build and needs the same shared libraries as before.
RDEPEND="
	>=app-accessibility/at-spi2-core-2.46.0:2
	app-crypt/libsecret
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/nspr
	dev-libs/nss
	media-libs/alsa-lib
	media-libs/fontconfig
	media-libs/mesa[gbm(+)]
	net-print/cups
	sys-apps/dbus
	sys-apps/util-linux
	sys-libs/glibc
	x11-libs/cairo
	x11-libs/gdk-pixbuf:2
	x11-libs/gtk+:3
	x11-libs/libX11
	x11-libs/libXScrnSaver
	x11-libs/libXcomposite
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libXrandr
	x11-libs/libdrm
	x11-libs/libxcb
	x11-libs/libxkbcommon
	x11-libs/libxshmfence
	x11-libs/pango
	appindicator? ( dev-libs/libayatana-appindicator )
"

S="${WORKDIR}/${MY_TARBALL_DIR}"

DESTDIR="/opt/${PN}"

QA_PREBUILT="*"

CONFIG_CHECK="~USER_NS"

src_prepare() {
	default

	# Distro packaging handles all of this; the script also kills running
	# instances and deletes files under every /home/*, which we do not want.
	rm postinst.sh || die "failed to remove upstream post-install script"

	# Icon ships as discord.png but the .desktop refers to discord-canary.
	mv discord.png "${PN}.png" || die "failed to rename icon"

	if ! use seccomp; then
		sed -i \
			-e "s:^Exec=/usr/bin/${PN}:Exec=/usr/bin/${PN} --disable-seccomp-filter-sandbox:" \
			"${PN}.desktop" || die "failed to disable seccomp in .desktop"
	fi
}

src_install() {
	exeinto "${DESTDIR}"
	# The launcher probes /usr/share/${PN}/updater_bootstrap first, then
	# /opt/${PN}/updater_bootstrap, then its own directory. Keeping both
	# files together in /opt makes the second probe succeed.
	doexe "${PN}" updater_bootstrap

	dosym "${DESTDIR}/${PN}" "/usr/bin/${PN}"

	doicon -s 256 "${PN}.png"
	domenu "${PN}.desktop"
}

pkg_postinst() {
	xdg_pkg_postinst

	elog "Discord now ships only a bootstrapper. On first launch it downloads"
	elog "the actual client into \${XDG_CONFIG_HOME:-~/.config}/discordcanary."
	elog "That directory is not managed by portage and survives unmerge;"
	elog "remove it by hand if you want a clean uninstall."

	optfeature "graphical progress dialog during the initial download" x11-libs/gtk+ gnome-extra/zenity
	optfeature "sound support" media-video/pipewire media-sound/pulseaudio media-sound/apulse[sdk]
}
