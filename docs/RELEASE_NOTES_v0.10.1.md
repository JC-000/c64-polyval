# c64-polyval v0.10.1 — 2026-09-06

Corrective **PATCH**. v0.10.0 was tagged four hours earlier and shipped
four real defects — two introduced by that release's own §6.1 work, one a
false statement in its central argument, and one an incomplete sweep it
claimed was complete. An adversarial review of the branch was
commissioned before tagging; its report arrived after. Tags are immutable
in this fleet, so this is the remedy.

**No behavioural change.** PRGs are byte-identical to v0.9.0 on all three
profiles. `LIB_POLYVAL_ABI_VERSION` stays **1** — though the published
*reason* was wrong and is corrected below.

## The two defects v0.10.0 introduced

### 1. The shipped example cfg silently collided a consumer's zero page

`src/polyval-example.cfg` declared `ZP: start = $0002`. c64-polyval claims
`polyval_zp_ptr2` at `$02-$03` and `polyval_aes_round` at `$04`
(`src/zp_config.s`). So a consumer copying the template and declaring
anything in `.segment "ZEROPAGE"` landed straight on top of the library.

Measured with the real shipped trio — a consumer with
`my_ptr: .res 2` / `my_count: .res 1`:

```
ld65 map:  ZEROPAGE   000002  000004  000003
exit 0, zero warnings, zero errors
```

**Nothing can diagnose this.** The library's slots are `.exportzp`
equates, not allocations, so ld65's zero-page allocator cannot see them;
the link is clean and the corruption surfaces at runtime inside whichever
routine reads the slot that got overwritten. It was a first-use trap in a
file whose opening line reads "COPY THIS INTO YOUR OWN TREE", and it was
the one §2 hazard the cfg failed to annotate while annotating two that
are far less likely to bite.

The area now starts at **`$31`**, the largest gap between the library's
three discontiguous regions:

| Region | Bytes | Slots |
|---|---:|---|
| `$02-$09` | 8 | `polyval_zp_ptr2`, `polyval_aes_round`/`_col`, `polyval_aes_tmp1..tmp4` |
| `$10-$30` | 33 | `polyval_acc` (16), `pv_mul_input` (16), `pv_mul_nibble` (1) |
| `$fb-$fe` | 4 | `polyval_zp_ptr`, `polyval_zp_temp`, `polyval_zp_count` |

That leaves the consumer `$31-$FA`, 202 bytes, clear of all three. The
cfg now carries the map, the measured failure, and the supported way out
if 202 bytes is not enough — relocate *the library's* slots via §2, which
is what `CONTRACT_ZP_DEFINES` is for:

```sh
make lib CONTRACT_ZP_DEFINES='-D polyval_acc=0x40 -D pv_mul_input=0x50'
```

A `LIB_POLYVAL_ZP_USAGE_BYTES` assert joined the cfg's recommended-asserts
block, with an explicit statement that it bounds the **total** and that no
link-time assert can catch an address overlap — that one is a review
obligation, not an automatable one.

### 2. `consumer-check-shipped` bypassed the PIN guard, then certified the wrong artifact

The new phony target depends on `$(LIB_DIR)/polyval.a` but had no `PIN_`
row. `PIN_lib` and `PIN_lib-polyval-gcmsiv` exist precisely because those
phonies reach that path; this was a third one and was not added. The
guard's `$(foreach g,$(MAKECMDGOALS),…)` inspects the named **goal**, not
the files a goal eventually builds, so it never fired:

```
$ make consumer-check-shipped POLYVAL_PROFILE=short
consumer-check-shipped: … are a sufficient consumer surface …
exit 0

$ ar65 t build/lib/polyval.a                    →  polyval_short.o
$ od65 --dump-exports build/lib_manifest.o      →  RESIDENT_BYTES = 16128   (the SHORT figure)
```

`build/lib/polyval.a` — the canonical **LONG** AEAD name — held
`polyval_short.o` with a SHORT manifest, exit 0, no diagnostic; and the
new shipped-surface check then certified that mis-pinned archive as sound
and left it in `build/lib/` for whatever ran next. That is verbatim the
failure the Makefile's own §6.3 block documents and the `PIN_` table
exists to prevent.

Fixed by `PIN_consumer-check-shipped = long`. The mis-pinned invocation
is now rejected at parse time, before any object is assembled; the
correct invocation is unaffected.

## The sweep v0.10.0 said was complete, and was not

v0.10.0 presented "removed at contract v1.0" as the one class of text it
*had* corrected. Two of the occurrences survived:

- **`docs/precalc-tables.md`** — and this file **ships in the release
  tarball**, staged explicitly by `tools/build_release.sh`. Confirmed
  present in `c64-polyval-v0.10.0.tar.gz`.
- **`API.md` §9.7**, the worked consumer-integration example.

Both told a reader the bare exports are removed at contract v1.0, which
v1.0.0 explicitly deferred to a future MAJOR. Both were missed for the
same reason: the phrase wraps across a line break and the sweep grepped
line-at-a-time. Re-checked with `tr '\n' ' '` over every tracked `.md`,
`.s` and `.inc`; the only remaining occurrences are self-referential ones
describing the correction.

## `LIB_POLYVAL_ABI_VERSION` — right answer, wrong reason

The counter holds at 1. v0.10.0 said so for a reason that is **false as
written**, in its release notes, in `API.md` §9.1 and in `CLAUDE.md`:
that `gcmsiv_decrypt`'s reject path is "indistinguishable from a tag
failure on **every** documented post-condition".

v0.8.0's banner carries a `memory (always)` line that argument never
reached:

| v0.8.0 documented | `@reject_len` actual |
|---|---|
| `A=1`, `Z=0`, `gcmsiv_tag_valid = 0` | matches |
| `gcmsiv_dec_buf` zeroed (64 B) | matches |
| `gcmsiv_tag` restored to received tag | matches (untouched) |
| `aes_current_key` preserved | matches |
| `aes_expanded_key` restored to master schedule | holds **derivatively only** — never touched, and Entry already required it to *be* the master schedule |
| `polyval_*` clobbered | **differs** |
| `aes_state` clobbered | **differs** |
| `gcmsiv_counter`/`keystream`/`idx` clobbered | **differs** |

All three misses share one cause: the path returns before
`gcmsiv_derive_keys` runs. The `gcmsiv_encrypt` half had a matching gap —
it argued only about `A` being undefined at v0.8.0, while that banner also
documented **unconditional** memory outputs (`gcmsiv_ct_buf = ciphertext`,
`gcmsiv_tag = 16-byte tag`) which the reject path does not produce.

**The argument that actually holds**, and covers both entry points and
every post-condition at once: v0.8.0's *Entry* banner on
`gcmsiv_encrypt` and `gcmsiv_decrypt` alike already read
`gcmsiv_pt_len = plaintext length (0..64)`. `pt_len > 64` was outside the
documented input domain **before** the change, so §7's "can a consumer
conforming to the previously documented contract be broken" test cannot
fire — no conforming consumer reaches the reject path on either routine.
It also does not depend on any property of `@reject_len` that a future
edit could silently invalidate, which the old argument did.

Both weaker arguments are now recorded in `CLAUDE.md` as explicitly
rejected, so the next person does not re-derive them.
[c64-lib-contract#180](https://github.com/JC-000/c64-lib-contract/issues/180)
was corrected in place, having been filed with the weaker reasoning.

**A real consumer-visible consequence that does not move the counter:** a
caller reading "clobbered" as *scrubbed* will find the previous call's
derived-key material still in `polyval_htable*` and `gcmsiv_keystream`
after a length rejection. The reject path wipes `gcmsiv_dec_buf` and
nothing else. That is defensible — "clobbered" is a permission, not a
guarantee of erasure — but it now says so.

The source banner that produced the error is fixed too
([#82](https://github.com/JC-000/c64-polyval/issues/82)): the
`memory (always)` line sat eight lines below a reject block stating "no
key derivation is performed", contradicting itself. It is now split by
outcome. Comment-only; PRG verified byte-identical.

## The shipped header now declares something

Through v0.10.0, `build/lib/polyval.inc` was a comment block plus three
profile-selector equates and **declared nothing** — while the Makefile,
`API.md` §9.5 and the release notes all justified shipping it as the
consumer's "declaration of the public symbols", and
`test/consumer_stub_shipped.s` hand-wrote 27 `.import` lines. That the
stub had to was the evidence.

The fleet settles the shape: `c64-x25519`'s shipped `src/x25519.inc`
carries 31 declarations. Ours now carries 29, as `.global` rather than
`.import` so the file stays safe to include from a translation unit that
*defines* a symbol as well as one that imports it.

Two properties were measured before adding them, because both would have
punished consumers silently:

| Property | Measured |
|---|---|
| An unreferenced declaration of a symbol the linked archive does not contain | does **not** fail the link — a POLYVAL-only consumer linking `polyval-long.a` is unaffected by the AEAD names |
| An unreferenced declaration | does **not** drag its archive member into the image — baseline stub 4166 B, and 4166 B with all nine AES/GCM-SIV entry points declared and none called |

Suppress with `-D POLYVAL_API_NO_DECLS=1` if you would rather author your
own import list. **Zero page is deliberately not declared**: `.importzp`
is a different directive with a different address size, and a consumer
overriding a slot via `CONTRACT_ZP_DEFINES` must not also import it
(§6.2 — a `-D` of an imported name is `Symbol already defined`).

`test/consumer_stub_shipped.s` no longer hand-writes those imports, so the
guard now proves the header declares as well as proving the shipped set is
sufficient. Shown capable of failing: `-D POLYVAL_API_NO_DECLS=1` stops it
at `Symbol 'gcmsiv_encrypt' is undefined`.

## Verification

| Check | Result |
|---|---|
| `run_all_tests.py --seed 8452` | **1253/1253 pass, 6 skip, 0 fail** on long, short and compact |
| All seven archive targets | build and stage all three shipped files |
| Example cfg vs all seven archives | link, 0 warnings |
| Consumer ZEROPAGE under the new cfg | lands `$31-$33`, clear of all three library regions |
| `make consumer-check-shipped POLYVAL_PROFILE=short` | **rejected at parse time** (was: exit 0, wrong archive) |
| `lib-verify` / `consumer-check` / `-noaes` / `-shipped` | all clean |
| PRG byte-identity vs `v0.9.0` | identical on all three profiles |
| `VERSION` / `lib_version.s` / `API.md` §9.1 | agree at `0.10.1`, ABI 1 |

## If you took v0.10.0

**Re-take the example cfg.** If you copied `build/lib/polyval-example.cfg`
from v0.10.0 and put your own variables in `.segment "ZEROPAGE"`, they are
very likely sitting on c64-polyval's slots with no diagnostic anywhere.
Check your link map: anything the consumer allocates below `$31` overlaps
`$02-$09` or `$10-$30`. Nothing else in v0.10.0 requires action — the
archives themselves are unchanged.

## Contract currency

Unchanged: **SPEC v1.1.0** (2026-09-03). Nothing in this release changes
which sections apply, and no conformance claim moves. §3 and §8.1–§8.3
remain N/A; the §1 and §8.4 zero-consumer carve-outs remain inapplicable.

## Attestation

`c64-polyval-v0.10.1.tar.gz` is produced reproducibly by
`make dist VERSION=v0.10.1`. Canonical artifact:

| Field      | Value |
|------------|-------|
| Filename   | `c64-polyval-v0.10.1.tar.gz` |
| **Size**   | 136073 bytes |
| **SHA256** | `37c7a3f1fc2ebb44b22afb3817fc602440851c1d48125e9faed97e97e34d9da4` |

Re-running `make dist VERSION=v0.10.1` against this source tree must
reproduce the recorded SHA256 byte-for-byte: every staged file's mtime
is forced to `2026-09-06T00:00:00Z`, owner/group are pinned to `0:0`
(numeric), and `gzip -n` drops the gzip timestamp+filename header. The
canonical vendoring file list lives in `tools/build_release.sh`.
