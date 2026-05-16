# c64-polyval v0.2.0 — 2026-05-15

This is a **repackage** release. The cryptographic library code is
**byte-equivalent** to v0.1.0 modulo relocation-operand bytes from the
single-Makefile / flat-`src/` reshuffle; the public ABI symbol set is
unchanged. v0.2.0 retires the ACME assembler parallel build, retires
the `.lib` archive shipping format, consolidates to a single top-level
ca65/ld65 Makefile, and switches to a reproducible source-tarball
release format that mirrors the sibling `c64-nist-curves` repository.

The full per-change log is in [`CHANGELOG.md`](../CHANGELOG.md); this
file is the concise release summary.

## What's in

- **Repackage to c64-nist-curves library format**. Flat `src/` layout
  with library files and demo-app files side by side; consumer link
  list documented in `API.md` §8.
- **ACME assembler support retired.** Library and demo-app are now
  ca65-only (cc65 toolchain). The historical ACME parallel build is
  preserved at `ca65/release/v0.1.0/` for archaeology but is no longer
  exercised by the test harness.
- **Dual root/`ca65/` Makefiles collapsed to one top-level Makefile.**
  Targets: `all`, `lib` (library-only verification link at $4000),
  `consumer-check` (assembles `test/consumer_stub.s` against the
  public ABI to prove the import path is stable), `run` (launch VICE
  with labels loaded), `clean`, and the new `dist`.
- **ABI surface moved from `abi_v1.inc` to `src/exports.inc`.**
  Stable cross-module `.global` / `.globalzp` declarations live in
  one place; consumers `.import` what they need. The historical
  `abi_v1.inc` symbol set is preserved verbatim under
  `ca65/release/v0.1.0/include/` for backward reference.
- **MIT LICENSE added.**
- **Source tarball release format** (`make dist VERSION=v0.2.0`)
  replaces the v0.1.0 `.lib` archive shipping format. The artifact is
  reproducible: same `VERSION` against the same source tree always
  produces a byte-identical tarball (fixed mtime, fixed
  owner/group/numeric, `gzip -n` drops the gzip timestamp). The
  canonical vendoring file list lives in `tools/build_release.sh`.
- **Historical v0.1.0 artifact preserved** at `ca65/release/v0.1.0/`.
  Not shipped in the v0.2.0 tarball; consumers wanting the frozen
  v0.1.0 `.lib` should check out the `lib-v0.1.0` git tag.

## What's NOT shipped

v0.2.0 is a **repackage**. Library behaviour is unchanged from v0.1.0;
the link products are byte-equivalent against the
`ca65/release/v0.1.0/` artifacts modulo relocation-operand bytes from
the layout reshuffle. No new public symbols, no behaviour fixes, no
new cryptographic primitives. Specifically:

- **No new public API surface.** POLYVAL, AES-256, and AES-256-GCM-SIV
  entry points are unchanged in signature and contract.
- **No constant-time hardening.** The library remains non-constant-time
  on all paths (public-input use only).
- **No AAD support.** GCM-SIV still authenticates empty-AAD messages
  only (see Known Limitations §3).
- **No bulk-encryption support.** GCM-SIV plaintext is still capped at
  64 bytes per call (see Known Limitations §4).

## Upgrade notes for consumers

- **Semver minor bump.** Additive tooling only. Existing v0.1.0 symbol
  calls remain ABI-compatible.
- **`#include "abi_v1.inc"` callers**: update to
  `.include "exports.inc"`. The symbol names are unchanged.
- **`.lib` archive consumers**: the `.lib` shipping format is no longer
  produced. Vendor the `src/` tree from the v0.2.0 tarball instead and
  link against your build's ca65/ld65. Refer to `API.md` §8 for the
  consumer link list (library files only; omit the demo-app files
  listed in §8.2).

## Attestation

`c64-polyval-v0.2.0.tar.gz` is produced reproducibly by
`make dist VERSION=v0.2.0`. Canonical artifact:

| Field      | Value |
|------------|-------|
| Filename   | `c64-polyval-v0.2.0.tar.gz` |
| **Size**   | 55713 bytes |
| **SHA256** | `2a0d42ad81bf53a1f246a4e9ab318e4416b596bb4bff4ce0943cd5034bb65f8f` |

Re-running `make dist VERSION=v0.2.0` against this source tree must
reproduce the recorded SHA256 byte-for-byte: every staged file's
mtime is forced to `2026-05-15T00:00:00Z`, owner/group are pinned to
`0:0` (numeric), and `gzip -n` drops the gzip timestamp+filename
header. The canonical vendoring file list lives in
`tools/build_release.sh`.

### Tarball contents

The tarball contains, under the `c64-polyval-v0.2.0/` prefix:

- `README.md`, `API.md`, `CHANGELOG.md`, `LICENSE`, `VERSION`
- `docs/RELEASE_NOTES_v0.2.0.md` (this file)
- `src/*.s` (library + demo-app sources)
- `src/*.inc` (public headers: `exports.inc`, `polyval_api.inc`,
  `constants_lib.inc`, `constants_app.inc`)
- `src/c64.cfg`, `src/lib_only.cfg` (ld65 linker configs)
- `src/include/zp.inc` (ZP symbol template for downstream ports)

The tarball does NOT contain `build/`, `tools/`, `test/`, the
`ca65/release/v0.1.0/` historical tree, or any VCS / editor metadata.

## Known limitations

Carried over from v0.1.0; see `API.md` §6 for the full list. The
highlights downstream callers most often need to know:

1. **No AAD.** GCM-SIV authenticates empty-AAD messages only. Calls
   with non-empty AAD silently diverge from any reference
   implementation that mixes AAD into the tag.
2. **64-byte plaintext cap.** GCM-SIV `pt_buf` / `ct_buf` / `dec_buf`
   are 64 B each. Bulk encryption must be chunked at the protocol
   layer — but RFC 8452's nonce-misuse-resistant construction does not
   support chunking natively, so callers wanting bulk encryption
   should pick a different mode.
3. **Not IRQ-safe.** Callers must mask IRQs around library work or
   serialise on a single thread of control.
4. **Not re-entrant.** Library routines share global ZP scratch and
   table state.
5. **Non-constant-time on every path.** Public-input use only; do not
   process secret-key material under attacker-visible timing.
6. **`polyval_precompute_table` destroys `polyval_h`.** Save H first
   if you need it after precompute.
7. **GCM-SIV requires pre-expanded AES round keys.** Call
   `aes_key_expansion` once after staging `aes_current_key`.

See `API.md` §6 for items 7–11 (precompute cost, Poly1305 distinction,
TLS-GHASH byte-reversal note, GCM vs GCM-SIV counter format, and the
constant-time disclaimer).

## Cross-references

- Sibling project: `c64-nist-curves` v0.2.0 (the source-tarball release
  format and `tools/build_release.sh` recipe shape were ported from
  there).
- Historical v0.1.0 artifact: `ca65/release/v0.1.0/` (frozen; git tag
  `lib-v0.1.0`).
