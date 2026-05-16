# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Releases: https://github.com/JC-000/c64-polyval/releases — tagged releases
track `MAJOR.MINOR.PATCH` and are the supported consumption points for
downstream projects (see `API.md` §8 for the integration contract).

## v0.2.0 — 2026-05-15

- Repackage to c64-nist-curves library format
- Retire ACME assembler support; consolidate to ca65 (cc65 toolchain)
- Replace dual root/ca65 Makefiles with single top-level Makefile
- Move ABI surface from `abi_v1.inc` to `src/exports.inc`
- Add MIT LICENSE
- Source tarball release format (`make dist VERSION=…`) replaces `.lib` archive shipping
- Preserve `ca65/release/v0.1.0/` as historical artifact

## v0.1.0 — (earlier)

- Initial public release. POLYVAL + AES-256-GCM-SIV with ca65+ACME parallel
  builds, LONG/SHORT profiles, `.lib` archive release format.
- Frozen at `ca65/release/v0.1.0/`.
