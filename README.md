# showcase-aws-lc-binary-size

Minimal repro for the aws-lc-rs binary size regression vs ring, and the
CFLAGS-based mitigation. Just does an HTTPS GET to
`https://am.i.mullvad.net/json` and prints the response.

Linux x86_64 only.

## Three builds

```sh
# 1. ring (baseline)
cargo build --release --no-default-features --features ring

# 2. aws-lc-rs, no size CFLAGS (override the .cargo/config.toml [env] entries)
AWS_LC_SYS_CFLAGS= AWS_LC_SYS_CFLAGS_x86_64_unknown_linux_gnu= \
    cargo build --release --no-default-features --features aws-lc \
    --target-dir target-aws-lc-default

# 3. aws-lc-rs with size CFLAGS (uses .cargo/config.toml as-is)
cargo build --release --no-default-features --features aws-lc \
    --target-dir target-aws-lc-trim
```

The override in (2) is needed because cargo merges `.cargo/config.toml`
files from the current directory up to `$HOME`. If you're running this from
inside another repo with its own `[env]` section, those entries also apply
unless you blank them on the command line.

## Observed sizes (rustc 1.95.0, opt-level=s + LTO + strip)

| build | bytes | text | delta vs ring |
| --- | ---: | ---: | ---: |
| ring | 1,849,528 | 1,790,272 | 0 |
| aws-lc-rs default | 3,768,296 | 3,666,337 | **+1.92 MB (+103.7%)** |
| aws-lc-rs + CFLAGS | 2,186,664 | 2,087,342 | **+337 KB (+18.2%)** |

Just swapping ring for aws-lc-rs more than doubles the binary. The CFLAGS
knobs in `.cargo/config.toml` recover ~82% of that.

## What the CFLAGS do

```toml
AWS_LC_SYS_CFLAGS_x86_64_unknown_linux_gnu = \
    "-ffunction-sections -fdata-sections -DOPENSSL_SMALL -DMY_ASSEMBLER_IS_TOO_OLD_FOR_512AVX"
```

- `-ffunction-sections -fdata-sections`: per-function/global sections so the
  linker's `--gc-sections` can drop unused crypto. AWS-LC's `CMakeLists.txt`
  doesn't enable these, unlike ring (which gets them via `cc-rs`).
- `-DOPENSSL_SMALL`: drops a 148 KiB precomputed P-256 table and a few
  other space/time tables. Slows P-256 ECDSA verify by a few x.
- `-DMY_ASSEMBLER_IS_TOO_OLD_FOR_512AVX`: excludes ~664 KiB of AVX-512
  AES-GCM and AES-XTS asm. AES-GCM falls back to AVX2/AES-NI.

`aws-lc-sys` lowercases the target triple in the per-target env-var name
(different from `cc-rs` which uppercases), so the variable is
`AWS_LC_SYS_CFLAGS_x86_64_unknown_linux_gnu`, not `..._X86_64_...`. Easy to
get wrong.

## Verifying

```sh
# Quick smoke test - all three should print the same JSON.
./target/release/showcase-aws-lc-binary-size
./target-aws-lc-default/release/showcase-aws-lc-binary-size
./target-aws-lc-trim/release/showcase-aws-lc-binary-size

# What's actually in the static lib? (look at .text per-function vs per-.o)
objdump -h target/release/build/ring-*/out/libring_core_*_.a \
    | grep -E '\.text\.[a-z]' | head
objdump -h target-aws-lc-trim/release/build/aws-lc-sys-*/out/libaws_lc_*_crypto.a \
    | grep -E '\.text\.[a-z]' | head
```

Tracking issue upstream: <https://github.com/aws/aws-lc-rs/issues/745>.
