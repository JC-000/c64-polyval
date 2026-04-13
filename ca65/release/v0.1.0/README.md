## c64-polyval v0.1.0

### Version

`v0.1.0` - first packaged ca65/ld65 library release of c64-polyval.

### What this is

A Commodore 64 / 6502 assembly library implementing:

- POLYVAL (RFC 8452 section 3), the carry-less universal hash underlying
  AES-GCM-SIV. Byte-accurate against the RFC 8452 test vectors.
- AES-256 encrypt and decrypt primitives (single-block, software T-table-
  free).
- AES-256-GCM-SIV authenticated encryption (RFC 8452) up to 64 bytes of
  plaintext per call. AAD is not supported.

Target toolchain: cc65 suite (ca65 assembler + ld65 linker + ar65
librarian). Consumers import the archive, include the API header, and link
their own code against it.

### Audit state

- Full in-repo test suite passes: 217/217 POLYVAL direct tests, 159/165
  GCM-SIV end-to-end tests (6 pre-existing AAD-not-supported skips).
- Byte-exact opcode parity with the original ACME assembler build of
  c64-polyval across the entire ~4500 bytes of crypto code.
- `polyval_multiply` is cycle-identical to the ACME baseline
  (3745 cy min). `polyval_precompute_table` is 110 cy faster than the ACME
  baseline.
- `make lib` (library-only link) and `make consumer-check` (downstream
  import rehearsal) both pass.

See `attestation/test_results.txt` and `attestation/benchmark_results.txt`
for full details.

### Profiles

Two archives are shipped. Pick one at link time; do not link both.

| File              | Multiply backend           | Per-block cost | Table RAM |
| ----------------- | -------------------------- | -------------- | --------- |
| `polyval_long.lib`  | Shoup 8-bit fused shift+reduce | ~4000 cy    | ~8.5 KB   |
| `polyval_short.lib` | 4-bit nibble Shoup             | ~19000 cy   | ~256 B    |

The LONG profile is the right choice for session-stable-H workloads
(TLS 1.3, WireGuard) where the large table is rebuilt rarely relative to
the number of blocks processed. The SHORT profile is better for
small-message workloads where H is rederived per message and RAM is at a
premium.

### Consumer usage

In your assembly source:

    .include "abi_v1.inc"
    .include "constants_lib.inc"

    .import polyval_init, polyval_update, polyval_multiply
    .import aes_encrypt_block, gcmsiv_encrypt, gcmsiv_decrypt

Assemble and link:

    ca65 --cpu 6502 -I . -D POLYVAL_PROFILE=2 consumer.s -o consumer.o
    ld65 -C consumer.cfg -o consumer.prg consumer.o polyval_long.lib

A worked example lives in `examples/`: `consumer_stub.s`, `consumer.cfg`,
and `Makefile.example`.

### ABI stability

- `include/abi_v1.inc` declares the stable public ABI. Every symbol in
  that file is promised stable for all v0.1.x releases. Changes to names,
  entry semantics, or data layouts in this set are breaking changes that
  require a major version bump.
- `include/test_probes.inc` is NOT stable. It exists so the upstream
  c64-polyval test suite can poke inner helpers directly; downstream
  consumers must not import from it. Symbols in this file may be renamed,
  inlined away, or removed in any v0.1.x point release without notice.
- `include/polyval_api.inc` is copied verbatim from the library source as
  documentation. If it describes a symbol that is NOT in abi_v1.inc, that
  symbol is still internal - the header comment is historical.
- The archives may contain additional exported symbols (cross-.o linker
  artifacts) that are not declared in either include file. Consumers must
  treat any symbol not in abi_v1.inc as if it did not exist.

### Zero-page layout

The library owns the following zero-page bytes at fixed addresses. These
ARE part of the v0.1 ABI; a consumer integrating c64-polyval must ensure
no other code uses them concurrently.

| ZP range  | Purpose                                               |
| --------- | ----------------------------------------------------- |
| `$10-$1F` | `polyval_acc` - 16-byte POLYVAL accumulator          |
| `$20-$2F` | `pv_mul_input` - 16-byte multiply input scratch      |
| `$30`     | `pv_mul_nibble` - 1-byte nibble param                |
| `$02-$09` | AES / pointer scratch (`zp_ptr2`, `zp_round`, etc.)  |
| `$fb-$ff` | `zp_ptr`, `zp_temp`, `zp_count`                      |

The equates in `constants_lib.inc` are wrapped in `.ifndef`, so a host
with its own ZP plan can pre-define the symbols before `.include`ing the
header. Doing so is only safe if the host has verified non-overlap with
the library's actual usage.

### Known limitations

- GCM-SIV associated data (AAD) is not supported. Only empty-AAD messages
  may be authenticated. This matches the original c64-polyval
  implementation; it is a v0.1-era limitation, not a regression.
- GCM-SIV plaintext length is limited to 0..64 bytes per call.
- Routines are NOT IRQ-safe and NOT reentrant. They clobber shared ZP
  scratch. Callers must mask interrupts or otherwise serialize access.

### License

No top-level LICENSE file is present in the parent repository at the time
of this release. See the parent repo for licensing terms.
