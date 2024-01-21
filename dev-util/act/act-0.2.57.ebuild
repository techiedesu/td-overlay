EAPI=8
EGO_PN=github.com/nektos/act

RESTRICT="network-sandbox" # TODO: Share deps

inherit go-module

DESCRIPTION="Run your GitHub Actions locally 🚀"
HOMEPAGE="https://nektosact.com/"
SRC_URI="https://${EGO_PN}/archive/refs/tags/v${PV}.tar.gz"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"

src_compile() {
	export VERSION="${PV}"
	export PREFIX="${S}"
	P_BD="${PREFIX}/bin"
	mkdir "${P_BD}"
	export PATH="${PATH}:${P_BD}"
}

src_install() {
	default
	exeinto /usr/bin
	doexe dist/local/act
}
