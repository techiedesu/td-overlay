# Copyright 1999-2021 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit qmake-utils xdg

DESCRIPTION="A program enabling web-installation of items via OpenCollaborationServices"
HOMEPAGE="https://opendesktop.org/p/1136805"
SRC_URI="https://www.opencode.net/akiraohgaki/ocs-url"
LICENSE="GPL-3+"
# KEYWORDS="~amd64"

# if [[ ${PV} == 9999 ]]; then
inherit git-r3
EGIT_REPO_URI="https://www.opencode.net/akiraohgaki/ocs-url.git"
# else # TODO: fix non-9999 version
# 	SRC_URI="https://www.opencode.net/akiraohgaki/${PN}/-/archive/release-${PV}/${PN}-release-${PV}.tar.bz2"
# 	S="${WORKDIR}/${PN}-release-${PV}"
# fi

SLOT="0"
KEYWORDS=""

DEPEND="
	>=dev-qt/qtcore-5.2.0:5
	>=dev-qt/qtdeclarative-5.2.0:5
	>=dev-qt/qtquickcontrols-5.2.0:5
	>=dev-qt/qtsvg-5.2.0:5
"
RDEPEND="${DEPEND}"

src_unpack() {
	git-r3_src_unpack

	unset EGIT_BRANCH EGIT_COMMIT
	EGIT_REPO_URI=https://github.com/akiraohgaki/qtil.git
	EGIT_CHECKOUT_DIR="${S}/lib/qtil"
	git-r3_src_unpack
}

src_prepare(){
	./scripts/prepare || die
	default_src_prepare
}

src_configure(){
	eqmake5 PREFIX="/usr"
}

src_install(){
	INSTALL_ROOT="${D}" default_src_install
}

pkg_postinst(){
	xdg_pkg_postinst
	elog "Thanks for installing ocs-url."
	elog "You can install packages from any page from"
	elog "https://www.opendesktop.org or related ones."
	elog "Just click on \"Install\", and then open the ocs://"
	elog "url provided by every package."
}
