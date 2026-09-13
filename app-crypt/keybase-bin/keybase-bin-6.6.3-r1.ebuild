# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Electron bundles the same language packs as Chromium.
CHROMIUM_LANGS="
	af am ar bg bn ca cs da de el en-GB en-US es es-419 et fa fi fil fr gu he hi
	hr hu id it ja kn ko lt lv ml mr ms nb nl pl pt-BR pt-PT ro ru sk sl sr sv
	sw ta te th tr uk ur vi zh-CN zh-TW
"

inherit chromium-2 desktop linux-info optfeature systemd unpacker xdg

MY_PN="${PN%-bin}"
# Upstream appends a build stamp to the release version in the deb pool.
MY_BUILD="20260603142455.f60f2ff97e"
MY_P="${MY_PN}_${PV}-${MY_BUILD}_amd64"

DESCRIPTION="Keybase client, KBFS and Electron GUI (upstream binary package)"
HOMEPAGE="https://keybase.io/"
# prerelease.keybase.io is a CloudFront alias for the same S3 bucket; the S3
# origin is listed first because the CDN is unreachable from some networks.
SRC_URI="
	amd64? (
		https://s3.amazonaws.com/prerelease.keybase.io/deb/pool/main/k/${MY_PN}/${MY_P}.deb -> ${P}.deb
		https://prerelease.keybase.io/deb/pool/main/k/${MY_PN}/${MY_P}.deb -> ${P}.deb
	)
"
S="${WORKDIR}"

LICENSE="Apache-2.0 BSD BSD-2 LGPL-3 MIT MPL-2.0"
SLOT="0"
KEYWORDS="-* ~amd64"
IUSE="+fuse +gui kbnm"
RESTRICT="bindist mirror strip test"

RDEPEND="
	app-crypt/gnupg
	sys-process/lsof
	sys-process/procps
	sys-process/psmisc
	fuse? ( sys-fs/fuse:0 )
	gui? (
		>=app-accessibility/at-spi2-core-2.46.0:2
		dev-libs/expat
		dev-libs/glib:2
		dev-libs/libayatana-appindicator
		dev-libs/nspr
		dev-libs/nss
		media-libs/alsa-lib
		media-libs/fontconfig
		media-libs/mesa[gbm(+)]
		net-print/cups
		sys-apps/dbus
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
		x11-libs/libXtst
		x11-libs/libdrm
		x11-libs/libxcb
		x11-libs/libxkbcommon
		x11-libs/libxshmfence
		x11-libs/pango
	)
	!app-crypt/kbfs
	!app-crypt/keybase
"

QA_PREBUILT="opt/keybase/* usr/bin/*"

# Needed by the bundled Chromium sandbox.
CONFIG_CHECK="~USER_NS"

pkg_setup() {
	use gui && chromium_suid_sandbox_check_kernel_config
}

src_unpack() {
	unpack_deb "${A}"
}

src_prepare() {
	default

	# Debian packaging leftovers that must not land on a Gentoo system.
	rm -r etc/apt usr/share/doc || die
	rm opt/keybase/post_install.sh || die

	if use gui; then
		pushd opt/keybase/locales > /dev/null || die
		chromium_remove_language_paks
		popd > /dev/null || die

		# Electron announces itself as "Keybase" (Wayland app_id, X11
		# WM_CLASS), so window managers look for a desktop entry of exactly
		# that name. Without it KWin falls back to the icon of whatever
		# launched the app. Ship a hidden alias next to the real entry.
		sed -i '/^Type=Application$/a StartupWMClass=Keybase' \
			usr/share/applications/keybase.desktop || die
		cp usr/share/applications/keybase.desktop \
			usr/share/applications/Keybase.desktop || die
		echo "NoDisplay=true" >> usr/share/applications/Keybase.desktop || die
	fi
}

src_install() {
	dobin usr/bin/keybase usr/bin/run_keybase
	systemd_douserunit usr/lib/systemd/user/keybase.service

	# run_keybase cats this unconditionally.
	insinto /opt/keybase
	doins opt/keybase/crypto_squirrel.txt

	if use fuse; then
		dobin usr/bin/kbfsfuse usr/bin/git-remote-keybase usr/bin/keybase-redirector
		systemd_douserunit usr/lib/systemd/user/kbfs.service
		systemd_douserunit usr/lib/systemd/user/keybase-redirector.service
	fi

	if use kbnm; then
		dobin usr/bin/kbnm
		insinto /etc/chromium/native-messaging-hosts
		doins etc/chromium/native-messaging-hosts/io.keybase.kbnm.json
		insinto /etc/opt/chrome/native-messaging-hosts
		doins etc/opt/chrome/native-messaging-hosts/io.keybase.kbnm.json
		insinto /usr/lib/mozilla/native-messaging-hosts
		doins usr/lib/mozilla/native-messaging-hosts/io.keybase.kbnm.json
	fi

	if use gui; then
		# keybase.gui.service and run_keybase both hardcode /opt/keybase/Keybase.
		exeinto /opt/keybase
		doexe opt/keybase/Keybase
		doexe opt/keybase/chrome-sandbox
		doexe opt/keybase/chrome_crashpad_handler
		doexe opt/keybase/libEGL.so
		doexe opt/keybase/libGLESv2.so
		doexe opt/keybase/libffmpeg.so
		doexe opt/keybase/libvk_swiftshader.so
		doexe opt/keybase/libvulkan.so.1

		insinto /opt/keybase
		doins opt/keybase/LICENSE
		doins opt/keybase/LICENSES.chromium.html
		doins opt/keybase/chrome_100_percent.pak
		doins opt/keybase/chrome_200_percent.pak
		doins opt/keybase/icudtl.dat
		doins opt/keybase/resources.pak
		doins opt/keybase/snapshot_blob.bin
		doins opt/keybase/v8_context_snapshot.bin
		doins opt/keybase/version
		doins opt/keybase/vk_swiftshader_icd.json
		insopts -m0755
		doins -r opt/keybase/locales opt/keybase/resources

		# The Chromium sandbox helper only works setuid, see
		# https://github.com/electron/electron/issues/17972
		fowners root:root /opt/keybase/chrome-sandbox
		fperms 4755 /opt/keybase/chrome-sandbox

		domenu usr/share/applications/keybase.desktop \
			usr/share/applications/Keybase.desktop
		insinto /usr/share/icons
		doins -r usr/share/icons/hicolor

		systemd_douserunit usr/lib/systemd/user/keybase.gui.service
	fi
}

pkg_postinst() {
	xdg_pkg_postinst

	elog "Start/restart everything: run_keybase"
	elog "Run the service only:     keybase service"
	elog "Log in:                   keybase login"

	if ! use gui; then
		elog ""
		elog "Built without USE=gui: export KEYBASE_NO_GUI=1 so that run_keybase"
		elog "does not try to launch the Electron app."
	fi

	if ! use fuse; then
		elog ""
		elog "Built without USE=fuse: export KEYBASE_NO_KBFS=1 so that run_keybase"
		elog "does not try to mount KBFS."
	else
		elog ""
		elog "The /keybase redirector mount needs a setuid helper. If you want it:"
		elog "  chown root:root /usr/bin/keybase-redirector"
		elog "  chmod 4755 /usr/bin/keybase-redirector"
		elog "Otherwise KBFS is still reachable under ~/.local/share/keybase."
	fi

	use gui && optfeature "sound support" media-video/pipewire media-sound/pulseaudio
}
