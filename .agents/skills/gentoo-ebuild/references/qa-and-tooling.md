# QA / tooling loop for personal-overlay ebuilds on this machine

All commands are copy-pasteable. `[user]` = runs as `td` (uid 1000, groups include `portage`, `wheel`). `[root]` = needs `sudo`.
Everything below was executed or read on this box on 2026-09-17 unless marked `[INFERENCE]`.

---

## 1. Overlay topology — what is where, and what talks to what

### 1.1 The dev checkout is NOT the installed repo

```
[user] stat -c '%d:%i %n' <repo> <installed-repo>
36:123948693 <repo>
36:98798467  <installed-repo>          # different inodes -> not a symlink, not a bind mount

[user] git -C <repo> remote -v
origin  git@github.com:techiedesu/td-overlay.git (fetch/push)
[user] git -C <installed-repo> remote -v
origin  https://github.com/techiedesu/td-overlay.git (fetch/push)

[user] git -C <repo> log -1 --format='%h %s'   -> 348bce2 keybase-bin: fix window icon on KDE/Wayland (-r1)
[user] git -C <installed-repo>     log -1 --format='%h %s'   -> 348bce2 (same commit)
```

They are **two independent clones of the same GitHub repo**, not linked on disk.
Portage's view is fixed by `/etc/portage/repos.conf/eselect-repo.conf`:

```ini
[td]
location = <installed-repo>
sync-type = git
sync-uri = https://github.com/techiedesu/td-overlay.git
```

```
[user] portageq get_repos /            -> vapoursynth td pentoo mv guru gentoo-zh gentoo
[user] portageq get_repo_path / td     -> <installed-repo>
```

**Consequence:** an ebuild written in `~/dev/td-overlay` is invisible to `emerge` until it is
committed+pushed and `<installed-repo>` is synced. Three ways to close the loop:

| goal | command | root? |
|---|---|---|
| QA the dev checkout | `pkgcheck scan -r <repo> <atom>` (`-r .` from inside) | no |
| install from dev checkout without pushing | add a temporary `repos.conf` entry whose `location` is the dev checkout (or copy the package dir into `<installed-repo>`) | yes (writes `/etc/portage`) |
| normal path | `git push` then `emerge --sync td` | yes |

### 1.2 ⚠ The installed clone is currently dirty (real hygiene trap)

```
[user] git -C <installed-repo> status --porcelain
 M net-im/discord-canary/Manifest
?? net-im/discord-canary/discord-canary-1.0.1886.ebuild
```

Somebody ran `scripts/create-discord-canary-new-release.sh` **inside `<installed-repo>`** instead of the
dev checkout: version 1.0.1886 exists only there (`pkgdev showkw -r td net-im/discord-canary` lists
`1.0.1886`, the dev checkout stops at `1.0.1884`). The next `emerge --sync td` will hit a dirty tree.
Rule for the skill: **author in `~/dev/td-overlay`, never in `<installed-repo>`.**

### 1.3 `metadata/layout.conf`

`<repo>/metadata/layout.conf` lines 1-3, in full:

```ini
masters = gentoo
thin-manifests = true
sign-manifests = false
```

| key | meaning | value here / default |
|---|---|---|
| `masters` | repos whose eclasses, `licenses/`, `profiles/categories`, arch list, profiles this repo inherits; also a hard dependency | `gentoo`. cf. `/var/db/repos/gentoo/metadata/layout.conf:55` `masters =` (empty = the master itself), `/var/db/repos/guru/metadata/layout.conf:1`, `/var/db/repos/gentoo-zh/metadata/layout.conf:1` |
| `thin-manifests` | `true` ⇒ Manifest contains **only `DIST` lines** (no `EBUILD`/`AUX`/`MISC` checksums) — required for git repos | `true`; cf. `gentoo/metadata/layout.conf:58` |
| `sign-manifests` | GPG-sign Manifests | `false`; gentoo signs commits instead (`gentoo/metadata/layout.conf:61-62`) |
| `manifest-hashes` | hash set for new Manifest entries | **unset** in ::td ⇒ portage default, which matches gentoo's `BLAKE2B SHA512` (`gentoo/metadata/layout.conf:14`). Verified: `app-crypt/keybase-bin/Manifest` carries exactly `DIST <file> <size> BLAKE2B … SHA512 …` |
| `cache-formats` | `pms` (old) or `md5-dict`; "Default is to detect dirs" (`man 5 portage`, layout.conf section) | **unset** in ::td; `metadata/md5-cache/` exists ⇒ md5-dict auto-detected. gentoo sets it explicitly (`gentoo/metadata/layout.conf:50`) |
| `profile-formats` | `pms`/`portage-1`/`portage-2`/… controls what profile files may be dirs; "Use portage-2 if you're unsure. The default is portage-1-compat mode" (`man 5 portage`) | **unset**; irrelevant until the overlay ships profiles |
| `eapis-banned` / `eapis-deprecated` | pkgcheck `BannedEapi`(error)/`DeprecatedEapi`(warning) source | unset in ::td. Gentoo: `eapis-banned = 0 1 2 3 4 5 6`, `eapis-deprecated = 7` (`gentoo/metadata/layout.conf:32-33`) ⇒ **EAPI 8** is the only non-flagged choice |
| `use-manifests` | `strict`/`true`/`false` (`man 5 portage`) | unset ⇒ default `strict`-ish enforcement by portage |

Other house files: `.editorconfig` (`[*.ebuild] indent_style = tab`, `end_of_line = lf`, `insert_final_newline = true`),
`.gitignore` (`metadata/md5-cache/**/`, `logs/*`, `!logs/.keep`), `README.md` (documents exactly one post-creation step: `pkgdev manifest`).

### 1.4 `profiles/`

`<repo>/profiles/` contains **only** `repo_name` (`td`) and `eapi` (`8`).
For comparison: `[gentoo] arch arches.desc arch.list base categories default desc eapi … `,
`[guru] categories eapi license_groups package.mask package.use.mask repo_name thirdpartymirrors updates use.desc use.local.desc`,
`[gentoo-zh] eapi license_groups package.mask repo_name updates`.

**Is `profiles/categories` needed for a new category?** Only if the category does not exist in a master.

```
[user] grep -nx 'app-misc' /var/db/repos/gentoo/profiles/categories   -> 23:app-misc
[user] grep -nx 'dev-db'   /var/db/repos/gentoo/profiles/categories   -> 36:dev-db
```

`app-misc` is inherited from `masters = gentoo` ⇒ **`app-misc/claude-desktop` needs no `profiles/categories`**.
Guru's file only lists categories gentoo lacks (`/var/db/repos/guru/profiles/categories:1-5` = `app-voices dev-crystal dev-elixir dev-hare dev-nim`) — that is the pattern to copy when inventing a category.
The relevant pkgcheck keyword is `UnknownCategoryDirs` (level: warning).

### 1.5 `metadata/md5-cache` — needed? committed?

```
[user] git -C <repo> ls-files metadata/
metadata/layout.conf
[user] git -C <repo> ls-files metadata/md5-cache | wc -l   -> 0
```

Not tracked (`.gitignore`, plus house commit `Untrack generated md5-cache file`). It is a **speed cache only**:
each entry ends with validation fields, e.g. `<repo>/metadata/md5-cache/net-im/discord-0.0.40`:

```
_eclasses_=toolchain-funcs	58a918e3…	linux-info	efd92365…	chromium-2	6be3cf19…	…
_md5_=30e58e4f3ee4498518f2b1d5915b41c5
```

A stale entry is detected by the `_md5_`/`_eclasses_` mismatch and portage falls back to sourcing the ebuild,
so **you never have to regenerate it by hand** for correctness. To regenerate anyway:

```bash
[user] egencache --repo=td --update --jobs=8            # writes metadata/md5-cache in the repo of that id
[root] egencache --repo=td --update --jobs=8            # needed if the repo dir is not writable by you
[user] egencache --update --jobs=8 \
         --repositories-configuration "$(printf '[td]\nlocation = <repo>\n')" --repo=td
```
(`egencache --help`: `--update  update metadata/md5-cache/ (generate as necessary)`, `--repo REPO  name of repo to operate on`,
`--repositories-configuration  override configuration of repositories (in format of repos.conf)`, `--jobs`, `--load-average`, `--tolerant`, `--update-pkg-desc-index`, `--update-manifests`, `--write-timestamp`.)

Note: `emerge --regen` is the portage-side equivalent mentioned by `man 5 portage` for repos that ship no pregenerated cache.

---

## 2. pkgdev 0.2.18 — exact flags (from `pkgdev <cmd> --help` on this box)

| command | writes? | network? | notes |
|---|---|---|---|
| `pkgdev manifest [target…]` | **yes**: `Manifest` + downloads into DISTDIR | **yes** (fetches every `SRC_URI`) | flags: `-d/--distdir DISTDIR`, `-f/--force` (forcibly remanifest), `-m/--mirrors` (allow Gentoo mirrors), `--if-modified` (only packages with uncommitted modifications), `--ignore-fetch-restricted`, `-q`, `-v` |
| `pkgdev commit` | **yes**: git index + commit, and rewrites file headers (`--mangle`) | no (unless `-b/--bug` lookups) | `-s/--scan [BOOLEAN]` run pkgcheck against staged changes, `-A/--ask` confirm on QA errors, `-n/--dry-run`, `-u/--update` (stage changed), `-a/--all` (stage changed/new/removed), `-m/--message`, `-M/--message-template FILE`, `-e/--edit`, `-b/--bug`, `-c/--closes`, `-T/--tag NAME:VALUE`, `--signoff`, `--gpg-sign/--no-gpg-sign`, `-d/--distdir` |
| `pkgdev showkw [target…]` | no | no | `-r/--repo REPO` (id or path), `-f/--format`, `-c/--collapse`, `-s/--stable`, `-u/--unstable`, `-o/--only-unstable`, `-p/--prefix`, `-a/--arch` |
| `pkgdev push` | **yes** (pushes) | yes | `-A/--ask`, `-n/--dry-run`, `--pull` (git pull --rebase first) |
| `pkgdev bugs` | **yes** (files Bugzilla bugs) | yes | `--api-key`, `-s/--stablereq`, `-k/--keywording`, `--commits`, `--staged`, `--dot`, `--edit-graph`, `--auto-cc-arches`, `--find-by-maintainer`, `--blocks`, `--stabletime` — **irrelevant for a personal overlay** |
| `pkgdev mask [TARGET…]` | **yes**: edits `profiles/package.mask` | only with `--file-bug`/`--email` | `-r/--rites [DAYS]` (last rites), `-b/--bug`, `--email`, `--file-bug`. Requires `profiles/package.mask` to exist in the repo |

Real runs on the clean dev checkout:

```
[user] cd <repo> && pkgdev manifest --if-modified
manifests are up to date
exit=0                              # no writes, no fetches when nothing is modified

[user] pkgdev showkw --color n -r td app-crypt/keybase-bin
keywords for app-crypt/keybase-bin:
          a a   a   l       p r   s
          l m   r h o m m   p i s p   e s r
          p d a m p o 6 i p c s 3 a x a l e
          h 6 r 6 p n 8 p p 6 c 9 r 8 p o p
          a 4 m 4 a g k s c 4 v 0 c 6 i t o
--------------------------------------------
 6.6.3-r1 * ~ * * * * * * * * * * * * 8 0 td
                                      ^ ^ ^--- repo
                                      | +------ SLOT
                                      +-------- EAPI
# legend: '*' = arch listed as -* , '~' = ~arch, '+' = stable, 'o' = not keyworded

[user] pkgdev commit --color n -n          # on a clean tree
pkgdev commit: error: no staged changes exist
```

Config file (INI, `key = value` with `<subcommand>.<long-option>` keys) is read from
`/etc/pkgdev/pkgdev.conf`, `${XDG_CONFIG_HOME}/pkgdev/pkgdev.conf`, `~/.config/pkgdev/pkgdev.conf`, `--config FILE`.
Useful house setting (`man pkgdev`):

```ini
[DEFAULT]
commit.scan = true
commit.ask = true
```

---

## 3. pkgcheck 0.10.43 — scanning an overlay

### 3.1 Invocations

```bash
[user] pkgcheck scan -r <repo> app-crypt/keybase-bin   # repo by path
[user] cd <repo> && pkgcheck scan app-misc/claude-desktop
[user] pkgcheck scan -r td app-crypt/keybase-bin                        # repo by id from repos.conf
[user] pkgcheck scan -r . -f latest net-im/discord-canary               # only newest version per slot
[user] pkgcheck scan -r . -k UnknownLicense,MissingManifest,VariableOrderWrong
[user] pkgcheck scan -r . -c SrcUriCheck,MetadataVarCheck
[user] pkgcheck scan -r . -s ver,pkg                                    # scopes: git profiles eclass repo cat pkg ver
[user] pkgcheck scan -r . --net app-misc/claude-desktop                 # NETWORK: validates SRC_URI/HOMEPAGE reachability
[user] pkgcheck scan --commits                                          # targets = unpushed commits
[user] pkgcheck scan --staged                                           # targets = staged changes
[user] pkgcheck scan -r . -R StrReporter  net-im/discord-canary
[user] pkgcheck scan -r . -R JsonStream   net-im/discord-canary | jq .
[user] pkgcheck scan -r . --exit=error app-misc/claude-desktop          # exit 1 if any error-level result
```

`-R/--reporter` values (`pkgcheck show --reporters`): `CsvReporter FancyReporter FlycheckReporter FormatReporter JsonReporter JsonStream StrReporter XmlReporter` (default = Fancy).
`--format FORMAT_STR` pairs with `FormatReporter`. Other useful switches: `-j/--jobs`, `--cache/--cache-dir`, `--sandbox BOOLEAN`, `-a/--arches`, `-p/--profiles`, `--timeout`, `-C/--checksets`, `--filter` (`-f latest`), `--reset-caching-per {version,package,category}`.

**`--exit` gotcha (measured):**

```
[user] pkgcheck scan --color n -r . --exit app-office/obsidian
pkgcheck scan: error: argument --exit: unknown checkset, check, or keyword: 'app-office/obsidian'   exit=2
[user] pkgcheck scan --color n -r . app-office/obsidian --exit          -> exit=1   # bare --exit must be last
[user] pkgcheck scan --color n -r . --exit=error app-office/obsidian    -> exit=1
[user] pkgcheck scan --color n -r . --exit=warning,style app-office/obsidian -> exit=1
[user] pkgcheck scan --color n -r . --exit=UnknownLicense app-office/obsidian -> exit=1
```

Without `--exit`, **pkgcheck exits 0 even when it reports errors** — CI/scripts must pass `--exit=error`.

### 3.2 Real scan output from this machine

```
$ pkgcheck scan -r <repo> app-crypt/keybase-bin
exit=0
                         # <- no output at all: the house .deb repack is 100% clean

$ pkgcheck scan --color n -r . app-office/obsidian
app-office/obsidian
  MissingRemoteId: missing <remote-id type="github">obsidianmd/obsidian-releases</remote-id> (inferred from URI 'https://github.com/obsidianmd/obsidian-releases/releases/download/v1.3.7/obsidian_1.3.7_amd64.deb')
  BadDescription: version 1.3.7: DESCRIPTION="A second brain, for you, forever." ends with a full stop
  DoubleEmptyLine: version 1.3.7: ebuild has unneeded empty line on line: 113
  NonsolvableDepsInDev: version 1.3.7: nonsolvable depset(rdepend) keyword(~amd64) dev profile (default/linux/amd64/23.0/musl) (12 total): solutions: [ sys-libs/glibc ]
  UnknownLicense: version 1.3.7: unknown license: Obsidian-EULA
  VariableOrderWrong: version 1.3.7: variable LICENSE should occur before RESTRICT
  VariableOrderWrong: version 1.3.7: variable S should occur before IUSE
  WhitespaceFound: version 1.3.7: ebuild has trailing whitespace on line: 191
exit=0

$ pkgcheck scan --color n -r . -f latest net-im/discord-canary
net-im/discord-canary
  NonsolvableDepsInDev: version 1.0.1884: nonsolvable depset(rdepend) keyword(amd64) dev profile (default/linux/amd64/23.0/musl) (12 total): solutions: [ sys-libs/glibc ]
  VariableOrderWrong: version 1.0.1884: variable IUSE should occur before RESTRICT
  VariableOrderWrong: version 1.0.1884: variable S should occur before IUSE
exit=0

$ pkgcheck scan --color n -r . -R StrReporter net-im/discord-canary | head -3
net-im/discord-canary-0.0.251: nonsolvable depset(rdepend) keyword(amd64) dev profile (default/linux/amd64/23.0/musl) (12 total): solutions: [ sys-libs/glibc ]
net-im/discord-canary-0.0.251: slot(0) keywords are overshadowed by versions: 0.0.253, 0.0.255, …
net-im/discord-canary-0.0.251: variable IUSE should occur before RESTRICT

$ pkgcheck scan --color n -r . -R JsonStream net-im/discord-canary | head -1
{"__class__": "NonsolvableDepsInDev", "category": "net-im", "package": "discord-canary", "version": "0.0.251", "attr": "rdepend", "keyword": "amd64", "profile": "default/linux/amd64/23.0/musl", "deps": ["sys-libs/glibc"], "profile_status": "dev", "profile_deprecated": false, "num_profiles": 12}

$ pkgcheck scan --color n -r . --exit=UnknownLicense app-office/obsidian >/dev/null ; echo $?
1
```

Whole-repo scan of ::td also produced, for other packages:
`UnknownRestrict: version 0.2.57: unknown RESTRICT="network-sandbox"` (dev-util/act),
`NonexistentDeps: … >=dev-qt/qtcore-5.2.0:5 …` and `UnusedInherits: version 9999: unused eclass: qmake-utils` (x11-apps/ocs-url),
`RedundantVersion: version 0.0.251: slot(0) keywords are overshadowed by versions: …` (net-im/discord-canary).

### 3.3 Keywords an overlay author actually trips, with severity (`man 1 pkgcheck`, `o level:` field)

| keyword | level | fires on | personal-overlay verdict |
|---|---|---|---|
| `MissingManifest` | error | `SRC_URI` targets missing from Manifest | **must fix** → `pkgdev manifest` |
| `InvalidManifest` / `UnknownManifest` / `UnnecessaryManifest` | error / warning / warning | Manifest vs files mismatch (`UnnecessaryManifest` = non-DIST entries under thin-manifests) | must fix |
| `UnknownLicense` | error | "License usage with no matching license file" | **must fix** → ship `licenses/<NAME>` (§5) |
| `MissingLicense` | error | `LICENSE` empty | must fix |
| `MissingLicenseRestricts` | warning | restrictive license without matching `RESTRICT` | fix: `RESTRICT="bindist mirror"` on proprietary repacks |
| `UnknownKeywords` | error | typo'd/unknown arch token | must fix |
| `UnsortedKeywords` / `DuplicateKeywords` / `OverlappingKeywords` | style | `KEYWORDS` hygiene. `-* ~amd64` is correctly ordered | fix (cheap) |
| `BannedEapi` / `DeprecatedEapi` | error / warning | from master's `eapis-banned`/`eapis-deprecated` | use `EAPI=8` and it never fires |
| `MissingEAPIBlankLine` | style | no blank line after `EAPI=8` | fix (cheap) |
| `VariableOrderWrong` | style | order must follow `skel.ebuild`: `DESCRIPTION HOMEPAGE SRC_URI S LICENSE SLOT KEYWORDS IUSE RESTRICT` | fix; the house discord/obsidian ebuilds all trip it |
| `MissingSlotDep` | warning | dep on a multi-slot package without `:slot` | fix (e.g. `dev-libs/glib:2`, `x11-libs/gtk+:3`) |
| `HomepageInSrcUri` | style | `${HOMEPAGE}` used inside `SRC_URI` | fix |
| `StaticSrcUri` | style | literal version in `SRC_URI` instead of `${P}`/`${PV}` | fix |
| `RedundantUriRename` | style | `-> ${P}.tar.gz` when the name is already that | fix |
| `BadFilename` | warning | non-disambiguated distfile name (`v1.2.3.deb`) | fix with `-> ${P}-amd64.deb` |
| `UnstableSrcUri` | warning | URI not guaranteed stable | judgement |
| `UnusedInherits` / `MissingInherits` / `IndirectInherits` | warning | eclass hygiene | must fix |
| `NonexistentDeps` | warning | dep atom matches nothing in any repo | must fix (usually a typo or removed package) |
| `NonsolvableDepsInDev` / `NonsolvableDepsInStable` | error | dep unsolvable on some profile | **expected noise here**: every ::td binary package trips `NonsolvableDepsInDev … default/linux/amd64/23.0/musl … solutions: [ sys-libs/glibc ]` because glibc-only prebuilts can't resolve on musl profiles. Ignorable for a personal overlay; silence with `-p -musl` / a `metadata/pkgcheck.conf` `[td] arches = amd64` |
| `RedundantVersion` | info | older version overshadowed in the same slot | ignorable (expected when keeping old discord-canary ebuilds) |
| `MissingRemoteId` | info | no `<remote-id>` in metadata.xml for a github/pypi URI | nice-to-have |
| `BadDescription` | style | ends with `.`, too long, starts with the package name | fix |
| `WhitespaceFound` / `DoubleEmptyLine` / `TrailingEmptyLine` / `NoFinalNewline` / `WrongIndentFound` | style | whitespace; `.editorconfig` already enforces tabs + final newline | fix |
| `MissingPackageRevision` | warning | `=cat/pkg-1.2` without `-r0` | fix |
| `UnknownRestrict` | warning | `RESTRICT` token not in master's `restrict-allowed` (`gentoo/metadata/layout.conf:9`) | fix |
| `PkgMissingMetadataXml` | error | **measured: does NOT fire in ::td** — `pkgcheck scan -r . -c PackageMetadataXmlCheck net-im/discord` (which has no metadata.xml) produced no output, exit 0 | optional in an overlay; the house keybase-bin still ships one |
| `StableRequest` | info | n/a with `-*` keywords | never fires |

**Checks that never fire outside ::gentoo** (`man 1 pkgcheck`, "o Gentoo repo specific") — do not chase them, and do not expect them to catch header mistakes in ::td:
`EbuildHeaderCheck, EbuildIncorrectCopyright, EbuildInvalidCopyright, EbuildInvalidLicenseHeader, EbuildNonGentooAuthorsCopyright, EbuildOldGentooCopyright, EclassHeaderCheck, Eclass*Copyright/LicenseHeader, IncorrectCopyright, InvalidCopyright, InvalidLicenseHeader, NonGentooAuthorsCopyright, OldGentooCopyright, BadCommitSummary, InvalidCommitMessage, InvalidCommitTag, MissingSignOff, EmptyCategoryDir, EmptyPackageDir, EmptyDirsCheck, BinaryFile, DirectStableKeywords, DroppedStableKeywords, DroppedUnstableKeywords, EAPIChangeWithoutRevbump, LiveOnlyPackage, MissingMove, MissingSlotmove, NewerEAPIAvailable, NonsolvableDeps(check), StableRequest(check), UnquotedVariable, UnstableOnly, UseFlagWithoutDeps, VulnerablePackage, PythonMismatchedPackageName, RequiredUseUnsatisfiable, SrcUriChecksumChange, SuspiciousSrcUriChange, RdependChange, GlsaCheck, AcctCheck`.
(The two-line `# Copyright 1999-2026 Gentoo Authors` / `# Distributed under the terms of the GNU General Public License v2` header is therefore **house convention**, present in every ::td ebuild, not something pkgcheck will enforce here.)

Per-repo suppression without touching the command line — `metadata/pkgcheck.conf` inside the repo (read only when cwd is inside the repo or `-r` is given):

```ini
[DEFAULT]
keywords = -info
[td]
arches = amd64
checks = -RedundantVersionCheck
```

---

## 4. Test-install loop without polluting the system

### 4.1 Filesystem facts that decide "root or not"

```
[user] portageq envvar DISTDIR PORTAGE_TMPDIR PKGDIR
/var/cache/distfiles ; /var/tmp ; /var/cache/binpkgs
[user] stat -c '%u:%g %a %n' /var/cache/distfiles /var/tmp/portage
0:250 775 /var/cache/distfiles          # root:portage, group-writable
250:250 775 /var/tmp/portage            # portage:portage, group-writable
[user] stat -c '%U:%G %a %n' /var/db/pkg /var/cache/binpkgs
root:root 755 /var/db/pkg               # only root may merge
root:root 755 /var/cache/binpkgs
[user] id -> uid=1000(td) … 250(portage) …
[user] portageq envvar FEATURES | tr ' ' '\n' | grep -E 'sandbox|userpriv|buildpkg'
buildpkg  ipc-sandbox  network-sandbox  pid-sandbox  sandbox  userpriv  usersandbox
```

### 4.2 `ebuild` phases (`man 1 ebuild`, English text quoted verbatim)

```bash
cd <repo>/app-misc/claude-desktop
[user] ebuild claude-desktop-1.2.3.ebuild manifest   # "Updates the manifest file for the package." writes Manifest + fetches to DISTDIR
[user] ebuild claude-desktop-1.2.3.ebuild clean      # "Cleans the temporary build directory" ($PORTAGE_TMPDIR)
[user] ebuild claude-desktop-1.2.3.ebuild unpack     # runs src_unpack into ${WORKDIR}
[user] ebuild claude-desktop-1.2.3.ebuild prepare    # src_prepare, cwd=${S}
[user] ebuild claude-desktop-1.2.3.ebuild install    # src_install -> …/image, i.e. ${ED}
[root] ebuild claude-desktop-1.2.3.ebuild qmerge     # "installs all the files in the install directory to the live filesystem" + pkg_preinst/pkg_postinst + writes /var/db/pkg/…/CONTENTS
[root] ebuild claude-desktop-1.2.3.ebuild merge      # fetch+unpack+compile+install+qmerge in one go
[root] ebuild claude-desktop-1.2.3.ebuild unmerge
[user] ebuild claude-desktop-1.2.3.ebuild package    # like merge but stops after producing a binpkg in PKGDIR (PKGDIR is root-owned here -> [root])
```

Default behaviour: "portage executes all functions in order up to the one you specify … If you want to ensure that they are all run, you need to use the `clean` command first. If you want only a single command to run, add `noauto` to FEATURES."
The fetch phase needs network; `manifest`/`digest` are equivalent; `ebuild --force` "forces regeneration of digests for all distfiles"; `--skip-manifest` skips manifest checks.

`ebuild --help` options: `--force`, `--color {y,n}`, `--debug`, `--version`, `--ignore-default-opts`, `--skip-manifest`.

**Root matrix** [INFERENCE from the ownership/FEATURES facts above; the phases themselves were not executed under the read-only constraint]:
`manifest/clean/unpack/prepare/install` write only `$PORTAGE_TMPDIR/portage` (775, group `portage`) and `DISTDIR` (775, group `portage`), both group-writable for `td` ⇒ **no root**.
`qmerge`/`merge`/`unmerge`/`package` write `/var/db/pkg`, `/`, `/var/cache/binpkgs` (root:root 755) ⇒ **root**.

### 4.3 `ebuild … merge` vs `emerge`

`ebuild … merge` runs *only that one ebuild's* phases: no dependency resolution, no keyword/license/mask checks, no world file, no news. `emerge` resolves and merges dependencies, applies `ACCEPT_KEYWORDS`/`ACCEPT_LICENSE`/masks, records the package in `@world` (unless `--oneshot`), and honours `EMERGE_DEFAULT_OPTS`. Use `ebuild` to iterate on `src_*` phases fast; use `emerge` for the final acceptance test.

### 4.4 `emerge` from the overlay

```bash
[user] emerge --pretend --verbose app-misc/claude-desktop          # or -pv ; works unprivileged
[user] emerge -pv --color=n --ignore-default-opts app-crypt/keybase-bin
[root] emerge --ask --verbose app-misc/claude-desktop
[root] emerge --ask --verbose --autounmask=y app-misc/claude-desktop
[root] emerge --ask --oneshot app-misc/claude-desktop              # do not add to @world
[root] emerge --buildpkgonly app-misc/claude-desktop               # -B: binpkg only, no merge
[root] emerge --usepkg app-misc/claude-desktop                     # -k: reuse a binpkg from PKGDIR
[root] emerge --usepkg=n app-misc/claude-desktop                   # FORCE a real rebuild (see trap below)
[root] emerge --sync td                                            # refresh <installed-repo>
```

Measured, unprivileged:

```
$ emerge -pv --color=n --ignore-default-opts app-crypt/keybase-bin
[ebuild   R   ~] app-crypt/keybase-bin-6.6.3-r1::td  USE="fuse gui -kbnm" L10N="af am ar …" 0 KiB
Total: 1 package (1 reinstall), Size of downloads: 0 KiB

$ emerge -pv --color=n --ignore-default-opts --autounmask=y --autounmask-write=n app-office/obsidian
[ebuild  N    ~] app-office/obsidian-1.12.7::guru  … 198 252 KiB

The following keyword changes are necessary to proceed:
 (see "package.accept_keywords" in the portage(5) man page for more details)
# required by app-office/obsidian (argument)
=app-office/obsidian-1.12.7 ~amd64
```

**Traps on this box:**

1. `EMERGE_DEFAULT_OPTS="--jobs=4 -avt --unordered-display --keep-going --backtrack=75 --getbinpkg"`.
   `man 1 emerge`: "`--getbinpkg` … **This option implies -k**" and `FEATURES` contains `buildpkg` ⇒ after one successful merge a binpkg of *your* package exists in `/var/cache/binpkgs`, and the next `emerge` of the **same PVR** can silently reuse it instead of re-running your edited ebuild. When iterating, always `emerge --usepkg=n …` (or bump `-rN`, or `--ignore-default-opts`).
2. `man 1 emerge`: "`--autounmask-write` … **This option is automatically enabled with `--ask`**" ⇒ `emerge -a --autounmask` *will* write `/etc/portage/package.*`. Use `--autounmask-write=n` when you only want to see the suggestion.
3. `-a` and `-t` are already in `EMERGE_DEFAULT_OPTS`, so a bare `emerge <atom>` already prompts.

### 4.5 Accept files — exact syntax

`/etc/portage/package.accept_keywords` is a **directory** here, so add a file inside it:

```bash
[root] cat > /etc/portage/package.accept_keywords/claude-desktop <<'EOF'
# app-misc/claude-desktop is KEYWORDS="-* ~amd64" (binary repack).
app-misc/claude-desktop ~amd64
EOF
```

Format (`man 5 portage`, `package.accept_keywords`): "comment lines begin with `#` (no inline comments); one DEPEND atom per line followed by additional KEYWORDS; lines without any KEYWORDS imply unstable host arch". Special tokens:

```
*  package is visible if it is stable on any architecture
~* package is visible if it is in testing on any architecture
** package is always visible (KEYWORDS are ignored completely)
```

and, verbatim for exactly our case: "If you encounter the `-*` KEYWORD, this indicates that the package is known to be broken on all systems which are not otherwise listed in KEYWORDS … If you wish to accept this package anyways, then use one of the other keywords in your package.accept_keywords like this: `games-fps/quake3-demo x86`".
⇒ For `KEYWORDS="-* ~amd64"` write `app-misc/claude-desktop ~amd64`. Only if the ebuild has **no** usable arch keyword (e.g. `KEYWORDS=""` or `-*` alone, as guru's live ebuilds) do you need `**` — the house file already uses that form: `=games-util/mangohud-0.8.4 **`, `=app-misc/openrgb-1.0_rc3_p1 **`.

`/etc/portage/package.license` **does not exist on this box** and is not needed, because `/etc/portage/make.conf:25` sets `ACCEPT_LICENSE="*"` (confirmed: `portageq envvar ACCEPT_LICENSE` → `*`). If that ever changes:

```bash
[root] mkdir -p /etc/portage/package.license
[root] printf 'app-misc/claude-desktop Anthropic\n' > /etc/portage/package.license/claude-desktop
```

Format (`man 5 portage:714-720`): "package.license — This will allow ACCEPT_LICENSE … to be augmented for a single package. Format: comment lines begin with `#` (no inline comments); one DEPEND atom per line followed by additional licenses or groups."
`ACCEPT_LICENSE` itself (`man 5 make.conf:47-60`) accepts license names, `@group` names, and the `*` / `-*` wildcards; e.g. `ACCEPT_LICENSE="* -@EULA"`, `ACCEPT_LICENSE="-* @FREE"`.

### 4.6 Verifying what landed

```bash
[user] qlist -Iv app-misc/claude-desktop        # installed package + version
[user] qlist app-misc/claude-desktop            # installed FILE list (fast, portage-utils)
[user] equery files app-misc/claude-desktop     # installed file list (gentoolkit)
[user] equery list 'app-misc/*'                 # note: gentoolkit >=0.3 needs globbing
[user] qlist -Iv | head                         # every installed package
```

Measured samples: `qlist app-arch/zstd` → `/usr/bin/pzstd /usr/bin/unzstd /usr/bin/zstd …`; `equery files app-arch/zstd` additionally lists directories (`/usr`, `/usr/bin`, …). `equery list -h` prints the gentoolkit-0.3 globbing warning.

---

## 5. Custom LICENSE in an overlay — answered with grep evidence

### 5.1 Which repos ship `licenses/`, and does `Anthropic` exist?

```
[user] for r in /var/db/repos/*; do … done
/var/db/repos/gentoo:       licenses/ present (645 files)
/var/db/repos/gentoo-zh:    licenses/ present (43 files)
/var/db/repos/guru:         licenses/ present (62 files)
/var/db/repos/mv:           licenses/ present (6 files)
/var/db/repos/pentoo:       licenses/ present (7 files)
<installed-repo>:           NO licenses/
/var/db/repos/vapoursynth:  NO licenses/

[user] find /var/db/repos/*/licenses -maxdepth 1 -iname '*anthropic*' -o -maxdepth 1 -iname '*claude*'
FOUND: /var/db/repos/gentoo-zh/licenses/Anthropic
FOUND: /var/db/repos/gentoo-zh/licenses/openclaude

[user] grep -ril anthropic /var/db/repos/*/licenses
/var/db/repos/gentoo-zh/licenses/Anthropic
/var/db/repos/gentoo-zh/licenses/openclaude
```

⇒ **`Anthropic` exists only in ::gentoo-zh, not in ::gentoo and not in ::td.** ::td ships no `licenses/` directory at all, so *any* non-gentoo license name used in ::td is an `UnknownLicense` error today (proven by the obsidian scan above).

`/var/db/repos/gentoo-zh/licenses/Anthropic` is a 10-line plain-text pointer file ("Anthropic Terms of Service … Claude Desktop is proprietary software from Anthropic PBC …" + links to consumer-terms/aup/privacy + "The package redistributes the upstream binary unmodified from https://claude.com/download"). ::td may write its own; it must be **plain UTF-8 text** (devmanual: "use a plain text file (UTF-8 encoded), because non-text files do not belong in the repository").

### 5.2 What the overlay must do

1. Create `<repo>/licenses/Anthropic` (plain text). Rule, verbatim from https://devmanual.gentoo.org/general-concepts/licenses/ : *"All ebuilds must specify a `LICENSE` … The license names listed in this variable must match files existing in the repository's `licenses/` directory."* and *"If your package's license is not already in the tree, you must add the license before committing the package."*
2. Optionally add it to a group via `profiles/license_groups` (gentoo's `EULA` group is at `/var/db/repos/gentoo/profiles/license_groups:84`, `BINARY-REDISTRIBUTABLE` at `:72`); GLEP 23 is the reference. ::gentoo-zh does ship a `profiles/license_groups`; ::td does not.
3. License-implied `RESTRICT` (same devmanual page): no redistribution permission ⇒ `RESTRICT=mirror`; no binary-package redistribution ⇒ `RESTRICT=bindist`; manual download ⇒ `RESTRICT=fetch` (implies mirror). Both reference ebuilds do exactly this: `RESTRICT="bindist mirror strip"` (gentoo-zh claude-desktop:26) and `RESTRICT="bindist mirror strip test"` (keybase-bin:36).

### 5.3 Portage vs pkgcheck disagree about where licenses live (measured)

```
[user] ls /var/db/repos/gentoo/licenses | grep -i obsidian   -> (nothing, exit 1)
[user] pkgcheck scan -r <repo> app-office/obsidian
  UnknownLicense: version 1.3.7: unknown license: Obsidian-EULA

[user] ACCEPT_LICENSE='-* @FREE' emerge -pv '=app-office/obsidian-1.3.7::td'
!!! All ebuilds that could satisfy "=app-office/obsidian-1.3.7::td" have been masked.
- app-office/obsidian-1.3.7::td (masked by: Obsidian-EULA license(s), ~amd64 keyword)
A copy of the 'Obsidian-EULA' license is located at '/var/db/repos/guru/licenses/Obsidian-EULA'.

[user] emerge -pv '=app-office/obsidian-1.3.7::td'          # with the box's ACCEPT_LICENSE="*"
- app-office/obsidian-1.3.7::td (masked by: ~amd64 keyword)   # license not an obstacle
```

So: **portage searches `licenses/` across all configured repos** (it found guru's copy for a ::td ebuild) and, with `ACCEPT_LICENSE="*"`, will install even with no license file anywhere; **pkgcheck only accepts license files from the scanned repo plus its `masters`** [INFERENCE, from these two observations + keyword doc "UnknownLicense: License usage with no matching license file"]. Therefore ::td must ship its own `licenses/Anthropic` to get a clean scan — relying on gentoo-zh's copy is not enough for QA and breaks for anyone who doesn't have ::gentoo-zh enabled.
Related repo-scope keywords: `UnknownLicenses`, `UnusedLicenses`, `UnusedInMastersLicenses`, `DeprecatedLicense`, `InvalidLicense`.

---

## 6. House workflow encoded in `scripts/create-discord-canary-new-release.sh`

The script (3.7 KB, bash, `set -e`) does, in order:

1. `OVERLAY_ROOT=$(dirname $(dirname $(readlink -fm $0)))` — every git/manifest operation is `git -C "$OVERLAY_ROOT"`, so it is meant to be run from whichever checkout it lives in.
2. Dependency gate: `jq` **or** `yq`, plus `pkgdev`, `curl`, `git` (`command_exists … || (echo "… not installed (dev-util/pkgdev)"; exit 1)`).
3. Latest version: `curl -s 'https://discord.com/api/updates/canary?platform=linux' | jq -Mr .name`; aborts if empty.
4. Newest existing ebuild: `find … ! -name 'Manifest' -type f | sort -V | tail -n1` (`-type f` = the real file; a second `find` without `-type f` gives the newest path incl. symlinks).
5. If the newest path != the new version: **`ln -s $(basename ${LATEST_EBUILD_FILE_PATH}) $NEW_EBUILD_PATH`** — new versions are **symlinks to the last real ebuild**, not copies. Confirmed on disk: `net-im/discord-canary/` holds one real `discord-canary-0.0.251.ebuild` plus `discord-canary-0.0.25{3,5,6,7}.ebuild -> discord-canary-0.0.251.ebuild`.
6. **`pkgdev manifest`** (bare, no flags) — the only QA step the script runs; matches `README.md`'s "### After ebuild creation → `pkgdev manifest`". *No `pkgcheck` step exists in the house tooling.*
7. Saves/restores any pre-existing staged files, then stages exactly two paths (`git add $NEW_EBUILD_PATH`, `git add $OVERLAY_ROOT/net-im/discord-canary/Manifest`) and aborts with `git reset` unless exactly 2 files are staged.
8. Commit message: **`Add $(basename $NEW_EBUILD_PATH)`** → e.g. `Add discord-canary-1.0.1884.ebuild`. `git push` is present but commented out.

Actual `git log` subjects in the dev checkout (house style):

```
keybase-bin: fix window icon on KDE/Wayland (-r1)      <- pkgdev-style "pkg: summary" for real changes
Add keybase-bin-6.6.3.ebuild                            <- "Add <file>.ebuild" for new versions
Add discord-canary-1.0.1884.ebuild
Untrack generated md5-cache file
Rewrite discord-canary ebuild for bootstrapper tarball
Use version sort in discord-canary release script
```

The one multi-line commit follows the standard shape: `pkg: imperative summary` + blank line + wrapped body explaining *why*:

```
keybase-bin: fix window icon on KDE/Wayland (-r1)

Electron announces app_id/WM_CLASS "Keybase", so KWin looked for Keybase.desktop,
found nothing and fell back to the icon of the launching application. Add
StartupWMClass and ship a hidden Keybase.desktop alias.
```

Note the script does *not* use `pkgdev commit` (which would auto-generate `cat/pkg: …` summaries and mangle headers); it uses raw `git commit -m`.

---

## 7. Recommended end-to-end loop for a new prebuilt package in ::td

```bash
# 1. author (dev checkout only!)
[user] cd <repo> && mkdir -p app-misc/claude-desktop
#      write app-misc/claude-desktop/claude-desktop-<PV>.ebuild (+ metadata.xml, + licenses/Anthropic)

# 2. manifest (network; writes Manifest + /var/cache/distfiles)
[user] pkgdev manifest app-misc/claude-desktop
#      or, from the package dir:  ebuild claude-desktop-<PV>.ebuild manifest

# 3. QA (read-only)
[user] pkgcheck scan -r . app-misc/claude-desktop --exit
[user] pkgcheck scan -r . --net app-misc/claude-desktop        # optional, validates URIs

# 4. phase-level smoke test, no root, nothing merged
[user] cd app-misc/claude-desktop
[user] ebuild claude-desktop-<PV>.ebuild clean install
[user] find /var/tmp/portage/app-misc/claude-desktop-<PV>/image -maxdepth 3 | head -50

# 5. real install
[root] printf 'app-misc/claude-desktop ~amd64\n' > /etc/portage/package.accept_keywords/claude-desktop
[user] emerge -pv app-misc/claude-desktop
[root] emerge --ask --verbose --usepkg=n app-misc/claude-desktop
[user] qlist -Iv app-misc/claude-desktop && equery files app-misc/claude-desktop | head -30

# 6. publish
[user] git add app-misc/claude-desktop licenses/Anthropic && git commit -m 'Add claude-desktop-<PV>.ebuild'
[user] git push
[root] emerge --sync td      # only after <installed-repo>'s local dirt (§1.2) is cleaned up
```

---

## 8. Prior art worth knowing before writing app-misc/claude-desktop

**`::gentoo-zh` already ships `app-misc/claude-desktop`** at `/var/db/repos/gentoo-zh/app-misc/claude-desktop/claude-desktop-1.52386.6.ebuild`, and that repo is enabled on this machine — a same-named ::td package will shadow/compete with it (`pkgcheck` keyword `MasterPackageClobbered` exists for the master case). Its skeleton, for reference:

| line | content |
|---|---|
| 4 | `EAPI=8` |
| 6 | `inherit desktop optfeature pax-utils unpacker xdg` |
| 11-20 | `SRC_URI="amd64? ( https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop/claude-desktop_${PV}_amd64.deb -> ${P}-amd64.deb ) arm64? ( … )"` |
| 21 | `S="${WORKDIR}"` |
| 23-26 | `LICENSE="Anthropic"` / `SLOT="0"` / `KEYWORDS="-* ~amd64 ~arm64"` / `RESTRICT="bindist mirror strip"` |
| 64 | `QA_PREBUILT="*"` |
| 66-84 | `src_install`: `dodir /opt`, `mv usr/lib/claude-desktop "${ED}/opt/${PN}" \|\| die`, `fperms 4755 "/opt/${PN}/chrome-sandbox"`, `pax-mark m`, `dosym -r`, `domenu usr/share/applications/com.anthropic.Claude.desktop`, `insinto /usr/share/icons; doins -r usr/share/icons/hicolor` |
| 86-93 | `pkg_postinst`: `xdg_pkg_postinst`, `elog`, `optfeature` |

The house equivalent, `app-crypt/keybase-bin-6.6.3-r1.ebuild` (scans **clean**), differs in style: `EAPI=8` (L4), `inherit chromium-2 desktop linux-info optfeature systemd unpacker xdg` (L13), multi-mirror `SRC_URI` with `-> ${P}.deb` (L24-29), `S="${WORKDIR}"` (L30), `KEYWORDS="-* ~amd64"` (L34), `RESTRICT="bindist mirror strip test"` (L36), `QA_PREBUILT="opt/keybase/* usr/bin/*"` (L77), explicit `src_unpack() { unpack_deb "${A}" }` (L86-88), `src_prepare` that deletes `etc/apt` and `usr/share/doc` (L90+), file-by-file `src_install` with `dobin`/`doexe`/`doins`/`fowners`/`fperms 4755` (L114+), and a `metadata.xml` with `<!-- maintainer-needed -->`, per-flag `<flag>` descriptions and `<remote-id type="github">`.

---

## 9. Could not verify

- **`ebuild` phase execution** (`unpack`/`prepare`/`install`/`qmerge`) was not run — the read-only constraint forbids writing to `$PORTAGE_TMPDIR`. The root/non-root matrix in §4.2 is derived from directory ownership + `FEATURES=userpriv usersandbox`, not from an observed run.
- **`pkgdev manifest` on a modified package** was only exercised in its clean no-op form (`manifests are up to date`); the fetch/write path was not triggered.
- **`pkgdev mask` / `pkgdev bugs` / `pkgdev push`** were not executed (they write or need Bugzilla credentials); flags come from `--help`.
- **`eselect repository`**: the module is installed (`app-eselect/eselect-repository-15`, `/usr/share/eselect/modules/repository.eselect`) but the subcommand is `eselect repository`, **not** `eselect repo` (`eselect repo list` → `!!! Error: Can't load module repo`). `eselect repository list -i` works but downloads `repositories.xml` into `~/.cache/eselect-repo/`.
- **Why `PkgMissingMetadataXml` (level error) does not fire in ::td** is unexplained; only the empirical result is reported (`pkgcheck scan -r . -c PackageMetadataXmlCheck net-im/discord` → no output, exit 0, and `net-im/discord/` contains only `Manifest` + one ebuild).
- `EmptyCategoryDir`/`EmptyPackageDir` did not fire on the empty `media-libs/alvr` (dev checkout) and `dev-db/` (installed clone) directories — consistent with both being flagged "Gentoo repo specific" in `man 1 pkgcheck`.
