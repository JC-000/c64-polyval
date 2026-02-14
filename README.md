# c64-polyval

POLYVAL (GF(2^128) universal hash from RFC 8452) implementation for the Commodore 64, intended for use with AES-256-GCM-SIV.

## Building

Requires the [ACME cross-assembler](https://sourceforge.net/projects/acme-crossass/).

```
make        # assemble
make run    # assemble and launch in VICE
make clean  # remove build artifacts
```

## Project Structure

- `src/` - 6502 assembly source files
- `build/` - compiled .prg output (gitignored)
- `tools/` - Python test scripts
- `test/` - test vectors

## Status

Work in progress. The long-term goal is to replace the simplified CBC-MAC in c64-aes256-ecdsa with a true POLYVAL implementation.
