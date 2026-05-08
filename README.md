# showcase-aws-lc-binary-size

Minimal repro for the aws-lc-rs binary size regression vs ring, and the
CFLAGS workaround. Does an HTTPS GET to `https://am.i.mullvad.net/json`
and prints the response.

## Run the benchmark

```sh
./build-all-versions.sh
```

Builds ring (baseline) and every combination of three aws-lc-sys size
knobs, then prints a comparison table. Works on Linux, macOS and Windows
(MSYS/Git Bash).

The script clears any `AWS_LC_SYS_*CFLAGS*` in the surrounding shell
and passes its own value via `AWS_LC_SYS_TARGET_CFLAGS`, which outranks
the per-target entries in `.cargo/config.toml`, so the recorded sizes
reflect only the script's flags.

Out of the box aws-lc-rs more than doubles the binary vs ring; the
flags in `.cargo/config.toml` recover ~80% of that.

## The flags

- `-DOPENSSL_SMALL`: drops a 148 KiB precomputed P-256 table plus
  ~30 KiB of Ed25519 base-point tables (curve25519). Slows Ed25519
  signing 1.5-2x and ECDSA P-256 verify a few x.
- `-DMY_ASSEMBLER_IS_TOO_OLD_FOR_512AVX`: excludes ~660 KiB of AVX-512
  AES-GCM/AES-XTS asm. Falls back to AVX2/AES-NI. x86_64-only.
- `/Gw` (MSVC only): per-global COMDAT sections so the linker can drop
  unreferenced data tables. `/Gy` is already implied by `/O1`/`/O2`.
  The GCC equivalent `-ffunction-sections -fdata-sections` is
  unnecessary on Linux/macOS/Android because cc-rs already adds it,
  and intentionally skipped by cc-rs on iOS.

Optional, not in `.cargo/config.toml`:

- `AWS_LC_SYS_NO_JITTER_ENTROPY=1`: drops the bundled
  jitterentropy-library (~20 KiB). aws-lc still seeds its DRBG from
  the OS RNG (getentropy/getrandom/BCryptGenRandom). Don't set this
  for FIPS builds.

`aws-lc-sys` lowercases the target triple in the per-target env-var
name (unlike `cc-rs` which uppercases), so the variable is
`AWS_LC_SYS_CFLAGS_x86_64_unknown_linux_gnu`, not `..._X86_64_...`.

Tracking issue: <https://github.com/aws/aws-lc-rs/issues/745>.
