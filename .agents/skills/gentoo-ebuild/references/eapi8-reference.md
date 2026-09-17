# EAPI 8 authoring reference (ebuild bodies)

Citation keys:

* **PMS §N / table N / algorithm N / listing N** → <https://projects.gentoo.org/pms/8/pms.html> (EAPI 8 PMS, dated 13 June 2021, commit 06af57d; anchors are per-section, e.g. `#x1-250003.2` for §3.2).
* **DM** → `https://devmanual.gentoo.org/…` (URL given inline).
* **PG NNNN** → <https://projects.gentoo.org/qa/policy-guide/> (Gentoo QA Policy Guide).
* Local file paths are verified on this machine (`/var/db/repos/gentoo`, installed pkgcheck 0.10.43 at `pkgcheck/`).

---

## 1. EAPI 8 delta vs EAPI 7

Complete list, verbatim from PMS Appendix E → “EAPI 8” (16 items), with the normative section for each:

| # | Change | Normative ref | Practical effect |
|---|---|---|---|
| 1 | Less strict naming rules for files in `profiles/updates/` | PMS §4.4.4 | repo-level only |
| 2 | **Bash version is 5.0** (EAPI 7 = 4.2); `failglob` set in global scope | PMS §6, table 6.1 | may use bash 5.0 features; an unmatched glob **in global scope** is a hard error |
| 3 | **Selective fetch/mirror restriction**: `fetch+`/`mirror+` URI prefixes | PMS §7.3.2 (`uri-restrict`), table 7.3 | per-file exemption from `RESTRICT="fetch"`/`"mirror"` |
| 4 | **`IDEPEND`** (install-time deps, CBUILD-compatible, live in `BROOT`) | PMS §8.1 (`idepend`), tables 8.1/8.2/8.4 | guaranteed in `pkg_preinst`/`pkg_postinst`; may be gone in `pkg_prerm`/`pkg_postrm`; query with `has_version -b` |
| 5 | **`pkg_*` phases start in a dedicated empty directory** (may be read-only) | PMS §9.1.1 (`phase-function-dir`), table 9.1 | never `cd`-less write in `pkg_*`; do not assume `${S}`/`${WORKDIR}` cwd |
| 6 | **`src_prepare` format 8** = `eapply -- "${PATCHES[@]}"` then `eapply_user` | PMS §9.1.5, table 9.4, listing 9.3 | `PATCHES` can no longer carry `patch` options (`-p0` etc.); call `eapply -p0 …` yourself |
| 7 | **`PROPERTIES` and `RESTRICT` accumulate across eclasses** | PMS §10.2 (`accumulate-vars`), table 10.1 | write `PROPERTIES="live"`, not `PROPERTIES+=" live"`. Accumulated set in EAPI 8: `IUSE REQUIRED_USE DEPEND BDEPEND RDEPEND PDEPEND IDEPEND PROPERTIES RESTRICT`. **Not** accumulated: `EAPI HOMEPAGE SRC_URI LICENSE KEYWORDS` |
| 8 | **`useq` banned** | PMS §12.3.2, table 12.3 | use `use` |
| 9 | **`hasv` and `hasq` banned** | PMS §12.3.2, table 12.3 | use `has` |
| 10 | `econf` adds **`--datarootdir="${EPREFIX}"/usr/share`** | PMS §12.3.8 (`econf-options`), table 12.8 | only passed if the string appears in `configure --help` |
| 11 | `econf` adds **`--disable-static`** | PMS §12.3.8, table 12.8 | only if `configure --help` mentions it; pass `--enable-static` explicitly to override (policy rationale: PG 0302, <https://projects.gentoo.org/qa/policy-guide/installed-files.html#pg0302>) |
| 12 | **`dosym -r`** creates relative links | PMS §12.3.9 (`dosym-relative`), table 12.15, listing 12.2 | `-r` + relative first arg = error; `-r` does *logical* path math (breaks through directory symlinks) |
| 13 | **`insopts` no longer affects `doconfd`, `doenvd`, `doheader`** | PMS §12.3.10 (`insopts`), table 12.16 | `insopts` ⇒ only `doins`/`newins` |
| 14 | **`exeopts` no longer affects `doinitd`** | PMS §12.3.10 (`exeopts`), table 12.17 | `exeopts` ⇒ only `doexe`/`newexe` |
| 15 | **`usev` takes an optional second argument** | PMS §12.3.12 (`usev`), table 12.20 | `$(usev foo --enable-foo)` == `$(usex foo --enable-foo '')` |
| 16 | **`unpack` drops `.7z`, `.rar`, `.lha`/`.lzh`** | PMS §12.3.15 (`unpack-extensions`), table 12.24 | `.deb`, `.zip`, `.tar.*`, `.a`, `.xz`, `.txz` still supported; use `unpacker.eclass` for the dropped ones (DM <https://devmanual.gentoo.org/ebuild-writing/eapi/index.html>) |

Inherited-from-EAPI-7 things that matter and are *not* new in 8 (PMS Appendix E → EAPI 7): `BDEPEND`, `BROOT`/`SYSROOT`/`ESYSROOT`, no trailing slash on `ROOT`/`EROOT`/`D`/`ED` (§11.1.4), **`die` works in subshells** (table 12.6), `nonfatal` is both function and external command (table 12.2), `dohtml`/`dolib`/`libopts` banned (table 12.3), `eqawarn` + output commands must not use stdout (table 12.5), `dostrip` + controllable stripping (table 12.18), `ver_cut`/`ver_rs`/`ver_test` (§12.3.14), `domo` installs to `/usr/share/locale` (table 12.14), `has_version`/`best_version` take `-b`/`-d`/`-r` (§12.3.4).

EAPI 6→7/8 removals to remember: `einstall` banned since EAPI 6 (table 12.3); `epatch` is an eclass function, never PM-provided — use `eapply` (PMS §12.3.7, table 12.7: `eapply`/`eapply_user` exist in EAPI 6, 7, 8).

> Context check: this machine’s tree already ships `EAPI=9` in `/var/db/repos/gentoo/skel.ebuild:16`, and devmanual documents EAPI 9 (bash 5.3, `assert`/`domo` banned, `pipestatus`, `edo`, `ver_replacing`, variables no longer exported). EAPI 8 remains valid and is the target here.

---

## 2. Required/ordered variable layout

### 2.1 Header (exact, current)

```
# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2
```

* Authoritative source: `/var/db/repos/gentoo/header.txt:1-2` (in this checkout it is exactly the two lines above — single year `2026`, no range).
* Rule: two-line header at the very start, followed by a blank line, and it must be an exact copy of `header.txt` — DM <https://devmanual.gentoo.org/ebuild-writing/file-format/index.html#ebuild-header>. The old `$Id$` third line must not be added.
* What pkgcheck actually enforces: `copyright_regex = ^# Copyright (\d{4}-)?(\d{4}) (.+)$` (`pkgcheck/checks/header.py:8`); for end-year ≥ 2019 the holder must be `Gentoo Authors` (`header.py:118-126`; `Gentoo Foundation` → `OldGentooCopyright`, anything else → `NonGentooAuthorsCopyright`); line 2 must equal `# Distributed under the terms of the GNU General Public License v2` (`header.py:110`). A year *range* (`1999-2026`) is accepted — `/var/db/repos/gentoo/skel.ebuild:1-2` uses `1999-2026` — but for a brand-new file in your own overlay, `# Copyright 2026 Gentoo Authors` (or your own holder, outside ::gentoo) is correct.
* Overlay note: the “must be Gentoo Authors” results come from `GentooRepoCheck` (header.py `_HeaderCheck(GentooRepoCheck)`), i.e. they only fire for the Gentoo repo; other repos may name an explicit holder (see `NonGentooAuthorsCopyright` docstring).

### 2.2 `EAPI=8` line

PMS §7.3.1: the assignment must occur **exactly once**, may be preceded only by blank lines and `#` comment lines, and must match

```
^[ \t]*EAPI=(['"]?)([A-Za-z0-9+_.-]*)\1[ \t]*([ \t]#.*)?$
```

The PM parses this line *textually* before sourcing and rejects the ebuild if the sourced value differs. Consequence: `EAPI` must come before `inherit` (eclasses branch on it) and must not be computed. DM: <https://devmanual.gentoo.org/ebuild-writing/eapi/index.html> (“EAPI must only be defined in ebuild files, not eclasses”).

### 2.3 Canonical order

```
# Copyright <year> Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit <eclasses>

DESCRIPTION=
HOMEPAGE=
SRC_URI=
S=                  # only if != ${WORKDIR}/${P}

LICENSE=
SLOT=
KEYWORDS=
IUSE=
REQUIRED_USE=
RESTRICT=
PROPERTIES=

BDEPEND=  DEPEND=  RDEPEND=  PDEPEND=  IDEPEND=

<phase functions, in call order>
```

* **QA-enforced subsequence** (pkgcheck `VariableOrderCheck`, result `VariableOrderWrong`, severity *Style*): `DESCRIPTION, HOMEPAGE, SRC_URI, S, LICENSE, SLOT, KEYWORDS, IUSE, RESTRICT` — `pkgcheck/checks/codingstyle.py:1764-1781` (comment in source: “Order from skel.ebuild”). Only these nine are checked; everything else is convention.
* Matching convention in the tree: `/var/db/repos/gentoo/skel.ebuild` — `DESCRIPTION:28`, `HOMEPAGE:31`, `SRC_URI:35`, `#S:41`, `LICENSE:47`, `SLOT:60`, `KEYWORDS:78`, `IUSE:83`, `#RESTRICT:87`, `#RDEPEND:98`, `#DEPEND:103`, `#BDEPEND:107`.
* Real EAPI 8 example (prebuilt .deb): `/var/db/repos/gentoo/sys-apps/intune-portal/intune-portal-1.2607.4-r1.ebuild:1-15`.
* Phases “should usually be defined in the order they are called, for readability” — DM <https://devmanual.gentoo.org/ebuild-writing/functions/index.html>.

### 2.4 Which variables are mandatory

| Variable | PMS status | Notes / citation |
|---|---|---|
| `DESCRIPTION` | **Mandatory** (PMS §7.2) | non-empty; may come from an eclass; ≤ 80 chars by convention (DM variables) |
| `SLOT` | **Mandatory** (PMS §7.2) | non-empty; `SLOT="0"` when unused; `slot/subslot` allowed (table 8.7); never `SLOT=""` |
| `EAPI` | Optional per PMS §7.3 (unset == 0) | in practice mandatory: always set `EAPI=8` |
| `HOMEPAGE` | Optional per PMS §7.3; **mandatory by policy** (DM variables; except virtuals) | raw text only, no variables — **PG 0103** <https://projects.gentoo.org/qa/policy-guide/ebuild-format.html#pg0103>; use `https://wiki.gentoo.org/wiki/No_homepage` if none |
| `LICENSE` | Optional per PMS §7.3; **mandatory by policy** (DM variables) | must match `licenses/` filename exactly; no variables — **PG 0106** |
| `SRC_URI` | Optional (PMS §7.3.2) | omit for pure meta/live packages |
| `KEYWORDS` | Optional (PMS §7.3.3) | one line, literal, at most once — **PG 0105**; `-arch` = will not work; `-*` = do not try elsewhere; empty = unknown everywhere |
| `IUSE` | Optional (PMS §7.3) | cumulative with eclasses; omit if empty; never list arch flags (DM variables §IUSE) |
| `REQUIRED_USE` | Optional, EAPI ≥ 4 (table 7.2) | operators `||`, `^^`, `??`, `flag? ( )` (PMS §7.3.4, §8.2) |
| `RESTRICT` | Optional (PMS §7.3.6) | standard tokens: `mirror fetch strip userpriv test` |
| `PROPERTIES` | Optional, EAPI ≥ 4 (table 7.2) | standard tokens: `interactive live test_network` (PMS §7.3.5) |
| `S` | Optional (PMS table 11.1) | default `${WORKDIR}/${P}`; **omit when default** (DM variables); for repacks that unpack into `${WORKDIR}` root use `S="${WORKDIR}"` (example: intune-portal ebuild line 11) |
| `DEPEND/BDEPEND/RDEPEND/PDEPEND/IDEPEND` | Optional (PMS §7.3, chapter 8) | in EAPI 7/8 `RDEPEND` does **not** default to `DEPEND` (PMS §7.3.7, table 7.4) |
| `DOCS`, `HTML_DOCS` | PM-consumed (PMS algorithm 12.4) | arrays or scalars, used by `einstalldocs` / default `src_install` |

### 2.5 `SRC_URI` specifics

* Renaming with arrows (EAPI ≥ 2, table 7.3): `SRC_URI="https://ex.com/${PV}.tar.gz -> ${P}.tar.gz"`; all tokens including `->` must be whitespace-separated (PMS §8.2, DM <https://devmanual.gentoo.org/ebuild-writing/variables/index.html#renaming-sources>).
* USE-conditional/arch blocks: `amd64? ( … )` etc. — same `flag? ( )` grammar as dependencies (PMS §8.2); `A` only contains enabled components (PMS table 11.1).
* EAPI 8 selective restriction (PMS §7.3.2 `uri-restrict`): with `RESTRICT="fetch"`, plain entries are unfetchable, `fetch+URI` becomes fetchable (still unmirrored), `mirror+URI` becomes fetchable **and** mirrorable. `fetch` implies `mirror`. Truth table: DM <https://devmanual.gentoo.org/ebuild-writing/variables/index.html#lifting-restrictions>.
* `SRC_URI` must not reference `${HOMEPAGE}` — **PG 0104**; pkgcheck result `HomepageInSrcUri` (`codingstyle.py:528`).
* Valid protocols: `http:// https:// ftp:// mirror://`; fetch-restricted packages may list a bare filename (PMS §7.3, `SRC_URI` entry).

---

## 3. Dependency syntax reference

### 3.1 Classes (PMS §8.1, tables 8.1–8.4)

| Class | Satisfied during | Binary-compat with | Path root | PM query flag |
|---|---|---|---|---|
| `BDEPEND` | all `src_*` (+`pkg_setup` in source builds) | CBUILD | `/` → `${BROOT}` | `-b` |
| `DEPEND` | all `src_*` (+`pkg_setup` in source builds) | CHOST | `${SYSROOT}` → `${ESYSROOT}` | `-d` |
| `RDEPEND` | `pkg_preinst`, `pkg_postinst`, `pkg_prerm`, `pkg_postrm`, `pkg_config` | CHOST | `${ROOT}` → `${EROOT}` | `-r` |
| `IDEPEND` | `pkg_preinst`, `pkg_postinst` (may be absent in `*rm`) | CBUILD | `${BROOT}` | `-b` |
| `PDEPEND` | after merge; `pkg_config` | CHOST | `${ROOT}` | `-r` |

`pkg_pretend`, `pkg_info`, `pkg_nofetch` get **no** dependency guarantees (table 8.1) — only `@system`. Executables from `DEPEND` must **not** be run (PMS §8.1, `bdepend` bullet). Binary-package installs only consult `RDEPEND` (DM <https://devmanual.gentoo.org/general-concepts/dependencies/index.html#runtime-dependencies>).

### 3.2 Grammar (PMS §8.2 — whitespace is mandatory around every token)

| Construct | Form | Allowed in |
|---|---|---|
| all-of | `( a b )` | all spec variables |
| any-of | `|| ( a b )` | `*DEPEND`, `LICENSE`, `REQUIRED_USE` |
| exactly-one-of | `^^ ( a b )` | `REQUIRED_USE` |
| at-most-one-of | `?? ( a b )` (EAPI ≥ 5, table 8.5) | `REQUIRED_USE` |
| use-conditional | `flag? ( … )`, `!flag? ( … )` | all spec variables |

Empty groups are illegal in EAPI 7/8 (PMS Appendix C “Empty dependency groups”, Appendix E EAPI 7).

### 3.3 Version operators (PMS §8.3.1)

| Operator | Meaning |
|---|---|
| `<`, `<=`, `>=`, `>` | ordinary comparisons (PMS §3.3 algorithm) |
| `=cat/pkg-1.2` | exactly that version |
| `=cat/pkg-1.2*` | prefix wildcard on version components; the spec must stay valid with the `*` removed; illegal with any other operator |
| `~cat/pkg-1.2` | version 1.2 ignoring revision (`-r0`, `-r1`, …) |

DM guidance: prefer `~` over `=` so revbumps keep matching — <https://devmanual.gentoo.org/general-concepts/dependencies/index.html#version-specifiers>.

### 3.4 Blockers (PMS §8.3.2, table 8.9)

* `!cat/pkg` = **weak** block (EAPI ≥ 2): PM may merge first and unmerge the blocked package later; exempts colliding files from collision checks. Put weak blockers in `RDEPEND` — pure-`DEPEND` weak blockers do not work correctly (DM <https://devmanual.gentoo.org/general-concepts/dependencies/index.html#blockers>).
* `!!cat/pkg` = **strong** block: must be resolved before building/merging; for cases where mere presence breaks the build, not for file collisions.
* Weak blocks on the ebuild’s own version do not count (PMS §8.3.2).

### 3.5 Slot dependencies (PMS §8.3.3, table 8.7 — EAPI 5+ has named *and* operator forms)

| Spec | Meaning |
|---|---|
| `:2` | only slot 2; sub-slot changes ignored |
| `:2/3` | exact slot/sub-slot pair (useful for prebuilt binaries pinned to a soname) |
| `:*` | any slot; explicitly says “I do not care about slot/sub-slot changes” |
| `:=` | any slot; **rebuild me** when the best matching installed dep changes slot/sub-slot |
| `:2=` | only slot 2, plus `:=` rebuild semantics |

Rules: `:=` requires that `DEPEND` guarantees a match at build time; `:=` is **invalid inside `PDEPEND` and inside any-of (`|| ( )`) groups** (PMS §8.3.3). `:slot/subslot=` is a syntax error in ebuilds (DM <https://devmanual.gentoo.org/ebuild-writing/eapi/index.html#eapi-5-metadata>). Order matters: slot restriction comes **before** the USE dependency (PMS §8.3 note).

### 3.6 USE dependencies (PMS §8.3.4, table 8.8 — EAPI 4+ = 4-style)

| Spec | Meaning |
|---|---|
| `[opt]` / `[-opt]` | flag must be enabled / disabled |
| `[opt=]` | dep’s flag must match mine |
| `[!opt=]` | dep’s flag must be the inverse of mine |
| `[opt?]` | if my flag is on, dep’s must be on |
| `[!opt?]` | if my flag is off, dep’s must be off |
| `[a,-b,c?]` | comma-combined; all must match |

**4-style defaults** `(+)` / `(-)`: when the target package does **not** list that flag in `IUSE_REFERENCEABLE`, `(+)` means “pretend present and enabled”, `(-)` means “pretend present and disabled” (PMS §8.3.4 `use-dep-defaults`). Without a default it is an *error* to apply a USE dep to a package lacking the flag. Example from DM: `>=dev-libs/boost-1.48[threads(+)] sys-devel/gcc[openmp(-)]` — <https://devmanual.gentoo.org/general-concepts/dependencies/index.html#use-dependency-defaults>. Typical prebuilt-package usage: `x11-libs/gtk+:3[X(+)]`, `media-libs/mesa[gbm(+)]`. Using a conditional USE dep (`[foo?]`, `[foo=]`) requires `foo` in your own `IUSE_EFFECTIVE` (PMS §8.3.4 last paragraph).

### 3.7 any-of / virtual practice

* Sort `|| ( )` members in *preferred* order — the resolver picks the first satisfiable one (DM <https://devmanual.gentoo.org/general-concepts/dependencies/index.html#any-of-many-dependencies>, bug 489458).
* A USE flag is unnecessary (use `|| ( )` instead) only if swapping providers cannot break an already-built package and a binpkg stays valid across providers (same page, “Any of many versus USE”).
* Independent specs may be satisfied by *different slots* of a slotted package; express ranges per-slot inside `|| ( )` instead of `>=x-2 <x-5` (DM “Common pitfalls”).
* Test deps go in `BDEPEND`/`DEPEND` behind `test`, with `RESTRICT="!test? ( test )"` (DM “Test dependencies”).
* List every *direct* dependency; do not rely on transitive chains (DM “Indirect dependencies”). No need to depend on `@system` members (DM “Implicit system dependency”).

---

## 4. Phase function rules

### 4.1 Order and defaults

Call order for an install (PMS §9.2): `pkg_pretend` (out of band) → `pkg_setup` → `src_unpack` → `src_prepare` → `src_configure` → `src_compile` → `src_test` → `src_install` → `pkg_preinst` → `pkg_postinst`. Uninstall: `pkg_prerm` → `pkg_postrm`. Upgrade/replace inserts `pkg_prerm`/`pkg_postrm` of the replaced package between `pkg_preinst` and `pkg_postinst`. **Binary package installs skip all `src_*` phases** (PMS §9.2, final paragraphs) — anything a binpkg user needs must happen in `pkg_*`/`RDEPEND`. Each phase runs at most once (PMS §11.3).

| Phase | Initial cwd (EAPI 8) | Default implementation |
|---|---|---|
| `pkg_*` | dedicated **empty** dir, possibly read-only (PMS §9.1.1, table 9.1) | `pkg_nofetch` has a default; others are no-ops |
| `src_unpack` | `${WORKDIR}` (PMS §9.1.4) | listing 9.1: `[[ -n ${A} ]] && unpack ${A}` |
| `src_prepare` | `${S}` (fallback/err to `${WORKDIR}`, §9.1.1, table 9.2) | listing 9.3 (format 8): `eapply -- "${PATCHES[@]}"` then `eapply_user` |
| `src_configure` | `${S}` | listing 9.4: `econf` if `${ECONF_SOURCE:-.}/configure` is executable |
| `src_compile` | `${S}` | listing 9.7 (format 2): `emake` if a `Makefile`/`GNUmakefile`/`makefile` exists |
| `src_test` | `${S}` | `emake check`, else `emake test`, if such a target exists; parallel allowed (table 9.7) |
| `src_install` | `${S}` | listing 9.9 (format 6, used by EAPI 6/7/8): `emake DESTDIR="${D}" install` if a makefile exists, then `einstalldocs` |

`${S}`-to-`${WORKDIR}` fallback in EAPI 4-8 is a **conditional error**: it is fatal unless `A` is empty *and* no earlier `src_*` phase is defined (PMS §9.1.1 `s-workdir-fallback`). Practical consequence for repacks that unpack into `${WORKDIR}`: set `S="${WORKDIR}"` explicitly.

`default` / `default_<phase>` are available in EAPI 8 for `pkg_nofetch` and all `src_*` (PMS §9.1.17, table 9.10, §12.3.15 `default`); calling them outside their phase is an error.

### 4.2 What may write where

| Location | Written by | Rule |
|---|---|---|
| `${WORKDIR}` | `src_*` | “where all build data should be contained” (PMS table 11.1) |
| `${S}` | `src_prepare`…`src_install` | `${WORKDIR}/${P}` by default; may be reassigned (table 11.1) |
| `${T}` | any phase | per-ebuild temp dir; consistent across an install sequence (table 11.1, footnote 5) |
| `${D}` / `${ED}` | **`src_install` and `pkg_preinst` only** | PMS table 11.1 (`D` legal in `src_install`, `pkg_preinst`, `pkg_postinst`), but **QA policy PG 0107 forbids `D`/`ED` outside `src_install` and `pkg_preinst`** — <https://projects.gentoo.org/qa/policy-guide/ebuild-format.html#pg0107>; enforced by pkgcheck `VariableScopeCheck` (`codingstyle.py:1219-1220`, comment “pkg_postinst is forbidden by QA policy PG 107”) |
| `${ROOT}` | `pkg_preinst`, `pkg_postinst`, `pkg_prerm`, `pkg_postrm` | those phases “must not write outside” `ROOT` (`pkg_preinst`: `ROOT` and `D`) — PMS §9.1.10-§9.1.13 |
| filesystem at large | nobody | `pkg_pretend` **must not write to the filesystem** (PMS §9.1.2); `pkg_setup` must not introduce “variancy” (PMS §11.3) |
| `${DISTDIR}`, `${FILESDIR}` | read-only in practice | `FILESDIR` may not exist; only defined in `src_*`/global scope (PMS table 11.1) |

Variable scope quick table as enforced by pkgcheck `VariableScopeCheck` (`codingstyle.py:1204-1222`, itself keyed to PMS §11.1): `A`/`AA` → `src_*`+`pkg_nofetch`; `FILESDIR`/`DISTDIR`/`WORKDIR`/`S` → `src_*`; `ROOT`/`EROOT` → `pkg_*`; `SYSROOT`/`ESYSROOT` → `src_*`+`pkg_setup`; `BROOT` → `src_*`, `pkg_setup`, `pkg_preinst`, `pkg_prerm`, `pkg_post*`; `D`/`ED` → `src_install`, `pkg_preinst`; `MERGE_TYPE`/`REPLACING_VERSIONS` → `pkg_*`; `REPLACED_BY_VERSION` → `pkg_prerm`/`pkg_postrm`. None of these may be used in **global scope**.

### 4.3 Sandbox

* `src_*` phases run sandboxed; `pkg_preinst`/`pkg_postinst` run with **Sandbox: Disabled**, privilege root — DM <https://devmanual.gentoo.org/ebuild-writing/functions/pkg_preinst/index.html>, <https://devmanual.gentoo.org/ebuild-writing/functions/pkg_postinst/index.html> (the per-phase tables at the top of each page).
* Sandbox controls (PMS §12.3.3): `addread`, `addwrite`, `addpredict`, `adddeny`, each taking exactly **one directory**; must not be run after the phase returns. pkgcheck errors on multi-arg/colon-separated calls (`InvalidSandboxCall`, `codingstyle.py:1718-1742`).
* Network is unavailable in build phases by design; do all fetching via `SRC_URI` (DM <https://devmanual.gentoo.org/ebuild-writing/functions/index.html>).

### 4.4 `die`, `|| die`, `assert`, `nonfatal`

* **Every PM-provided command documented with “Failure behaviour is EAPI dependent” aborts the build in EAPI 7 and 8** (PMS §12.3.1, table 12.2: EAPIs 7, 8 → “Aborts”, `nonfatal` supported, and `nonfatal` exists both as a shell function and an external command). So `dobin foo || die` is redundant; `dobin foo` already dies.
* `econf`, `eapply`, `eapply_user`, `einstalldocs` are specified to die on failure explicitly (PMS §12.3.8, §12.3.7, §12.3.15) unless run under `nonfatal`.
* **Shell builtins, external commands and anything from upstream still need `|| die`**: `cp … || die`, `mv … || die`, `cd … || die`, `sed -i … || die`. DM: “You should use `die` on almost all external commands in ebuilds” — <https://devmanual.gentoo.org/ebuild-writing/error-handling/index.html>.
* Pipelines: `$?` only reflects the last element; use `assert` (checks `PIPESTATUS`, calls `die`) — PMS §12.3.6, DM error-handling “The `assert` function and `PIPESTATUS`”. (Note: `assert` is banned in EAPI 9, replaced by `pipestatus` — not relevant to EAPI 8.)
* Subshells: `die` **is** guaranteed to work in a subshell in EAPI 7/8 (PMS table 12.6). DM still recommends `if` blocks and input redirection over `cat … | while` because of scoping surprises.
* `nonfatal cmd` converts an aborting helper into a non-zero return (PMS §12.3.1); `die -n` only returns non-zero when running under `nonfatal` (PMS §12.3.6, table 12.6).
* Output commands (PMS §12.3.5, table 12.5): `einfo einfon elog ewarn eqawarn eerror ebegin eend`; in EAPI 7/8 they must not write to stdout, and `eqawarn` exists. Never `echo` in a phase.

### 4.5 `pkg_*` restrictions worth repeating

* `pkg_pretend` runs outside the normal sequence, has no env saving, no dependency guarantees, and must not write to the filesystem (PMS §9.1.2).
* `pkg_setup` must not change system state (PMS §11.3) but runs with full filesystem permissions (PMS §9.1.3) — correct place for user/group creation.
* `pkg_config` is the only phase allowed to be interactive (PMS §9.1.14).
* In EAPI 8 every `pkg_*` phase starts in an empty, possibly read-only dir — write to `${T}` if you need scratch space (PMS §9.1.1).
* `REPLACING_VERSIONS` (in `pkg_preinst`/`pkg_postinst`) and `REPLACED_BY_VERSION` (in `pkg_prerm`/`pkg_postrm`) are the supported upgrade-detection hooks (PMS §11.1.2, table 11.2).

---

## 5. Install-phase helper reference (EAPI 8)

Unless stated otherwise, every row below is PMS §12.3.9 (installation commands), §12.3.10 (destinations) or §12.3.11 (staging manipulation); “dies” = the command aborts the build on failure in EAPI 8 by PMS §12.3.1 + table 12.2. All install helpers are *external programs* (callable from `xargs`), all destination-setting commands are *shell functions*; none may be called after the phase returns. Paths are relative to `${ED}`. Calling any install helper with no filename argument is an error.

| Helper | Signature / destination | Available in EAPI 8 | Dies on its own | Notes |
|---|---|---|---|---|
| `dobin` | `dobin <files>` → `${DESTTREE}/bin` (default `/usr/bin`), mode 0755, root-owned | yes | **yes** | dest changed with `into` |
| `dosbin` | `dosbin <files>` → `${DESTTREE}/sbin` | yes | **yes** | as `dobin` |
| `newbin` / `newsbin` | `new* <src> <newname>` | yes | **yes** | `-` as `<src>` reads stdin (table 12.13) |
| `doexe` | `doexe <files>` → dir set by `exeinto`, mode 0755 or `exeopts` | yes | **yes** | behaviour undefined if `exeinto` was never called |
| `newexe` | `newexe <src> <newname>` | yes | **yes** | |
| `exeinto` | `exeinto <dir>` sets `doexe`/`newexe` target; creates it | yes | **yes** (EAPI-dependent failure, as `into`) | shell function |
| `exeopts` | `exeopts <install-opts>` | yes | n/a | **EAPI 8: affects only `doexe`/`newexe`** (table 12.17) |
| `insinto` | `insinto <dir>` sets `doins`/`newins` target | yes | **yes** | avoid for well-known dirs — pkgcheck `DeprecatedInsinto` maps `/etc/conf.d`, `/etc/env.d`, `/etc/init.d`, `/etc/pam.d`, `/usr/lib/systemd/{system,user}`, `/usr/share/applications`, fish/zsh completion dirs to dedicated helpers (`codingstyle.py:373-384`) |
| `doins` | `doins [-r] <files|dirs>` → `insinto` dir, mode 0644 or `insopts` | yes | **yes** | `-r` recurses; symlinks installed as symlinks (table 12.11); creates dirs as `dodir` |
| `newins` | `newins <src> <newname>` | yes | **yes** | stdin via `-` |
| `insopts` | `insopts <install-opts>` (e.g. `-m0644`) | yes | n/a | **EAPI 8: affects only `doins`/`newins`** (table 12.16) |
| `into` | `into <prefix>` sets `DESTTREE` for `dobin`/`dosbin`/`dolib*` | yes | **yes** | `DESTTREE` itself is no longer an env var in EAPI 7/8 (Appendix E EAPI 7) |
| `dodir` | `dodir <dirs>` mode 0755 or `diropts` | yes | **yes** | redundant before `doins`/`dodoc`/etc. (pkgcheck `RedundantDodir`, `codingstyle.py:1284`) |
| `diropts` | `diropts <install-opts>` | yes | n/a | in EAPI 8 does **not** affect dirs implicitly created by `doconfd`/`doenvd`/`doheader`/`doinitd` (DM EAPI 8 commands) |
| `keepdir` | `keepdir <dirs>` → dir + `.keep*` file | yes | **yes** | required because empty-dir behaviour is undefined (PMS §13.2.2) |
| `dosym` | `dosym <target> <link>` | yes | **yes** | without `-r`, an absolute target is verbatim → must include `${EPREFIX}`; creates missing parent dirs |
| `dosym -r` | `dosym -r <abs-target> <link>` | **yes (new in 8)**, table 12.15 | **yes** | logical relative path (listing 12.2: `realpath -m -s --relative-to=…`); `-r` with a relative target = error; pkgcheck warns on absolute `dosym` (`AbsoluteSymlink`, `codingstyle.py:331-351`) |
| `fperms` | `fperms <mode> <paths>` (chmod inside image) | yes | **yes** | |
| `fowners` | `fowners <user>:<group> <paths>` (chown inside image) | yes | **yes** | |
| `dodoc` | `dodoc [-r] <files>` → `/usr/share/doc/${PF}/<docinto>` mode 0644 | yes; `-r` since EAPI 4 (table 12.9) | **yes** | without `-r` a directory argument is an error |
| `newdoc` | `newdoc <src> <newname>` | yes | **yes** | |
| `docinto` | `docinto <subdir>` | yes | **yes** | |
| `einstalldocs` | no args; installs `DOCS` then `HTML_DOCS` | yes (table 12.25) | **yes**, unless under `nonfatal` | algorithm 12.4: `DOCS` array/scalar → `dodoc -r`; unset → the `README* ChangeLog AUTHORS NEWS TODO CHANGES THANKS BUGS FAQ CREDITS CHANGELOG` glob (non-empty files only); `HTML_DOCS` → `/usr/share/doc/${PF}/html` |
| `doheader` | `doheader [-r] <files>` → `/usr/include`, 0644 | yes (table 12.10) | **yes** | **EAPI 8: ignores `insopts`** (table 12.16) |
| `newheader` | `newheader <src> <newname>` | yes | **yes** | |
| `dolib.so` | `dolib.so <files>` → libdir under `DESTTREE`, mode 0755 | yes | **yes** | libdir per algorithm 12.3 / `get_libdir` |
| `dolib.a` | `dolib.a <files>`, mode 0644 | yes | **yes** | symlinks installed as relative links |
| `newlib.so` / `newlib.a` | two-arg forms | yes | **yes** | |
| `dolib`, `libopts` | — | **BANNED** (table 12.3, EAPI 7+) | n/a | use `dolib.so`/`dolib.a` |
| `doman` | `doman [-i18n=<lang>] <pages>` → `/usr/share/man/man<N>` | yes | **yes** | `foo.lang.1` → `/usr/share/man/lang/man1/foo.1`; `-i18n` wins (table 12.12). pkgcheck warns on pre-compressed pages (`InstallCompressedManpage`) |
| `newman` | `newman <src> <newname>` | yes | **yes** | |
| `doinfo` | `doinfo <files>` → `/usr/share/info`, 0644 | yes | **yes** | uncompressed only (`InstallCompressedInfo`) |
| `doinitd` / `newinitd` | → `/etc/init.d`, 0755 | yes | **yes** | **EAPI 8: ignores `exeopts`** (table 12.17) |
| `doconfd` / `newconfd` | → `/etc/conf.d`, 0644 | yes | **yes** | **EAPI 8: ignores `insopts`** (table 12.16) |
| `doenvd` / `newenvd` | → `/etc/env.d`, 0644 | yes | **yes** | **EAPI 8: ignores `insopts`** |
| `domo` | `.mo` → `/usr/share/locale/<lang>/LC_MESSAGES/${PN}.mo` | yes (table 12.14: `/usr` since EAPI 7) | **yes** | banned in EAPI 9 |
| `docompress` | `docompress [-x] <paths>` | yes (table 12.18) | not specified; **error outside `src_install`** | default include `/usr/share/{doc,info,man}`, default exclude `/usr/share/doc/${PF}/html`; exclusion beats inclusion; non-existent paths are ignored with a warning (DM <https://devmanual.gentoo.org/ebuild-writing/functions/src_install/docompress/index.html>) |
| `dostrip` | `dostrip [-x] <paths>` | yes (table 12.18, EAPI 7+) | not specified; **error outside `src_install`** | default include `/` unless `RESTRICT=strip` (then empty); use `dostrip -x /opt/foo` for prebuilt blobs |
| `dohtml` | — | **BANNED** (table 12.3, EAPI 7+) | n/a | use `HTML_DOCS` + `einstalldocs`, or `docinto html; dodoc -r` |
| `dohard`, `dosed` | — | **BANNED** (table 12.3, EAPI 4+/6+) | n/a | |
| `einstall` | — | **BANNED** (table 12.3, EAPI 6+) | n/a | use `emake DESTDIR="${D}" install` |
| `domenu` (desktop.eclass) | `domenu <.desktop files|dirs>` → `/usr/share/applications`, 0644 | eclass, EAPI 8 OK | **yes, indirectly** — runs `insopts -m 0644; insinto …; doins` in a subshell and `exit`s its status; `doins` dies, and die works in subshells in EAPI 7/8 (table 12.6) | `/var/db/repos/gentoo/eclass/desktop.eclass:489-512`; preferred over raw `insinto /usr/share/applications` (pkgcheck `DeprecatedInsinto`, `codingstyle.py:381`) |
| `newmenu` (desktop.eclass) | `newmenu <file> <newname>` | eclass | **yes, indirectly** (wraps `newins`) | `desktop.eclass:514-525` |
| `doicon` (desktop.eclass) | `doicon [-s|--size <size>] [-c|--context apps] [-t|--theme hicolor] <icons>` | eclass | **yes, indirectly** (wraps `insinto`+`doins`) | without `--size` installs to `/usr/share/pixmaps`; with `-s 48` → `/usr/share/icons/hicolor/48x48/apps`; valid sizes `16 22 24 32 36 48 64 72 96 128 192 256 512 1024 scalable` — `desktop.eclass:596-627` |
| `newicon` (desktop.eclass) | `newicon [options] <icon> <newname>` | eclass | **yes, indirectly** (wraps `newins`) | `desktop.eclass:629-645` |
| `make_desktop_entry` (desktop.eclass) | `make_desktop_entry [--eapi9] <command> [options]` → `/usr/share/applications` | eclass | dies internally | `desktop.eclass:25-64`; prefer shipping upstream’s `.desktop` via `domenu` |

Non-dying helpers you will also use: `use`, `usev [flag] [output]`, `usex`, `in_iuse`, `has` (PMS §12.3.12/§12.3.13) — these return exit status; they only *error* when given a flag outside `IUSE_EFFECTIVE` (table 12.19: error in EAPIs 4-8) and are forbidden in global scope. `unpack` skips unrecognised extensions silently but aborts if a supported format fails to extract (PMS §12.3.15); it accepts bare filenames (looked up in `DISTDIR`), `./relative` paths, and — in EAPI 6-8 — absolute/relative paths and case-insensitive extension matching (table 12.23).

---

## 6. Versions: format and comparison

### 6.1 Format (PMS §3.2)

```
number-part      [0-9]+(\.[0-9]+)*        e.g. 1, 1.2, 20250101, 1.52386.6
letter           optional single [a-z]    e.g. 1.2b   (NOT a beta marker)
suffixes         zero or more of _alpha _beta _pre _rc _p, each with an optional unsigned integer
revision         optional -r<uint>, absent == -r0
```

Suffix ordering (PMS algorithm 3.6): `_alpha < _beta < _pre < _rc < (none) < _p`. Suffixes chain (`1.0_alpha_pre` < `1.0_alpha_rc1` < `1.0_beta_pre`) — DM <https://devmanual.gentoo.org/ebuild-writing/file-format/index.html#file-naming-rules>. Snapshot conventions: `<last-release>_pYYYYMMDD` or `<next-release>_preYYYYMMDD`; live ebuilds use `9999` (same DM page). A trailing letter sorts **above** the bare version (`1.2b > 1.2`). Package names may not end in a hyphen followed by something version-like (PMS §3.1.2). Binary-only packages get the `-bin` suffix only when they coexist with a source-built package (DM file-format “Binary packages”).

### 6.2 Comparison (PMS §3.3, algorithms 3.1-3.7)

Order of decision: **numeric components → letter → suffixes → revision** (algorithm 3.1).

1. Algorithm 3.2: compare the **first** numeric components as integers. If they differ, that decides the whole comparison — nothing else is examined. Then compare subsequent components pairwise (algorithm 3.3), then more components wins.
2. Algorithm 3.3 caveat: if *either* component after the first has a **leading zero**, both are compared as ASCII strings with trailing zeros stripped (so `1.010 > 1.1` is false: `01` vs `1` string-compares as `0` < `1`).
3. Algorithm 3.5: fewer suffixes wins unless the extra suffix is `_p` (`1.0_p1 > 1.0 > 1.0_rc1`).
4. Algorithm 3.7: revision compared as integer, missing == 0.

### 6.3 Empirical verification on this machine

Command (portage’s own comparator, `dev-lang/python` + installed portage):

```console
$ python3 -c "
from portage.versions import vercmp
for a,b in [('1.52386.6','2.110.0'),('2.110.0','1.52386.6'),('1.0_rc1','1.0'),('1.0_p1','1.0'),
            ('1.0a','1.0'),('1.0-r1','1.0'),('1.10','1.9'),('1.0','1.0.0'),('1.0_alpha','1.0_beta')]:
    print(f'vercmp({a!r}, {b!r}) = {vercmp(a,b)}')"
vercmp('1.52386.6', '2.110.0') = -1
vercmp('2.110.0', '1.52386.6') = 1
vercmp('1.0_rc1', '1.0') = -1
vercmp('1.0_p1', '1.0') = 1
vercmp('1.0a', '1.0') = 1
vercmp('1.0-r1', '1.0') = 1
vercmp('1.10', '1.9') = 1
vercmp('1.0', '1.0.0') = -1
vercmp('1.0_alpha', '1.0_beta') = -1
```

**Answer: `2.110.0` is NEWER than `1.52386.6`** (`vercmp` returns `-1` for `1.52386.6` vs `2.110.0`, i.e. left < right). Per PMS algorithm 3.2 lines 2-5 the decision is made at the very first numeric component (`1 < 2`), so the huge `52386` is never consulted. Corollary for repack ebuilds: if upstream switches numbering schemes (e.g. `1.52386.6` → `2.110.0`), Portage will treat it as an upgrade only if the leading component increases; a scheme change that *lowers* the first component (e.g. `2026.1` → `1.0`) needs `PV` mangling (`MY_PV`) or a `-rN`/epoch-like workaround, because there are no epochs in Gentoo versions (PMS §3.2 lists no epoch).

### 6.4 Version manipulation commands (EAPI 7+, PMS §12.3.14)

`ver_cut <range> [version]`, `ver_rs <range> <sep> [version]`, `ver_test [v1] <op> <v2>` — implemented as shell functions, therefore callable in **global scope**; default input is `${PVR}`. Prefer these over `sed`/`awk`/`cut` for `MY_PV` munging (DM <https://devmanual.gentoo.org/ebuild-writing/variables/index.html#version-and-name-formatting-issues>). They were added in EAPI 7 (PMS Appendix E → EAPI 7, “Version manipulation and comparison commands”).

---

## 7. Extras that bite prebuilt/repack ebuilds (all grounded)

* `.deb` is still an `unpack` format in EAPI 8 (PMS §12.3.15 `unpack-extensions`: deb requires GNU binutils `ar`, or `deb2targz` on non-GNU platforms). Only `.7z`/`.rar`/`.lha` were dropped (table 12.24). `unpacker.eclass` provides `unpack_deb <one deb>` (`/var/db/repos/gentoo/eclass/unpacker.eclass:282-287`) and routes `*.deb` in its dispatcher (`unpacker.eclass:517-518`).
* Canonical in-tree shape of a `.deb` repack (EAPI 8): `/var/db/repos/gentoo/sys-apps/intune-portal/intune-portal-1.2607.4-r1.ebuild` — `EAPI=8` (line 4), `inherit desktop pam prefix readme.gentoo-r1 systemd tmpfiles unpacker xdg` (6), `S="${WORKDIR}"` (11), `LICENSE="all-rights-reserved"` (12), `KEYWORDS="-* ~amd64"` (14), `RESTRICT="bindist mirror"` (15), `QA_PREBUILT="*"` (40), `src_unpack(){ unpack_deb ${A}; … }` (48-51).
* `KEYWORDS="-* ~amd64"` is the documented pattern for binary-only packages (`/var/db/repos/gentoo/skel.ebuild:74-78`; `-*` semantics in PMS §7.3.3).
* Stripping/QA of prebuilt blobs: `QA_PREBUILT` (fnmatch patterns relative to the image dir) feeds all other `QA_*` variables — DM <https://devmanual.gentoo.org/ebuild-writing/variables/index.html#qa-control-variables>; per-file strip control via `dostrip -x /opt/foo` (PMS §12.3.11), whole-package via `RESTRICT="strip"` (PMS §7.3.6).
* `RESTRICT` tokens recognised by PMS are exactly `mirror fetch strip userpriv test` (PMS §7.3.6); `bindist` is a Portage-specific token — PMS permits extra tokens but ebuilds must not *depend* on them (PMS §7.3.6 last paragraph; DM variables §RESTRICT).
* Desktop integration: use `domenu`/`newmenu`/`doicon`/`newicon` rather than `insinto /usr/share/applications` (pkgcheck `DeprecatedInsinto`, `codingstyle.py:373-384`); put `dev-util/desktop-file-utils`-style post-install tools in **`IDEPEND`** and call them from `pkg_postinst` (DM <https://devmanual.gentoo.org/ebuild-writing/eapi/index.html>, IDEPEND example with `xdg-utils`).
* Coding style enforced by policy: tabs for indentation, `${foo}` not `$foo`, `[[ ]]` not `[ ]` — **PG 0101**; ≤80 columns preferred (DM file-format “Indenting and whitespace”), pkgcheck `ExcessiveLineLength` triggers at 120 (`codingstyle.py:1456-1459`); UTF-8 with Unix newlines (PMS §6; GLEP 31).

---

### Anything not verified

* PMS anchors were read through the single-page HTML render; section *numbers* are quoted from that render and are stable, but I did not cross-check the per-section anchor hashes for every citation (the two DM-supplied ones, `#x1-250003.2` for §3.2 and `#x1-260003.3` for §3.3, are confirmed).
* No `app-doc/pms` package is installed locally, so the PDF “EAPI cheat sheet” (PMS Appendix F) could not be consulted offline.
* pkgcheck behaviour above is read from its source, not from executing `pkgcheck scan`.
