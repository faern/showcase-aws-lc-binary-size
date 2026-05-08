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

`-ffunction-sections -fdata-sections` (GCC/Clang) and `/Gw` (MSVC) were
also tested but had no measurable effect on this build profile: cc-rs
already adds the GCC pair on Linux/macOS/Android, and rust-lld's LTO
already strips unreferenced functions and globals on MSVC.

Optional, not in `.cargo/config.toml`:

- `AWS_LC_SYS_NO_JITTER_ENTROPY=1`: drops the bundled
  jitterentropy-library (~20 KiB). aws-lc still seeds its DRBG from
  the OS RNG (getentropy/getrandom/BCryptGenRandom). Don't set this
  for FIPS builds.

`aws-lc-sys` lowercases the target triple in the per-target env-var
name (unlike `cc-rs` which uppercases), so the variable is
`AWS_LC_SYS_CFLAGS_x86_64_unknown_linux_gnu`, not `..._X86_64_...`.

Tracking issue: <https://github.com/aws/aws-lc-rs/issues/745>.

## Results

### Linux (`x86_64-unknown-linux-gnu`)

| Build                                                                                              | Size (KiB) | Diff vs ring |
| -------------------------------------------------------------------------------------------------- | ---------: | -----------: |
| ring                                                                                               |       1806 |            0 |
| aws-lc (default)                                                                                   |       3680 |    +1873 KiB |
| aws-lc (`-ffunction-sections -fdata-sections`)                                                     |       3680 |    +1873 KiB |
| aws-lc (`-DOPENSSL_SMALL`)                                                                         |       3176 |    +1369 KiB |
| aws-lc (`-ffunction-sections -fdata-sections -DOPENSSL_SMALL`)                                     |       3176 |    +1369 KiB |
| aws-lc (`-DMY_ASSEMBLER_IS_TOO_OLD_FOR_512AVX`)                                                    |       2453 |     +647 KiB |
| aws-lc (`-ffunction-sections -fdata-sections -DMY_ASSEMBLER_IS_TOO_OLD_FOR_512AVX`)                |       2453 |     +647 KiB |
| aws-lc (`-DOPENSSL_SMALL -DMY_ASSEMBLER_IS_TOO_OLD_FOR_512AVX`)                                    |       2137 |     +331 KiB |
| aws-lc (`-ffunction-sections -fdata-sections -DOPENSSL_SMALL -DMY_ASSEMBLER_IS_TOO_OLD_FOR_512AVX`) |       2137 |     +331 KiB |

### macOS (`aarch64-apple-darwin`)

| Build                                                                                              | Size (KiB) | Diff vs ring |
| -------------------------------------------------------------------------------------------------- | ---------: | -----------: |
| ring                                                                                               |       1608 |            0 |
| aws-lc (default)                                                                                   |       2662 |    +1054 KiB |
| aws-lc (`-ffunction-sections -fdata-sections`)                                                     |       2662 |    +1054 KiB |
| aws-lc (`-DOPENSSL_SMALL`)                                                                         |       2194 |     +586 KiB |
| aws-lc (`-ffunction-sections -fdata-sections -DOPENSSL_SMALL`)                                     |       2194 |     +586 KiB |
| aws-lc (`-DMY_ASSEMBLER_IS_TOO_OLD_FOR_512AVX`)                                                    |       2662 |    +1054 KiB |
| aws-lc (`-ffunction-sections -fdata-sections -DMY_ASSEMBLER_IS_TOO_OLD_FOR_512AVX`)                |       2662 |    +1054 KiB |
| aws-lc (`-DOPENSSL_SMALL -DMY_ASSEMBLER_IS_TOO_OLD_FOR_512AVX`)                                    |       2194 |     +586 KiB |
| aws-lc (`-ffunction-sections -fdata-sections -DOPENSSL_SMALL -DMY_ASSEMBLER_IS_TOO_OLD_FOR_512AVX`) |       2194 |     +586 KiB |

### macOS (`x86_64-apple-darwin`)

| Build                                                                                              | Size (KiB) | Diff vs ring |
| -------------------------------------------------------------------------------------------------- | ---------: | -----------: |
| ring                                                                                               |       1692 |            0 |
| aws-lc (default)                                                                                   |       3542 |    +1850 KiB |
| aws-lc (`-ffunction-sections -fdata-sections`)                                                     |       3542 |    +1850 KiB |
| aws-lc (`-DOPENSSL_SMALL`)                                                                         |       3029 |    +1337 KiB |
| aws-lc (`-ffunction-sections -fdata-sections -DOPENSSL_SMALL`)                                     |       3029 |    +1337 KiB |
| aws-lc (`-DMY_ASSEMBLER_IS_TOO_OLD_FOR_512AVX`)                                                    |       2274 |     +582 KiB |
| aws-lc (`-ffunction-sections -fdata-sections -DMY_ASSEMBLER_IS_TOO_OLD_FOR_512AVX`)                |       2274 |     +582 KiB |
| aws-lc (`-DOPENSSL_SMALL -DMY_ASSEMBLER_IS_TOO_OLD_FOR_512AVX`)                                    |       1962 |     +269 KiB |
| aws-lc (`-ffunction-sections -fdata-sections -DOPENSSL_SMALL -DMY_ASSEMBLER_IS_TOO_OLD_FOR_512AVX`) |      1962 |     +269 KiB |

### Windows (`x86_64-pc-windows-msvc`)

| Build                                                              | Size (KiB) | Diff vs ring |
| ------------------------------------------------------------------ | ---------: | -----------: |
| ring                                                               |       1838 |            0 |
| aws-lc (default)                                                   |       2539 |     +700 KiB |
| aws-lc (`/Gw`)                                                     |       2539 |     +700 KiB |
| aws-lc (`-DOPENSSL_SMALL`)                                         |       2184 |     +345 KiB |
| aws-lc (`/Gw -DOPENSSL_SMALL`)                                     |       2184 |     +345 KiB |
| aws-lc (`-DMY_ASSEMBLER_IS_TOO_OLD_FOR_512AVX`)                    |       2515 |     +676 KiB |
| aws-lc (`/Gw -DMY_ASSEMBLER_IS_TOO_OLD_FOR_512AVX`)                |       2515 |     +676 KiB |
| aws-lc (`-DOPENSSL_SMALL -DMY_ASSEMBLER_IS_TOO_OLD_FOR_512AVX`)    |       2160 |     +321 KiB |
| aws-lc (`/Gw -DOPENSSL_SMALL -DMY_ASSEMBLER_IS_TOO_OLD_FOR_512AVX`) |      2160 |     +321 KiB |
