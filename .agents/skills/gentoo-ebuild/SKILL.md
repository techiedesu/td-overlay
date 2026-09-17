---
name: gentoo-ebuild
description: Write, fix, and QA the ebuilds in this Gentoo overlay (EAPI 8/9) — dependency atoms, eclasses, prebuilt/.deb repacks, Manifest generation, the pkgcheck/pkgdev loop, the repo's own test entrypoint, and test-merging without breaking the system. Use for any *.ebuild, metadata.xml, Manifest, licenses/, overlay layout, USE-flag, KEYWORDS, or emerge-from-overlay work.
---

# Gentoo ebuilds in this overlay

This skill is tracked in the repo it documents, at `.agents/skills/gentoo-ebuild/`. The repo-root
`AGENTS.md` is a symlink to this file and `CLAUDE.md` a symlink to `AGENTS.md`, so every harness
reads one source of truth. Discovery is project-scoped: it loads only when the session's working
directory is inside the checkout, so work on the overlay from inside it.

Paths below are relative to the repo root; machine-specific locations are always *derived*, never
hardcoded:

```sh
repo_root=$(git rev-parse --show-toplevel)
repo_id=$(cat "${repo_root}"/profiles/repo_name)      # section name in metadata/pkgcheck.conf
installed=$(portageq get_repo_path / "${repo_id}")    # what emerge actually reads
portageq distdir; portageq envvar ACCEPT_LICENSE EMERGE_DEFAULT_OPTS PORTAGE_TMPDIR
```

Deep references (read only the one you need):

- `skill://gentoo-ebuild/references/eapi8-reference.md` — EAPI 8 language rules, variable order, dependency syntax, install-helper table, version comparison. Every rule carries a PMS section or devmanual URL.
- `skill://gentoo-ebuild/references/eclasses-and-exemplars.md` — eclass API matrix (`unpacker`, `desktop`, `xdg`, `pax-utils`, `optfeature`, `linux-info`, `chromium-2`, …) plus 21 real prebuilt-repack ebuilds in `::gentoo`, with observed house-pattern counts and the exact portage QA-notice strings.
- `skill://gentoo-ebuild/references/qa-and-tooling.md` — pkgdev/pkgcheck/ebuild/emerge flag reference, keyword severities, `package.accept_keywords`/`package.license` syntax.

## What this repo is

- A personal binary overlay: `metadata/layout.conf` declares `masters = gentoo`, `thin-manifests = true`, `sign-manifests = false`, plus `eapis-banned`/`eapis-deprecated`. A new category needs no `profiles/categories` file — the master supplies the list.
- Almost every package is an upstream binary repack (`.deb`/tarball) installed under `/opt`. Source packages are the exception.
- The dev checkout and the repo portage reads are **two independent clones**. Edits are invisible to `emerge` until they are committed here and pulled into the installed clone.
- `licenses/` holds license texts for proprietary `LICENSE` values that `::gentoo` does not ship (e.g. `Obsidian-EULA`); without the file `pkgcheck` raises `UnknownLicense`.

## Workflow

1. **Check prior art.** `ls /var/db/repos/*/*/<pkg>` and `pkgcheck scan <atom>` — `guru`, `gentoo-zh` and `pentoo` carry many binary apps. If one has it, decide explicitly: bump theirs or keep ours (highest version across repos wins, so keep the same `${CATEGORY}/${PN}`).
2. **Copy the house pattern.** `app-crypt/keybase-bin` and `app-misc/claude-desktop` are the reference ebuilds: tab indent, `EAPI=8`, `# Copyright 1999-2026 Gentoo Authors`, comments that explain *why* a hack exists, `optfeature` in `pkg_postinst`.
3. **Write the ebuild + `metadata.xml`.** Maintainer is `techiedesu@protonmail.com`. Document every USE flag (`<flag name="...">`); an undocumented flag is reported as `UnknownUseFlags`.
4. **Manifest:** `cd <cat>/<pkg> && pkgdev manifest`. Needs network and fetches *every* `SRC_URI` arch, not just yours — an amd64+arm64 repack downloads both.
5. **Test:** `scripts/test-ebuilds.sh` (see below). Green means every ebuild sources, manifests are complete and deps resolve.
6. **Deploy to the installed clone** (run from the repo root):
   ```sh
   git add <cat>/<pkg> && git commit -m "Add <P>.ebuild"
   installed=$(portageq get_repo_path / "$(cat profiles/repo_name)")
   git -C "${installed}" status --porcelain     # check first: it may hold untracked local ebuilds
   sudo git -C "${installed}" pull "$(pwd)" master
   ```
   Never `git clean` the installed clone, and `reset --hard` it only after reading its status.
7. **Keyword/USE:** `-*`-keyworded packages need `/etc/portage/package.accept_keywords` entries (`<cat>/<pkg> ~amd64`); USE flags go in `/etc/portage/package.use`. A proprietary `LICENSE` also needs `/etc/portage/package.license` unless `ACCEPT_LICENSE` already accepts it (`portageq envvar ACCEPT_LICENSE`).
8. **Merge and verify:** `sudo emerge --ask=n --usepkg=n --getbinpkg=n --verbose <atom>`, then the checks in the last section.

## Tests

| Command | What it gates |
| --- | --- |
| `scripts/test-ebuilds.sh` | bash syntax of every ebuild/eclass/script, then `pkgcheck scan --exit error` over the whole repo |
| `scripts/test-ebuilds.sh --syntax-only` | syntax gate alone — no Gentoo tooling required, used by the CI job that runs on plain Ubuntu |
| `scripts/test-ebuilds.sh <atom> …` | extra arguments go straight to `pkgcheck scan` |
| `.github/workflows/pkgcheck.yml` | same two gates in CI; the scan job runs `pkgcore/pkgcheck-action@v1`, which executes `pkgcheck ci --exit GentooCI` in the upstream container and syncs `::gentoo` first |

Error-level results fail the run; warning/style/info results are printed and do not. Repo-wide QA
policy lives in `metadata/pkgcheck.conf` (INI, section = repo id, keys = `pkgcheck scan` long
options — values must stay on one line, continuations end up inside the value). Two keywords are
disabled there, both with reasons in the file: `NonsolvableDepsInDev` (prebuilt glibc-linked
binaries can never satisfy the musl dev profiles; the stable-profile variant stays on) and
`RedundantVersion` (old channel versions are deliberate symlinks to the newest real ebuild).
`pkgcheck scan --config false` shows what the policy suppresses.

When adding a package, prefer fixing the ebuild over widening that policy.

## Traps

- Check `portageq envvar EMERGE_DEFAULT_OPTS` before merging. If it contains `-a`/`--ask`, `emerge` aborts outside a terminal unless you pass `--ask=n`. If it contains `--getbinpkg`, **binary-package reuse survives `--usepkg=n`**: a stale `/var/cache/binpkgs/<cat>/<pkg>/*.gpkg.tar` for the same CPV is merged silently and your ebuild edits look like no-ops. Iterating without a version bump: `--usepkg=n --getbinpkg=n`, and delete the stale gpkg.
- `ebuild <file> install` as an unprivileged user dies at `fowners`/`fperms`. Inspect `${D}` with `sudo env PORTAGE_TMPDIR=<scratch> ebuild <file> clean install`.
- `<<-EOF` strips leading **tabs only**. A script generated from a tab-indented ebuild comes out flush-left; indent the script body with spaces after the stripped tabs.
- A USE dependency on a flag that older versions of the target lack → `MissingUseDepDefault`. Use `[flag(+)]` when those versions behaved as if enabled (e.g. `sys-firmware/edk2-bin[qemu_softmmu_targets_x86_64(+)]`: ≤202411 installed OVMF unconditionally), `[flag(-)]` when as if disabled.
- `EAPI`: `::gentoo` bans 0–6 and deprecates 7, and `skel.ebuild` is already `EAPI=9`. Write `EAPI=8` unless a 9-only feature is needed. `eapis-banned`/`eapis-deprecated` are **not** inherited from `masters`, which is why this repo declares them itself — without them a deliberate `EAPI=7` ebuild scans clean.
- `pkgcheck` header checks (`InvalidCopyright`, `InvalidLicenseHeader`) come from `_HeaderCheck(GentooRepoCheck)` (`pkgcheck/checks/header.py:93`), so **they never run outside `::gentoo`** — the header is on you. The regex `^# Copyright (\d{4}-)?\d{4} .+$` accepts both `2026` and `1999-2026`; `::gentoo`'s `header.txt` uses the single year, this repo uses the range.

## What pkgcheck will not catch (self-enforce)

Measured against a deliberately broken scratch ebuild:

| Reported | Silent |
| --- | --- |
| `VariableOrderWrong` (LICENSE before SLOT, KEYWORDS before IUSE), `UnknownKeywords`, `UnknownUseFlags`, `MissingManifest`, `UnknownLicense`, `StaticSrcUri`, `HomepageInSrcUri`, `AbsoluteSymlink`, `UnusedInherits`, `MissingUseDepDefault`, `MissingPythonEclass` | copyright/license header (`::gentoo`-only), `MissingSlotDep` |

`MissingSlotDep` fires only when the slotless atom is in **both** `DEPEND` and `RDEPEND`, and it
resolves candidate slots via `pkg.repo.itermatch` (`pkgcheck/checks/metadata.py:858-870`) — in an
overlay the dependency lives in `::gentoo`, not here, so it stays silent even for genuinely
multi-slot targets such as `x11-libs/gtk+` (`:2`, `:3`). Slot correctness is a manual review item.

## Prebuilt / .deb repack recipe

The dominant case here. Worked example: `app-misc/claude-desktop`, which repacks Anthropic's
official `.deb`.

```bash
inherit desktop linux-info optfeature pax-utils unpacker xdg   # unpacker EXPORT_FUNCTIONS src_unpack → .deb handled
S="${WORKDIR}"                      # deb payload unpacks to ./usr/...
LICENSE="all-rights-reserved"       # proprietary and non-redistributable; ::gentoo ships this name
KEYWORDS="-* ~amd64"                # -* because there is nothing to build for other arches
RESTRICT="bindist mirror strip test"
QA_PREBUILT="opt/${PN}/*"           # appended to QA_EXECSTACK/TEXTRELS/WX_LOAD and, as regex,
                                    # QA_DT_NEEDED/FLAGS_IGNORED/PRESTRIPPED/SONAME{,_NO_SYMLINK}
                                    # (portage's phase-functions.sh:585-607)
CONFIG_CHECK="~USER_NS"             # '~' = warn only (linux-info.eclass:68); Electron sandbox
```

Rules that keep such a package honest:

1. **Derive `RDEPEND` from the binaries, not from the Debian `Depends:`.** For every shipped ELF:
   ```sh
   objdump -p <file> | awk '/NEEDED/{print $2}'                         # hard links
   strings -a <file> | grep -E '^lib[A-Za-z0-9_+.-]+\.so(\.[0-9]+)*$'   # dlopen'd sonames
   ```
   Map sonames → atoms (`libgbm.so.1` → `media-libs/mesa[gbm(+)]`, `libsecret-1.so.0` → `app-crypt/libsecret[crypt]`, `libudev.so.1` → `virtual/libudev`, `libEGL.so.1` → `media-libs/libglvnd`). Anything `dlopen`ed and optional belongs behind a USE flag or `optfeature`, not in the hard set. Do not add `sys-libs/glibc`: it is implicit, and it is what makes `NonsolvableDepsInDev` fire on musl profiles.
2. **Drop Debian-only payload** in `src_prepare`: `usr/share/lintian`, apt sources/keyrings, AppArmor profiles, maintainer scripts, and the vendor's `/usr/bin` symlink when you install elsewhere. Reinstall `usr/share/doc/<pkg>/copyright` with `dodoc`.
3. **Install to `/opt/${PN}`**; for a multi-hundred-MB tree `dodir /opt && mv usr/lib/<pkg> "${ED}${DESTDIR}"` beats `doins -r` — a rename inside one filesystem instead of a full copy.
4. **Electron specifics:** `fowners root:root` + `fperms 4755` on `chrome-sandbox`; `pax-mark m` the main binary; wrap `/usr/bin/<pkg>` with a launcher that adds `--ozone-platform-hint=auto` when `WAYLAND_DISPLAY` is set (Chromium defaults to X11, i.e. XWayland) and expose an env var to opt out.
5. **Rewrite absolute paths** the upstream package baked in for its own prefix — D-Bus `.service` `Exec=`, systemd units, wrapper scripts. Find them with `grep -rlI '/usr/lib/<pkg>' .`.
6. **Desktop integration:** `domenu usr/share/applications/*.desktop`, `insinto /usr/share/icons && doins -r usr/share/icons/hicolor`. Keep the upstream `.desktop` basename when it matches the Wayland `app_id`/`StartupWMClass`, otherwise docks show a second generic icon.
7. A hand-written `pkg_postinst` **must** call `xdg_pkg_postinst`: `xdg.eclass` exports that phase and your definition replaces it.

## Verification before yielding

```sh
scripts/test-ebuilds.sh                          # syntax + pkgcheck, error-level clean
sudo emerge --ask=n --usepkg=n --getbinpkg=n -v <atom>
qlist -Iv <cat>/<pkg>; qlist <cat>/<pkg> | wc -l
stat -c '%A %U:%G %n' /opt/<pkg>/chrome-sandbox   # -rwsr-xr-x root:root when setuid was intended
ldd /opt/<pkg>/<binary> | grep 'not found' || echo resolved
readlink -e <symlink the ebuild created>          # non-empty = target exists
```

GUI package → launch it and look. Electron/Chromium logs land in `~/.config/<App>/logs/main.log`,
and `ps -eo args | grep <pkg>` shows whether the GPU process really got `--ozone-platform=wayland`.
On a Wayland session capture the window with the compositor's own tool (`spectacle -fbn -o <file>`
on KDE, `grim` on wlroots); X11 tools such as `import` or `xdotool` only see XWayland clients.
