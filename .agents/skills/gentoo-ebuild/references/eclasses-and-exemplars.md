# Eclasses & Prebuilt-Binary Exemplars (::gentoo, verified on disk)

Scope: eclasses + real-world repack patterns. EAPI language rules and pkgdev/pkgcheck commands are covered by sibling reports.
All `eclass/...` citations are `/var/db/repos/gentoo/eclass/<file>:<lines>`. All ebuild paths are rooted at `/var/db/repos/gentoo/`.
Portage citations are from the installed tree: `/usr/lib/portage/*/...` and `<portage-python>/...`.

---

## 1. Eclass reference

### 1.1 Summary matrix

| eclass | `@SUPPORTED_EAPIS` | phases it EXPORTs | must you re-call it by hand? | inherit order constraint |
|---|---|---|---|---|
| `unpacker` | `7 8` (`unpacker.eclass:7`) | `src_unpack` (`unpacker.eclass:651`) | only if you define your own `src_unpack`; then call `unpacker` yourself | none; it `inherit`s `multiprocessing toolchain-funcs` + `eapi9-pipestatus` internally (`unpacker.eclass:18-24`) |
| `desktop` | `7 8 9` (`desktop.eclass:7`) | **none** (no `EXPORT_FUNCTIONS` in file) | n/a — pure helper library | none |
| `xdg` | `7 8` (`xdg.eclass:9`) | `pkg_preinst pkg_postinst pkg_postrm` (`xdg.eclass:136`); additionally `src_prepare` **only in EAPI 6/7** (`xdg.eclass:129-131`) | **YES** — if you write your own `pkg_postinst`/`pkg_postrm`/`pkg_preinst` you must call `xdg_pkg_postinst` etc. | `@PROVIDES: xdg-utils` (`xdg.eclass:10`) — never inherit both `xdg` and `xdg-utils` |
| `xdg-utils` | `7 8` (`xdg-utils.eclass:10`) | **none** | you call the update functions yourself from `pkg_post*` | inherit this instead of `xdg` when you want manual control |
| `pax-utils` | `7 8` (`pax-utils.eclass:10`) | **none** | n/a | none |
| `optfeature` | `7 8 9` (`optfeature.eclass:7`) | **none** | call `optfeature` from `pkg_postinst` | none |
| `wrapper` | `7 8` (`wrapper.eclass:7`) | **none** | n/a | none |
| `linux-info` | `7 8` (`linux-info.eclass:9`) | `pkg_setup` (`linux-info.eclass:999`) | **YES** if you define `pkg_setup` → call `linux-info_pkg_setup` | none |
| `readme.gentoo-r1` | `7 8 9` (`readme.gentoo-r1.eclass:9`) | **none** | **YES** — `readme.gentoo_create_doc` in `src_install`, `readme.gentoo_print_elog` in `pkg_postinst` (`readme.gentoo-r1.eclass:12-18`) | none |
| `systemd` | — | **none** | n/a | none |
| `udev` | — | **none** | call `udev_reload` from `pkg_postinst`+`pkg_postrm` (`udev.eclass:115-118`) | none |
| `check-reqs` | `7 8` (`check-reqs.eclass:9`) | `pkg_pretend pkg_setup` (`check-reqs.eclass:492`) | **YES** if you define either phase | none |
| `verify-sig` | `7 8 9` (`verify-sig.eclass:6`) | `src_unpack` (`verify-sig.eclass:529`) | **YES** if you define `src_unpack` | **conflicts with `unpacker`**: both export `src_unpack`; last inherit wins |
| `estack` | — | **none** | n/a | not referenced by any eclass above |
| `edos2unix` | — | **none** | n/a | not referenced by any eclass above |
| `mount-boot` | — | `pkg_pretend pkg_preinst pkg_postinst pkg_prerm pkg_postrm` (`mount-boot.eclass:43`) | — | irrelevant for desktop repacks; listed for completeness |
| `chromium-2` | `7 8` (`chromium-2.eclass:10`) | **none** | call `chromium_suid_sandbox_check_kernel_config` from `pkg_setup`/`pkg_pretend`/`src_configure` | `inherit linux-info` internally (`chromium-2.eclass:17`); sets `IUSE+=" +l10n_*"` from `CHROMIUM_LANGS` → `CHROMIUM_LANGS` **must be set before `inherit`** (`chromium-2.eclass:69-71`) |

> **`unpacker` + `verify-sig` collision is real.** Both end with `EXPORT_FUNCTIONS src_unpack` (`unpacker.eclass:651`, `verify-sig.eclass:529`). If you need both, write your own `src_unpack` that calls `verify-sig_src_unpack` then `unpacker`.

### 1.2 `unpacker.eclass` — details

Public functions (signatures verbatim from `@USAGE:` lines):

| function | `@USAGE` | line |
|---|---|---|
| `unpack_pdv` | `<file to unpack> <size of off_t>` | `unpacker.eclass:69-70` |
| `unpack_makeself` | `[file to unpack] [offset] [tail\|dd]` | `unpacker.eclass:167-168` |
| `unpack_deb` | `<one deb to unpack>` | `unpacker.eclass:282-283` |
| `unpack_cpio` | `<one cpio to unpack>` | `unpacker.eclass:328-329` |
| `unpack_zip` | `<zip file>` | `unpacker.eclass:347-348` |
| `unpack_7z` | `<7z file>` | `unpacker.eclass:364-365` |
| `unpack_rar` | `<rar file>` | `unpacker.eclass:389-390` |
| `unpack_lha` | `<lha file>` | `unpacker.eclass:401-402` |
| `unpack_gpkg` | `<gpkg file>` | `unpacker.eclass:456-457` |
| `unpacker` | `[archives to unpack]` — defaults to `${A}` | `unpacker.eclass:570-578` |
| `unpacker_src_unpack` | (no args) — just runs `unpacker` | `unpacker.eclass:581-586` |
| `unpacker_src_uri_depends` | `[archives that we will unpack]` → echoes BDEPEND atoms; defaults to `${SRC_URI}` | `unpacker.eclass:588-596` |

Variables consumed: `A`, `DISTDIR`, `SRC_URI`, `EAPI`, `EPREFIX`; user-settable `UNPACKER_BZ2` (`unpacker.eclass:28-35`), `UNPACKER_LZIP` (`unpacker.eclass:37-44`), `PORTAGE_BZIP2_COMMAND`/`PORTAGE_BUNZIP2_COMMAND`.

Dispatch table in `_unpacker` (`unpacker.eclass:~520-560`): `*.deb → unpack_deb`, `*.run → unpack_makeself`, `*.sh`/`*.bin` → makeself **only if** `#.*Makeself` is found in the header, `*.zip → unpack_zip`, `*.tar.*|*.tgz|... → tar --no-same-owner -xof`, `*.gpkg.tar → unpack_gpkg`; `7z/rar/lha` handled by the eclass only in EAPI≠7.

**`.deb` mechanics** (`unpacker.eclass:286-326`): non-prefix path runs `$(tc-getBUILD_AR) t"/`p` on the archive, picks the `data.tar*` member, pipes it through `_unpacker_get_decompressor` and then `tar --no-same-owner -xf -`. Consequences:
* the **`control.tar*` is discarded** — maintainer scripts, `postinst`, `conffiles` never land in `${WORKDIR}`;
* the result is the Debian filesystem image rooted at `${WORKDIR}` → `S="${WORKDIR}"` is mandatory (see every exemplar);
* `unpacker_src_uri_depends` returns **nothing for `.deb`** (`unpacker.eclass:598-645` has no `*.deb` case) — the `ar` dependency comes from the toolchain (`@system`), so no BDEPEND is needed for plain `.deb`. It *does* emit deps for `.zip` (`app-arch/unzip`), `.7z`, `.rar`, `.zst`, `.lz4`, `.lzo`, `.lha`, `.cpio`, `.lz`, `.xz`.
* Real BDEPEND users: `app-arch/tarlz/tarlz-0.29.ebuild:29-32`, `dev-build/make/make-4.4.1-r102.ebuild:37-41`, `dev-qt/qt-docs/qt-docs-6.11.1_p202605090529.ebuild:18-20` (`$(unpacker_src_uri_depends .7z)`). 61 ebuild files in ::gentoo call it.

### 1.3 `desktop.eclass` — details

| function | `@USAGE` | line |
|---|---|---|
| `make_desktop_entry` | `[--eapi9] <command> [options]` | `desktop.eclass:25-26` |
| `make_session_desktop` | `[--eapi9] <command> [options]` | `desktop.eclass:341-342` |
| `domenu` | `<menus>` → `/usr/share/applications`, `insopts -m 0644` | `desktop.eclass:489-512` |
| `newmenu` | `<menu> <newname>` | `desktop.eclass:514-526` |
| `doicon` | `[options] <icons>` | `desktop.eclass:596-627` |
| `newicon` | `[options] <icon> <newname>` | `desktop.eclass:629-646` |

`make_desktop_entry` legacy positional form (EAPI 7/8 default): `<command> [name] [icon] [categories] [entries]` (`desktop.eclass:113-118`). New getopts form, opt-in with `--eapi9` in EAPI 7/8 and mandatory from EAPI 9 (`desktop.eclass:66-79`): `-a|--args`, `-c|--categories`, `-C|--comment`, `-d|--desktopid`, `-e|--entry` (repeatable, must be `Key=Value`), `-f|--force`, `-i|--icon`, `-n|--name` (`desktop.eclass:84-105`). Defaults: `name=${PN}`, `icon=${PN}`, `comment=${DESCRIPTION}` (`desktop.eclass:109-120`); `Categories=` is auto-derived from `${CATEGORY}` when unset (`desktop.eclass:122-243`) — e.g. `app-misc` falls into the `*)` arm and yields an **empty** `Categories=`, so pass `-c` explicitly for `app-misc`.
Icon-extension guard: a relative `Icon=` ending in `.xpm/.png/.svg` triggers `ewarn` and the extension is stripped (`desktop.eclass:275-280`).

`doicon`/`newicon` option set (`_iconins`, `desktop.eclass:528-594`): `-s|--size` (accepts `48` or `48x48`; legal values `16 22 24 32 36 48 64 72 96 128 192 256 512 1024 symbolic scalable`), `-c|--context` (default `apps`), `-t|--theme` (default `hicolor`). **Without `-s` the icon goes to `/usr/share/pixmaps`; with `-s` it goes to `/usr/share/icons/${theme}/${size}/${context}`** (`desktop.eclass:562-567`).

### 1.4 `xdg.eclass` / `xdg-utils.eclass`

`xdg_pkg_preinst` (`xdg.eclass:56-78`) scans `${ED}` for `usr/share/applications`, `usr/share/icons`, `usr/share/mime` and stores results in `XDG_ECLASS_DESKTOPFILES`, `XDG_ECLASS_ICONFILES`, `XDG_ECLASS_MIMEINFOFILES`. `xdg_pkg_postinst` (`xdg.eclass:80-101`) and `xdg_pkg_postrm` (`xdg.eclass:103-124`) conditionally run the three updaters based on those arrays. **Therefore: if you override `pkg_preinst` you must call `xdg_pkg_preinst`, or `pkg_postinst` will silently do nothing.**

Dependency injection: in EAPI 7 `DEPEND="dev-util/desktop-file-utils x11-misc/shared-mime-info"`; in EAPI 8 it becomes `IDEPEND` (`xdg.eclass:32-52`). You do not add these yourself.

`xdg-utils` functions, all of which `die` unless `${EBUILD_PHASE} == post*`:
* `xdg_environment_reset` (`xdg-utils.eclass:37-54`) — exports `XDG_{DATA,CONFIG,CACHE,STATE}_HOME`, `XDG_RUNTIME_DIR=${T}/run` (chmod 0700), unsets `DBUS_SESSION_BUS_ADDRESS`. In EAPI 8 `xdg` no longer calls this for you (`xdg.eclass:44-51` — `xdg_src_prepare` dies in EAPI ≥ 8); call it from `src_prepare`/`src_configure` if the build touches a session bus.
* `xdg_desktop_database_update` (`xdg-utils.eclass:56-73`) — `update-desktop-database -q "${EROOT}/usr/share/applications"`.
* `xdg_icon_cache_update` (`xdg-utils.eclass:75-113`) — `gtk-update-icon-cache -qf` per theme dir that has `index.theme`; also GCs stale `icon-theme.cache` and empty theme dirs.
* `xdg_mimeinfo_database_update` (`xdg-utils.eclass:115-134`) — `update-mime-database "${EROOT}/usr/share/mime"` with `PKGSYSTEM_ENABLE_FSYNC=0` (bug 819783).

### 1.5 `pax-utils.eclass`

`pax-mark <flags> <ELF files>` (`pax-utils.eclass:39-149`). Flags are single letters, optional leading `-`; the eclass filters the argument to `[zPpEeMmRrSs]` (`pax-utils.eclass:72`), so `pax-mark m x` and `pax-mark -m x` are identical. `z` = reset to default. `PAX_MARKINGS` defaults to **`none`** (`pax-utils.eclass:32-36`), i.e. on a stock non-hardened profile `pax-mark` is a no-op — it is cheap insurance, not a requirement.
Also: `list-paxables <files>` (`pax-utils.eclass:151-164`), `host-is-pax` (`pax-utils.eclass:166-172`).
Example from the tree: `media-sound/spotify/spotify-1.2.96.ebuild:117-120` does the 3-step `pax-mark C` → `pax-mark z` → `pax-mark m` dance under `USE=pax-kernel`.

### 1.6 `wrapper.eclass`

`make_wrapper <wrapper> <target> [chdir] [libpaths] [installpath]` (`wrapper.eclass:18-19`). Emits `#!/bin/sh`, optional `LD_LIBRARY_PATH` (`DYLD_LIBRARY_PATH` on darwin) prepend, optional `cd "${EPREFIX}${chdir}" &&`, then `exec <target> "$@"` (`wrapper.eclass:26-49`). `${bin}` is deliberately unquoted so it may carry arguments. With no `installpath` it uses `newbin`; otherwise `exeinto ${path}; newexe` (`wrapper.eclass:51-60`).
Real use with a space in the target: `dev-db/mongodb-compass-bin/mongodb-compass-bin-1.50.0.ebuild:73` → `make_wrapper mongodb-compass "'/usr/lib/mongodb-compass/MongoDB Compass'"`.

### 1.7 `optfeature.eclass`

`optfeature <short description> <package atom to match> [other atoms]` (`optfeature.eclass:70-71`). Space-separated atoms **inside one argument** mean AND; separate arguments mean OR (`optfeature.eclass:88-104`). `optfeature_header [text]` (`optfeature.eclass:43-44`) overrides the default banner `Install additional packages for optional runtime features:` (`optfeature.eclass:22`); the header is printed once, lazily, only if something is missing (`optfeature.eclass:105-109`).
Tree examples: `net-im/discord/discord-1.0.154.ebuild:213-217`, `net-im/slack/slack-4.51.191.ebuild:110`.

### 1.8 `readme.gentoo-r1.eclass`

`readme.gentoo_create_doc` (`readme.gentoo-r1.eclass:51-84`) — uses `${DOC_CONTENTS}` (`:29`), else `${FILESDIR}/README.gentoo-${SLOT%/*}`, else `${FILESDIR}/README.gentoo${README_GENTOO_SUFFIX}`, else dies. Without `DISABLE_AUTOFORMATTING` (`:34`) the text is piped through `fold -s -w 70`. Installs via `docinto .; dodoc` and sets `README_GENTOO_DOC_VALUE`.
`readme.gentoo_print_elog` (`readme.gentoo-r1.eclass:86-110`) — dies if `create_doc` was not called; prints only when `REPLACING_VERSIONS` is empty, unless `FORCE_PRINT_ELOG` (`:41`) is set.
Exemplar: `net-im/zoom/zoom-7.0.0.1666-r2.ebuild:139-148` (local `DOC_CONTENTS` + `readme.gentoo_create_doc`) and `:151-155` (`readme.gentoo_print_elog` in `pkg_postinst`).

### 1.9 `linux-info.eclass`

Consumes `CONFIG_CHECK` (`linux-info.eclass:54-75`) — prefix `~` = warn only, `!` = must be absent, combinable; `ERROR_<CFG>` / `WARNING_<CFG>` (`linux-info.eclass:77-89`) supply the message. `KERNEL_DIR` defaults to `${ROOT}/usr/src/linux` (`:49-52`). Outputs `KV_FULL`/`KV_MAJOR`/`KV_MINOR`/... Public helpers: `linux_config_exists` (`:321`), `linux_chkconfig_present <option>` (`:368-369`), `get_version` (`:473`), `linux-info_get_any_version` (`:663`), `check_extra_config` (`:743-746`), `linux-info_pkg_setup` (`:971-974`). Exports `pkg_setup` (`:999`).
Prebuilt usage: `net-im/zoom/zoom-7.0.0.1666-r2.ebuild:79` → `CONFIG_CHECK="~USER_NS ~PID_NS ~NET_NS ~SECCOMP_FILTER"`; `net-im/discord/discord-1.0.154.ebuild:100` → `CONFIG_CHECK="~USER_NS"`; `www-client/vivaldi/vivaldi-8.2.4133.47.ebuild:135` → `CONFIG_CHECK="~CPU_FREQ"`.

### 1.10 `check-reqs.eclass`

Variables: `CHECKREQS_MEMORY`, `CHECKREQS_DISK_BUILD`, `CHECKREQS_DISK_USR`, `CHECKREQS_DISK_VAR` (`check-reqs.eclass:49-73`), user-only `CHECKREQS_DONOTHING` (`:69-75`). Exported phases `pkg_pretend pkg_setup` (`:492`), both running `_check-reqs_prepare/_run/_output` (`:83-101`). Dies if inherited with no variable set (`:117-129`). Relevant for a ~200 MB Electron `.deb`: `CHECKREQS_DISK_BUILD` should cover WORKDIR+image (~3× the deb).

### 1.11 `verify-sig.eclass`

`VERIFY_SIG_METHOD` ∈ `minisig|openpgp|sigstore|signify`, default `openpgp` (`verify-sig.eclass:52-64`), `@PRE_INHERIT`. BDEPEND is set automatically per method (`:66-92`). `VERIFY_SIG_OPENPGP_KEY_PATH` (`:96-105`) is required for the default `src_unpack`. Functions: `verify-sig_verify_detached <file> <sig-file> [<key-file>]` (`:138-139`), `verify-sig_verify_message <file> <output-file> [<key-file>]` (`:230-231`), `verify-sig_verify_unsigned_checksums <checksum-file> <format> <files>` (`:294-295`), `verify-sig_verify_signed_checksums <checksum-file> <algo> <files> [<key-file>]` (`:388-389`), `verify-sig_uncompress_verify_unpack <compressed-tar> <sig-file> [<key-file>]` (`:430-431`), `verify-sig_src_unpack` (`:460-467`). Adds `IUSE="verify-sig"` (`:51`).
**Not applicable to a vendor `.deb` with no detached signature** — Anthropic/Slack/Signal ship no `.sig`, so skip this eclass rather than faking it.

### 1.12 `systemd.eclass` / `udev.eclass` (only if the package ships units/rules)

`systemd`: `systemd_get_systemunitdir` (`systemd.eclass:72`), `systemd_get_userunitdir` (`:83`), `systemd_get_utildir` (`:94`), `systemd_get_systemgeneratordir` (`:105`), `systemd_get_systempresetdir` (`:115`), `systemd_get_sleepdir` (`:125`), `systemd_dounit <unit>...` (`:133-134`), `systemd_newunit <old-name> <new-name>` (`:147-148`), `systemd_douserunit <unit>...` (`:161-162`), `systemd_newuserunit <old-name> <new-name>` (`:175-176`), `systemd_install_serviced <conf-file> [<service>]` (`:190-191`). No exported phases.
`udev`: `get_udevdir` (`udev.eclass:76`), `udev_get_udevdir` (`:66`, deprecated in favour of `get_udevdir`), `udev_dorules <rule> [...]` (`:87-88`), `udev_newrules <oldname> <newname>` (`:101-102`), `udev_reload` (`:115-118`), `udev_hwdb_update` (`:134-137`). No exported phases — call `udev_reload` yourself from `pkg_postinst` **and** `pkg_postrm`.

### 1.13 `estack` / `edos2unix`

Neither is referenced by any eclass in §1.1 (verified: no `inherit estack` / `inherit edos2unix` in those files). `estack` provides `estack_push <stack> [items]` (`estack.eclass:13-14`), `estack_pop <stack> [variable]` (`:33-34`), `evar_push`/`evar_push_set`/`evar_pop` (`:61,94,109`), `eshopts_push`/`eshopts_pop` (`:133,169`), `eumask_push <new umask>`/`eumask_pop` (`:180,190`). `edos2unix <file> [more files...]` (`edos2unix.eclass:9-10`). Neither is needed for a binary repack.

---

## 2. Exemplars — 21 prebuilt ebuilds in ::gentoo

All paths verified to exist. `deb` = upstream `.deb`, `tar` = prebuilt tarball, `distro` = brotli blobs.

| # | path | src | inherit | LICENSE | KEYWORDS | RESTRICT | QA_* | install root | launcher |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `www-client/google-chrome-beta/google-chrome-beta-154.0.8037.17.ebuild` | deb | `chromium-2 desktop pax-utils unpacker xdg` (`:11`) | `google-chrome` | `-* ~amd64 ~arm64` | `bindist mirror strip` (`:36`) | `QA_PREBUILT="*"` (`:73`), `QA_DESKTOP_FILE="usr/share/applications/google-chrome.*\\.desktop"` (`:74`) | `/opt/google/chrome-beta` (`:75`) | deb's own `/usr/bin` symlink kept (whole-image install `:97-99`) |
| 2 | `www-client/microsoft-edge/microsoft-edge-153.0.4234.32.ebuild` | deb | `chromium-2 desktop pax-utils unpacker xdg` (`:6`) | `microsoft-edge` (`:21`) | `-* amd64` (`:23`) | `bindist mirror strip` (`:26`) | `QA_PREBUILT="*"` (`:65`), `QA_DESKTOP_FILE` (`:66`) | `/opt/microsoft/msedge` (`:67`) | deb's own symlink; `pax-mark m` (`:124`) |
| 3 | `www-client/opera/opera-135.0.5973.133-r1.ebuild` | deb | `chromium-2 pax-utils unpacker xdg` (`:19`) | `OPERA-2018` (`:42`) | `-* amd64` (`:44`) | `bindist mirror strip` (`:46`) | `QA_PREBUILT="*"` (`:82`) | `/opt/opera-stable` (`:83`, moved from `usr/lib/x86_64-linux-gnu` `:107-109`) | `rm usr/bin/opera; dosym` (`:124-125`) |
| 4 | `www-client/vivaldi/vivaldi-8.2.4133.47.ebuild` | deb | `chromium-2 desktop linux-info toolchain-funcs unpacker xdg` (`:77`) | `Vivaldi` (`:98`) | `-* amd64 arm64` (`:100`) | `bindist mirror` (`:102`) | `QA_PREBUILT="*"` (`:134`) | `/opt/vivaldi` (`:80`) | `dosym` (`:180`, `:201-202`); `fperms 4711 vivaldi-sandbox` (`:181`) |
| 5 | `www-client/firefox-bin/firefox-bin-156.0.ebuild` | tar | `desktop linux-info optfeature pax-utils xdg` (`:34`) | `MPL-2.0 GPL-2 LGPL-2.1` (`:44`) | `-* amd64 ~arm64` (`:43`) | `strip` (`:47`) | `QA_PREBUILT="opt/firefox/*"` (`:88`) | `/opt/firefox` | `newmenu` template (`:288`); `pax-mark m` on 3 binaries (`:205-208`) |
| 6 | `net-im/slack/slack-4.51.191.ebuild` | deb | `desktop multilib-build optfeature pax-utils unpacker xdg` (`:8`) | `all-rights-reserved` (`:15`) | `-* ~amd64` (`:17`) | `bindist mirror` (`:19`) | `QA_PREBUILT` = 11-entry explicit list (`:49-59`) | `/opt/slack` via `cp -a usr/lib/slack "${ED}"/opt` (`:95-96`) | `dosym ../../opt/slack/slack usr/bin/slack` (`:99`) |
| 7 | `net-im/signal-desktop-bin/signal-desktop-bin-8.26.0.ebuild` | deb | `pax-utils unpacker xdg` (`:8`) | `AGPL-3` + 40 bundled-Chromium licenses (`:17-24`) | `-* amd64` (`:27`) | `splitdebug` (`:28`) | `QA_PREBUILT` explicit list (`:61-72`) | `/opt/Signal` via `insinto /; doins -r opt` (`:85-87`) | `dosym ../../opt/Signal/signal-desktop /usr/bin/...` (`:93`) |
| 8 | `net-im/element-desktop-bin/element-desktop-bin-1.12.26.ebuild` | deb | `optfeature unpacker xdg` (`:6`) | `Apache-2.0` (`:22`) | `-* ~amd64 ~arm64` (`:24`) | `splitdebug` (`:25`) | `QA_PREBUILT` explicit list (`:56-64`) | `/opt/Element` via `insinto /; doins -r usr; doins -r opt` (`:76-78`) | two `dosym`s incl. legacy alias `riot-desktop` (`:85-86`) |
| 9 | `net-im/discord/discord-1.0.154.ebuild` | distro | `chromium-2 desktop linux-info optfeature python-single-r1 unpacker xdg` (`:17`) | `all-rights-reserved` (`:52`) | `amd64` (`:54`) | `bindist mirror strip test` (`:58`) | `QA_PREBUILT="*"` (`:98`), `CONFIG_CHECK="~USER_NS"` (`:100`) | `/opt/discord` (`DESTDIR` var, `:96`) | custom `${FILESDIR}/launcher-r1.sh` sed-templated then `newexe` (`:151-153`, `:205-206`) |
| 10 | `net-im/zoom/zoom-7.0.0.1666-r2.ebuild` | tar | `desktop linux-info readme.gentoo-r1 xdg-utils` (`:6`) | `all-rights-reserved` (`:12`) | `-* ~amd64` (`:14`) | `mirror bindist strip` (`:16`) | `QA_PREBUILT="opt/zoom/*"` (`:80`), `CONFIG_CHECK` (`:79`) | `/opt/zoom` (`:105-113`) | `dosym -r /opt/zoom/ZoomLauncher /usr/bin/zoom` under `USE=zoom-symlink` (`:126`) |
| 11 | `net-im/whatsapp-desktop-bin/whatsapp-desktop-bin-0.5.4.ebuild` | deb | `chromium-2 desktop unpacker xdg` (`:12`) | 17-license list incl. `all-rights-reserved` (`:23-26`) | `-* ~amd64 ~x86` (`:28`) | `bindist mirror` (`:30`) | `QA_PREBUILT="opt/whatsapp-desktop/*"` (`:64`) | `/opt/whatsapp-desktop` | — |
| 12 | `net-im/telegram-desktop-bin/telegram-desktop-bin-7.1.5.ebuild` | tar | `desktop optfeature xdg` (`:6`) | `GPL-3-with-openssl-exception` (`:17`) | `-* ~amd64` (`:19`) | *(none)* | `QA_PREBUILT="usr/bin/telegram-desktop"` (`:21`) | `/usr/bin` directly | binary is the launcher; `domenu` upstream file (`:66`) + `dbus-1/services` (`:67-68`) |
| 13 | `net-im/mattermost-desktop-bin/mattermost-desktop-bin-6.3.1_rc1.ebuild` | tar | `desktop toolchain-funcs xdg` (`:9`) | `Apache-2.0 GPL-2+ LGPL-2.1+ MIT` (`:20`) | `~amd64 ~arm64` (conditional, `:22-24`) | *(none)* | `QA_PREBUILT` explicit list (`:58-61`) | `/opt/mattermost-desktop` (`:101-102`) | `dosym -r` (`:112`) + `make_desktop_entry --eapi9` (`:114-117`) |
| 14 | `media-sound/spotify/spotify-1.2.96.ebuild` | deb | `desktop pax-utils unpacker xdg` (`:6`) | `Spotify` (`:14`) | `amd64` (`:16`) | `mirror strip` (`:18`) | `QA_PREBUILT` explicit list (`:63-72`) | `/opt/spotify/spotify-client` (`:104-107`) | `envsubst` over `${FILESDIR}/spotify-wrapper` → `/usr/bin/spotify` (`:109-113`) |
| 15 | `dev-db/mongodb-compass-bin/mongodb-compass-bin-1.50.0.ebuild` | deb | `chromium-2 desktop unpacker wrapper xdg` (`:11`) | `SSPL-1` (`:19`) | `-* ~amd64` (`:21`) | *(none)* | `QA_PREBUILT="usr/lib/mongodb-compass/.*"` (`:45-47`) | **`/usr/lib/mongodb-compass`** (`:62-63`) | `make_wrapper` (`:73`) |
| 16 | `app-office/onlyoffice-bin/onlyoffice-bin-9.4.0.ebuild` | deb | `desktop unpacker xdg` (`:6`) | `AGPL-3` (`:20`) | `amd64` (`:22`) | `mirror strip test` (`:23`) | `QA_PREBUILT="*"` (`:64`) | `/opt/onlyoffice` (`:85`) | `dobin usr/bin/{desktopeditors,onlyoffice-desktopeditors}` (`:84`) |
| 17 | `app-office/drawio-desktop-bin/drawio-desktop-bin-29.6.6.ebuild` | deb | `chromium-2 desktop unpacker xdg` (`:12`) | 12-license list (`:36-38`) | `-* ~amd64` (`:42`) | *(none)* | `QA_PREBUILT="opt/drawio/*"` (`:68`) | `/opt/drawio` (`:92`) | `dosym /opt/drawio/drawio /usr/bin/drawio` (`:124`) |
| 18 | `app-editors/vscode/vscode-1.137.0.ebuild` | tar | `chromium-2 desktop optfeature pax-utils shell-completion xdg` (`:10`) | 16-license list (`:22-38`) | `-* amd64 ~arm arm64` (`:40`) | `mirror strip bindist` (`:42`) | `QA_PREBUILT="*"` (`:82`) | `/opt/vscode` (`:116-117`) | two `dosym -r` (`:120-121`); `fperms 4711 chrome-sandbox` (`:118`) |
| 19 | `app-admin/bitwarden-desktop-bin/bitwarden-desktop-bin-2026.8.0.ebuild` | deb | `desktop unpacker xdg-utils` (`:6`) | `GPL-3` (`:13`) | `~amd64` (`:15`) | *(none)* | `QA_PREBUILT` explicit list (`:56-59`) | `/opt/Bitwarden` | `dosym -r` (`:79`); `fperms 4755 chrome-sandbox` (`:70`) |
| 20 | `games-util/heroic-bin/heroic-bin-2.22.1.ebuild` | tar | `chromium-2 desktop python-single-r1 xdg` (`:12`) | `GPL-3+` (`:30`) | `~amd64` (`:32`) | *(none)* | `QA_PREBUILT=".*"` (`:91`) | `/opt/heroic` via `cp -r` (`:133`) | `dosym -r .../heroic /usr/bin/heroic-run` (`:140`) |
| 21 | `app-text/zotero-bin/zotero-bin-10.0.1.ebuild` | tar | `desktop xdg` (`:6`) | `AGPL-3` (`:17`) | `-* ~amd64 ~arm64 ~x86` (`:19`) | *(none)* | `QA_PREBUILT="opt/zotero/*"` (`:49`) | `/opt/zotero` | `dosym` (`:80`) + `domenu` (`:82`) |

### 2.1 Interesting `src_prepare` / `src_install` hacks worth copying

| trick | where | what it does |
|---|---|---|
| Whole-image passthrough | `www-client/google-chrome-beta/...:93-99`, `www-client/opera/...:97-101`, `www-client/microsoft-edge/...:85-91` | `src_unpack() { :; }` then in `src_install`: `dodir /; cd "${ED}" \|\| die; unpacker` — unpacks the `.deb` **directly into the image**, so the deb's own `/usr/bin`, `.desktop`, icons and man pages are installed verbatim. Requires cleaning vendor cruft afterwards (`rm -r etc/cron.daily`, `rm -r usr/share/lintian`). |
| Fix hard-coded `Icon=`/`Exec=` before install | `net-im/slack/...:67-70` (`sed -i -e '/Icon/s\|/usr/share/pixmaps/slack.png\|slack\|' -e '/Exec/s\|slack\|slack -s\|'`), `net-im/signal-desktop-bin/...:77-78` | Upstream `.desktop` points at `/opt/...`; rewrite to the `/usr/bin` launcher and to a themed icon name. |
| Rename `.desktop` to match the Wayland app-id | `net-im/signal-desktop-bin/...:81-87` | `mv usr/share/applications/signal-desktop.desktop usr/share/applications/signal.desktop` so the compositor can match `app-id`. |
| Kill the bundled auto-updater | `www-client/opera/...:111-112` (`rm opera_autoupdate{,.licenses,.version}`), `app-editors/vscode/...:107` (`sed -e "/updateUrl/d" -i resources/app/product.json`), `net-im/discord/...:184-185` (installs flathub's `disable-breaking-updates.py`) | Mandatory hygiene for repacks. |
| `patchelf --replace-needed` for a Debian-only soname | `media-sound/spotify/...:95-99` | `libcurl-gnutls.so.4` → `libcurl.so.4`; `BDEPEND=">=dev-util/patchelf-0.10"` (`:32`). |
| Drop libs with unresolvable sonames | `app-office/onlyoffice-bin/...:78-79` | `rm -v .../libqtvirtualkeyboardplugin.so \|\| die` with bug reference. |
| Decompress the Debian changelog | `www-client/opera/...:116`, `net-im/element-desktop-bin/...:74`, `www-client/google-chrome-beta/...:104` | `mv usr/share/doc/${MY_PN} usr/share/doc/${PF}` then `gzip -d .../changelog.gz` — portage compresses docs itself, shipping a pre-gzipped one trips the ecompress QA notice (`/usr/lib/portage/*/ecompress:267-271`). |
| Extract an icon out of the binary | `net-im/zoom/...:83-86` | `bbe -s -b '/<svg .../:/<\\/svg>\\n/' -e 'J 1;D' zoom > videoconference-zoom.svg`, with `BDEPEND="dev-util/bbe"` (`:77`). |
| Bundle-lib symlink to the system copy | `net-im/slack/...:105-107`, `net-im/discord/...:209-211` | `dosym ../../usr/lib64/libayatana-appindicator3.so /opt/slack/libappindicator3.so` (bug 898912). |
| USE-flag-driven `Exec=` flags | `net-im/slack/...:72-90`, `app-editors/vscode/...:123-135` | sed in `--ozone-platform-hint=auto`, `--enable-features=...` per USE. |
| Language-pak pruning | `chromium-2.eclass:73-116` via `chromium_remove_language_paks` | Used by 10 of 21 exemplars; `CHROMIUM_LANGS` must be set **before** `inherit` because it generates `IUSE=+l10n_*` (`chromium-2.eclass:69-71`). |

---

## 3. The recurring house pattern — with observed counts

Population = the 21 ebuilds in §2 (each verified by reading or grepping the file).

| trait | count | note |
|---|---|---|
| `QA_PREBUILT` set | **21 / 21** | universal. `"*"` in 6, `".*"` in 2 (`heroic`, and `mongodb-compass` uses `usr/lib/mongodb-compass/.*`), path-glob in 7, explicit file list in 6. |
| `RESTRICT` contains `strip` | **9 / 21** | chrome, edge, opera, firefox-bin, discord, zoom, spotify, onlyoffice, vscode |
| `RESTRICT` contains `mirror` | **11 / 21** | any non-redistributable or session-token download URL |
| `RESTRICT` contains `bindist` | **9 / 21** | proprietary EULA → binpkgs must not be shared |
| `RESTRICT` contains `splitdebug` | **2 / 21** | signal-desktop-bin, element-desktop-bin (modern alternative to `strip` — keeps stripping off but avoids the debug-split machinery) |
| `RESTRICT` contains `test` | **2 / 21** | discord, onlyoffice |
| **no `RESTRICT` at all** | **7 / 21** | telegram, mattermost, mongodb-compass, drawio, bitwarden, heroic, zotero — i.e. `RESTRICT=strip` is **not** mandatory; `QA_PREBUILT` alone already whitelists pre-stripped files |
| `KEYWORDS` begins with `-*` | **15 / 21** | the house style for arch-locked binaries; the 6 exceptions are discord, onlyoffice, spotify, mattermost, bitwarden, heroic |
| `LICENSE="all-rights-reserved"` exactly | **3 / 21** | slack, discord, zoom. 5 others use a vendor-specific license file (`google-chrome`, `microsoft-edge`, `OPERA-2018`, `Vivaldi`, `Spotify`) that must exist under `licenses/`; 6 enumerate the full bundled-dependency license list (signal lists 40). |
| `inherit xdg` | **19 / 21** | exceptions: zoom and bitwarden inherit `xdg-utils` and drive the updates manually |
| `inherit desktop` | **18 / 21** | not: opera, signal, element (they install the deb's `.desktop` with `doins`) |
| `inherit unpacker` | **14 / 21** | exactly the `.deb` + `.distro` consumers; the 7 tarball repacks rely on the default `src_unpack` |
| `inherit pax-utils` + calls `pax-mark` | **8 / 21** | chrome, edge, opera, firefox-bin, slack, signal, spotify, vscode — perfectly correlated: no exemplar inherits `pax-utils` without calling `pax-mark` |
| `inherit chromium-2` | **10 / 21** | every Electron/CEF repack that prunes `*.pak` or checks the SUID-sandbox kernel config |
| `inherit optfeature` | **6 / 21** | firefox-bin, slack, element, discord, telegram, vscode |
| explicit `xdg_pkg_postinst` inside a hand-written `pkg_postinst` | **5 / 5 that define one** | slack `:112`, element `:89`, discord `:196`, spotify `:127`, vscode `:151` — **100 % of overriding ebuilds re-call it** |
| setuid on `chrome-sandbox` | **8 / 21** | `4755`: bitwarden `:70`, mongodb-compass `:67`. `4711`: discord `:190` (+`fowners root` `:189`), vscode `:118`, opera `:142` (`opera_sandbox`, `USE=suid`), vivaldi `:181` (`vivaldi-sandbox`). `u+s`: signal `:90`, element `:83`, slack `:98` (`USE=suid`). Tree-wide, 50 ebuild files match `fperms (4755\|4711\|u\+s).*sandbox`. |
| `QA_DESKTOP_FILE` | **2 / 21** (chrome, edge) | tree-wide exactly **17 ebuild files** in 8 package dirs: `www-client/google-chrome{,-beta,-unstable}`, `www-client/microsoft-edge{,-beta,-dev}`, `app-emulation/wine-desktop-common`, `media-tv/plex-media-server`. Only needed when the vendor's own `.desktop` fails `desktop-file-validate`. |
| `QA_FLAGS_IGNORED` | **0 / 21** | redundant: `QA_PREBUILT` already feeds it (`/usr/lib/portage/*/phase-functions.sh:597-603`). It is a **source**-package idiom for Go/Rust (`app-admin/mongo-tools/mongo-tools-100.9.4.ebuild:22-23` `QA_FLAGS_IGNORED='.*'`, `app-admin/sudo-rs/sudo-rs-0.2.15.ebuild:43`). |
| `QA_SONAME` | **0 / 21** | likewise redundant via `QA_PREBUILT`. Standalone use: `app-arch/csnappy/csnappy-0_pre20220804.ebuild:22-23`. |
| `QA_DT_HASH` | **0 occurrences in all of `/var/db/repos/gentoo` and 0 in `/usr/lib/portage`** | **the variable no longer exists** — do not write it. |
| `dostrip -x` | **0 / 21** | 144 ebuild files tree-wide, all *source* packages shielding prebuilt sub-artifacts: `app-emulation/qemu/qemu-10.2.3.ebuild:919` (`dostrip -x ${QA_PREBUILT}`), `app-emulation/wine-vanilla/wine-vanilla-8.0.2.ebuild:362`, `dev-debug/valgrind/valgrind-3.27.0.ebuild:184`, `dev-debug/rr/rr-5.9.0-r1.ebuild:107`, `app-forensics/aflplusplus/aflplusplus-4.35c.ebuild:92`. |

### 3.1 Why they co-occur (mechanism, not folklore)

1. **`QA_PREBUILT` is the master switch.** `/usr/lib/portage/*/phase-functions.sh:585-608` expands it, *after* `pkg_setup* and before `src_install`, into:
   * fnmatch-matched: `QA_EXECSTACK`, `QA_TEXTRELS`, `QA_WX_LOAD`;
   * regex-translated (`${QA_PREBUILT//\*/.*}`): `QA_DT_NEEDED`, `QA_FLAGS_IGNORED`, `QA_PRESTRIPPED`, `QA_SONAME`, `QA_SONAME_NO_SYMLINK`.
   So one `QA_PREBUILT="opt/foo/*"` silences pre-stripped, ignored-CFLAGS/LDFLAGS, execstack, textrel, WX-load, missing-SONAME and missing-NEEDED at once. That is exactly why 0 of 21 set the individual variables.
2. **`RESTRICT="strip"` is a different lever.** `/usr/lib/portage/*/estrip:412-421` reads `PORTAGE_RESTRICT` into `has_restriction[strip]` and skips stripping entirely; `:528` also skips the pre-stripped *scan* under `RESTRICT=binchecks`. Use `strip` when you don't want portage rewriting vendor ELFs at all (Electron binaries with appended ASAR/signature data can be corrupted by `strip`). `QA_PREBUILT` only silences the *warning*; `RESTRICT=strip` prevents the *action*. Both are common; 9 of 21 use both.
3. **`RESTRICT="bindist"`** — proprietary EULA forbids redistributing built binpkgs. Pairs with `LICENSE=all-rights-reserved` / a vendor license file. **`RESTRICT="mirror"`** — Gentoo mirrors may not carry the distfile. **`RESTRICT="test"`** — there is nothing to test in a repack; only 2 of 21 bother, because no `src_test` is defined anyway.
4. **`pax-mark m <main binary>`** disables MPROTECT for the JIT in Chromium/SpiderMonkey. Harmless on stock profiles (`PAX_MARKINGS` defaults to `none`, `pax-utils.eclass:32-36`) and required on hardened; cost is one line.
5. **`fperms 4755|4711 chrome-sandbox`** — Electron's SUID sandbox helper refuses to run without the setuid bit (comment + upstream link at `net-im/discord/discord-1.0.154.ebuild:187-188`, `dev-db/mongodb-compass-bin/...:67`). `4711` additionally hides the binary from non-owners; `discord` pairs it with `fowners root` (`:189`). Ebuilds that gate it behind `USE=suid` (slack `:98`, opera `:142`, vivaldi always) let the user pick namespaces-only sandboxing.
6. **`dostrip -x`** is the *fine-grained* alternative to `RESTRICT=strip`: keep stripping for the package's own compiled output, exclude the prebuilt subtree. Only useful for mixed source+prebuilt packages; a pure repack should use `RESTRICT=strip` or nothing.

### 3.2 Minimal correct skeleton distilled from the 21

```bash
EAPI=8
inherit desktop optfeature unpacker xdg

SRC_URI="https://vendor.example/pool/${PN}_${PV}_amd64.deb"
S="${WORKDIR}"                 # unpack_deb explodes data.tar into WORKDIR

LICENSE="all-rights-reserved"  # or a real file in licenses/
SLOT="0"
KEYWORDS="-* ~amd64"           # -* because it is amd64-only by construction
RESTRICT="bindist mirror strip"

QA_PREBUILT="opt/${PN}/*"

src_prepare() {
    default
    sed -i -e "/^Exec=/s|.*|Exec=${PN} %U|" \
           -e "/^Icon=/s|.*|Icon=${PN}|" \
        usr/share/applications/${PN}.desktop || die
}

src_install() {
    insinto /opt/${PN}
    doins -r opt/${PN}/.
    fperms +x /opt/${PN}/${PN}
    fperms 4755 /opt/${PN}/chrome-sandbox
    dosym -r /opt/${PN}/${PN} /usr/bin/${PN}

    domenu usr/share/applications/${PN}.desktop
    local s
    for s in 16 32 48 64 128 256 512; do
        doicon -s ${s} usr/share/icons/hicolor/${s}x${s}/apps/${PN}.png
    done
}

pkg_postinst() {
    xdg_pkg_postinst          # MANDATORY once you define pkg_postinst
    optfeature "secret storage" app-crypt/libsecret
}
```

---

## 4. `/opt` installs: desktop entries, icons, MIME, and the xdg interaction

### 4.1 Desktop entries — four idioms, counted over the 21

| idiom | count | examples |
|---|---|---|
| `domenu <file>` (the vendor's own `.desktop`, possibly sed-patched) | **9** | slack `:94`, spotify `:122`, mongodb-compass `:69`, onlyoffice `:81`, drawio `:114`, bitwarden `:72`, telegram `:66`, zotero `:82`, vscode `:137-138` |
| `newmenu <src> <name>.desktop` | **2** | firefox-bin `:288`, heroic `:143-148` |
| `make_desktop_entry` (synthesised) | **3** | discord `:167-170`, zoom `:129-135`, mattermost `:114-117` (`--eapi9` getopts form) |
| `insinto /usr/share; doins -r usr/share/applications` | **2** | signal `:87-88`, element `:76-77` |
| deb's file installed verbatim by whole-image `unpacker` | **4** | chrome, edge, opera, vivaldi |

`domenu` is not just `doins`: it forces `insopts -m 0644` and `insinto /usr/share/applications` **inside a subshell** so it cannot corrupt the caller's `insinto` (`desktop.eclass:494-512`). Prefer it over hand-rolled `insinto /usr/share/applications` — no exemplar uses the hand-rolled form for applications.

### 4.2 Icons

* `doicon`/`newicon` **without `-s`** → `/usr/share/pixmaps` (`desktop.eclass:562-563`). Used by slack `:93` (`doicon usr/share/pixmaps/slack.png`), mongodb-compass `:70`, mattermost `:99`, heroic `:149-150`.
* **with `-s <size>`** → `/usr/share/icons/hicolor/<size>x<size>/apps` (`desktop.eclass:564-566`). The dominant idiom is a size loop: chrome `:127-129`, edge `:111-113`, vivaldi `:184-188`, spotify `:115-119`, drawio `:96-103`, onlyoffice `:82-84`, telegram `:53-57`, zotero `:84-86`, bitwarden `:75-77`, slack `:93-94` (both pixmaps and 512).
* `-s scalable` for SVG: zoom `:137` (`doicon -s scalable videoconference-zoom.svg`), drawio `:104-105`.
* `-s symbolic` for monochrome tray icons: telegram `:60-64`; firefox-bin instead hand-rolls `insinto /usr/share/icons/hicolor/symbolic/apps; newins` (`:240-241`).
* `-c mimetypes` to register a **file-type** icon rather than an app icon: drawio `:100-101,105` (`newicon -s ${SZ} -c mimetypes ... application-vnd.jgraph.mxfile.png`).
* Bulk copy when the vendor tree already has a correct hicolor layout: signal `:88` / element `:77` (`doins -r usr/share/icons`). This is the only case where bypassing `doicon` is justified.

**Icon name must match `Icon=` in the `.desktop`, extension-less.** `make_desktop_entry` strips a trailing `.png/.svg/.xpm` from a relative icon and `ewarn`s (`desktop.eclass:275-280`); slack's `sed` at `:68` exists precisely to turn `Icon=/usr/share/pixmaps/slack.png` into `Icon=slack`.

### 4.3 MIME types and URI-scheme handlers

* **File-type MIME**: install the XML package and let `update-mime-database` run in postinst. `app-office/drawio-desktop-bin/...:110-112` → `insinto /usr/share/mime/packages; doins usr/share/mime/packages/drawio.xml`, after patching it in `src_prepare:82-87` to add `<sub-class-of type="text/xml"/>` and a proper `<icon name=.../>`. `app-editors/vscode/vscode-1.137.0.ebuild:144-145` installs `${FILESDIR}/code-workspace.xml` the same way.
* **URI-scheme handlers** live in the `.desktop`'s `MimeType=` key as `x-scheme-handler/<scheme>`: `net-im/zoom/zoom-7.0.0.1666-r2.ebuild:131-135` —
  ```bash
  make_desktop_entry "${EPREFIX}/opt/zoom/ZoomLauncher %U" Zoom \
      videoconference-zoom "Network;VideoConference;" \
      "MimeType=$(printf '%s;' x-scheme-handler/zoommtg x-scheme-handler/zoomus application/x-zoom)"
  ```
  vscode ships a second `.desktop` dedicated to the handler (`code-url-handler.desktop`, `:138`).
* **D-Bus activation** files go to `/usr/share/dbus-1/services`: telegram `:67-68`.
* `metainfo`/AppStream: `insinto /usr/share/metainfo; doins ${FILESDIR}/code.appdata.xml` (vscode `:141-142`).

### 4.4 Interaction with `xdg.eclass`

`xdg_pkg_preinst` snapshots `usr/share/applications`, `usr/share/icons`, `usr/share/mime` **inside `${ED}`** (`xdg.eclass:60-78`). `xdg_pkg_postinst`/`postrm` then run `update-desktop-database`, `gtk-update-icon-cache` and `update-mime-database` **only if the corresponding array is non-empty** (`xdg.eclass:83-100`, `:107-124`).

Practical consequences for an `/opt` repack:
1. Files installed **under `/opt` alone trigger nothing** — the arrays stay empty. You must install the `.desktop` under `/usr/share/applications` and the icons under `/usr/share/icons` (or `/usr/share/pixmaps`, which the icon cache does not index — hence the `-s` loops) for the caches to refresh.
2. Overriding **any** of `pkg_preinst`, `pkg_postinst`, `pkg_postrm` replaces the eclass version. Every exemplar that overrides `pkg_postinst` calls `xdg_pkg_postinst` (5/5). None override `pkg_preinst` — if you must, call `xdg_pkg_preinst` first or postinst becomes a no-op.
3. `xdg-utils`-only ebuilds must do the work by hand in **both** `pkg_postinst` and `pkg_postrm`: `net-im/zoom/zoom-7.0.0.1666-r2.ebuild:151-159` calls `xdg_desktop_database_update` + `xdg_icon_cache_update` in each. Note zoom omits `xdg_mimeinfo_database_update` even though it registers scheme handlers — scheme handlers live in the desktop DB, not the mime DB, so that is correct.
4. `xdg` adds `IDEPEND="dev-util/desktop-file-utils x11-misc/shared-mime-info"` in EAPI 8 (`xdg.eclass:47-50`); do not duplicate those in your own `DEPEND`.

---

## 5. Exact portage QA warning texts and their silencers

All strings copied verbatim from the installed portage on this machine.

| condition | exact emitted text | source | silenced by |
|---|---|---|---|
| Prebuilt ELF already stripped | `QA Notice: Pre-stripped files found:` followed by one path per line | `/usr/lib/portage/*/estrip:552-553` | `QA_PRESTRIPPED` (fnmatch→regex list, `estrip:537-546`), auto-populated from `QA_PREBUILT` (`phase-functions.sh:597-603`). Overridable per-arch as `QA_PRESTRIPPED_${ARCH}`. `QA_STRICT_PRESTRIPPED` in the environment defeats the filter (`estrip:539-540`). |
| Shared library with no `DT_SONAME` | `QA Notice: The following shared libraries lack a SONAME` + file list | `/usr/lib/portage/*/install-qa-check.d/80libraries:41-42` | `QA_SONAME` (`80libraries:17-35`), fed by `QA_PREBUILT`; per-arch `QA_SONAME_${ARCH}`; `QA_STRICT_SONAME` defeats it |
| Shared library with undefined symbols but no `DT_NEEDED` | (same file, second block) log `scanelf-missing-NEEDED.log` | `/usr/lib/portage/*/install-qa-check.d/80libraries:50-73` | `QA_DT_NEEDED` (+`_${ARCH}`), fed by `QA_PREBUILT` |
| Library installed without the `lib*.so.N` compat symlink | `QA Notice: Missing soname symlink(s):` then `\t<link> -> <target>` | `<portage-python>/package/ebuild/doebuild.py:3387-3390` (function `_post_src_install_soname_symlinks`, `:3128-3131`) | `QA_SONAME_NO_SYMLINK` (read from `build-info/QA_SONAME_NO_SYMLINK`, `doebuild.py:3166-3176`); paths matching `QA_PREBUILT` are excluded outright (`doebuild.py:3186-3192`) |
| ELF portage cannot parse | `QA Notice: Unrecognized ELF file(s):` | `doebuild.py:3376-3380` | not silenceable by a `QA_*` var — fix or delete the file |
| Binaries built ignoring CFLAGS | `QA Notice: Files built without respecting CFLAGS have been detected` + `Please include the following list of files in your report:` | `/usr/lib/portage/*/install-qa-check.d/10ignored-flags:60-62` | `QA_FLAGS_IGNORED` (array or space list, `10ignored-flags:10-18,46-49`), fed by `QA_PREBUILT`; `QA_STRICT_FLAGS_IGNORED` defeats it |
| Binaries built ignoring LDFLAGS | `QA Notice: Files built without respecting LDFLAGS have been detected` (same trailer) | `10ignored-flags:88-90` | same `QA_FLAGS_IGNORED` |
| Text relocations | (log `scanelf-textrel.log`) | `install-qa-check.d/10executable-issues:64-73` | `QA_TEXTRELS` / `QA_TEXTRELS_${ARCH}`, fed by `QA_PREBUILT`; note the eclass-independent default `QA_TEXTRELS+=" lib*/modules/*.ko"` (`:70`) |
| Executable stack / WX load segments | (log from `scanelf -qyRAF '%e %p'`) | `install-qa-check.d/10executable-issues:101-114` | `QA_EXECSTACK`, `QA_WX_LOAD` (+`_${ARCH}`), fed by `QA_PREBUILT` |
| `RESTRICT=binchecks` set but ELFs installed | `QA Notice: RESTRICT=binchecks prevented checks on these ELF files:` + list | `/usr/lib/portage/*/misc-functions.sh:232-234` | don't set `RESTRICT=binchecks` — use `QA_PREBUILT` |
| `<stabilize-allarches/>` on a package shipping ELFs | `QA Notice: <stabilize-allarches/> found on package installing ELF files` | `misc-functions.sh:228-230` | remove the tag from `metadata.xml` |
| Invalid `.desktop` | `QA Notice: This package installs one or more .desktop files that do not pass validation.` (wrapped at 72 cols) | `doebuild.py:3405-3408`; validation runs `desktop-file-validate` (`portage/util/_desktop_entry.py:47-50`) | `QA_DESKTOP_FILE` — a whitespace-separated list of **regexes** anchored with `^...$` and matched against the `${ED}`-relative path (`doebuild.py:2864-2888`). Real use: `www-client/google-chrome-beta/google-chrome-beta-154.0.8037.17.ebuild:74`. Hints and a curated `_ignored_errors` list are dropped automatically (`_desktop_entry.py:62-66`). |
| Non-UTF-8 file names | `QA Notice: This package installs one or more file names containing characters that are not encoded with the UTF-8 encoding.` | `doebuild.py:3422-3425` | fix the names |
| Pre-compressed docs in a docompress dir | `QA Notice: One or more compressed files were found in docompress-ed directories. Please fix the ebuild not to install compressed files (manpages, documentation) when automatic compression is used:` | `/usr/lib/portage/*/ecompress:268-271` | `gzip -d` the file in `src_install` (see chrome `:107-108`, opera `:116`) or `docompress -x` |
| Absolute symlink pointing inside `${D}` | `QA Notice: Absolute symlink %s points to %s inside the image directory.\nRemoving the leading %s from its path.` | `<portage-python>/dbapi/vartree.py:4452-4456,5694-5698` | use `dosym -r` or a relative target |
| Dangling symlink | `QA Notice: Symbolic link /%s points to /%s which does not exist.` | `vartree.py:5758-5761` | ensure the target is in `RDEPEND` and really installed |

**Notes.**
* `QA_PREBUILT` accepts fnmatch globs; portage converts `*` → `.*` when feeding the regex-based variables (`phase-functions.sh:596-604`). Writing `QA_PREBUILT="opt/foo/*"` is therefore both a glob and, after translation, a regex — which is why `mongodb-compass` writes `usr/lib/mongodb-compass/.*` and `heroic-bin` writes `.*`; both forms work.
* `QA_PREBUILT` is exported into `build-info` (`phase-functions.sh:725-729`) so the python-side checks (`doebuild.py:3166-3192`) can read it.
* `RESTRICT="strip"` does **not** imply `binchecks`; ELF metadata (`NEEDED.ELF.2`, `PROVIDES`/`REQUIRES` soname deps) is still collected (`misc-functions.sh:205-221`), which is what makes `emerge @preserved-rebuild` work for repacks. Never reach for `RESTRICT=binchecks`.
* `QA_DT_HASH` **does not exist** — zero occurrences in `/var/db/repos/gentoo` and zero in `/usr/lib/portage`.

---

## 6. Anti-patterns observed nowhere in ::gentoo (do not invent them)

* `RESTRICT="binchecks"` on a desktop repack — 0 of 21; it only produces an extra QA notice (`misc-functions.sh:232`).
* `QA_DT_HASH` — 0 tree-wide.
* Hand-rolled `insinto /usr/share/applications; doins x.desktop` — 0 of 21 use it in place of `domenu`.
* Inheriting both `xdg` and `xdg-utils` — forbidden by `@PROVIDES: xdg-utils` (`xdg.eclass:10`).
* Defining `pkg_postinst` without `xdg_pkg_postinst` when `xdg` is inherited — 0 of 5 overriders make that mistake.
* Calling `unpack` on a `.deb` — PMS `unpack` has no `.deb` support; that is the entire reason `unpacker.eclass` exists (`unpacker.eclass:9-12`).

---

## 7. Limits of this survey

* `pkg_postinst` bodies of `bitwarden-desktop-bin` (line 82+), `heroic-bin`, `zotero-bin`, `mattermost-desktop-bin` were not read, so the "5/5 overriders re-call `xdg_pkg_postinst`" count covers only the five I read (slack, element, discord, spotify, vscode).
* `dostrip -x` counts: I confirmed 144 matching ebuild files tree-wide and inspected the first 20 (all source packages); I did not enumerate all 144, so "all 144 are source packages" is an inference, not an observation. The 0/21 count for the exemplar population **is** observed.
* I did not execute `pkgcheck`, `ebuild`, or `emerge` (read-only mandate); no runtime behaviour was exercised.
