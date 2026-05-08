#!/usr/bin/env bash
# Build the ring baseline and every combination of three aws-lc-sys CFLAGS,
# then print a table comparing binary sizes against ring.
#
# Assumes .cargo/config.toml has the AWS_LC_SYS_CFLAGS_* line commented out
# so the only CFLAGS in effect are the ones this script sets.
set -euo pipefail

# Ensure the binary lands at the path we expect. A CARGO_TARGET_DIR inherited
# from the environment would redirect output and break ${BIN_PATH} below.
unset CARGO_TARGET_DIR

BIN_NAME="showcase-aws-lc-binary-size"
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) BIN_EXT=".exe"; IS_WINDOWS=1 ;;
    *)                    BIN_EXT="";     IS_WINDOWS=0 ;;
esac
BIN_PATH="target/release/${BIN_NAME}${BIN_EXT}"
# The non-target-suffixed env var works on Linux, macOS and Windows. Higher-
# priority vars (AWS_LC_SYS_TARGET_CFLAGS, TARGET_CFLAGS, the per-target
# variants) must be unset in the environment for this to take effect.
ENV_VAR="AWS_LC_SYS_CFLAGS"
RESULTS_DIR="size-results"

mkdir -p "${RESULTS_DIR}"

# Three CFLAGS knobs we want to combinatorially test.
#
# fsec: -ffunction-sections / -fdata-sections on GCC/Clang. On MSVC the
#   equivalents are /Gy (function-level linking) and /Gw (data). cc-rs
#   passes /O1 (opt-level=s) or /O2 (opt-level=2/3); both imply /Gy, so
#   only /Gw needs to be set explicitly. The GCC syntax is unknown to
#   cl.exe, so we swap the flag string when running on Windows.
if [ "${IS_WINDOWS}" = "1" ]; then
    FSEC_FLAGS="/Gw"
else
    FSEC_FLAGS="-ffunction-sections -fdata-sections"
fi
FLAGS=(
    "${FSEC_FLAGS}"
    "-DOPENSSL_SMALL"
    "-DMY_ASSEMBLER_IS_TOO_OLD_FOR_512AVX"
)
# Short labels for each flag, used in result table.
LABELS=("fsec" "small" "noavx512")

result_labels=()
result_sizes=()

record_size() {
    local label="$1"
    local size
    size=$(wc -c < "${BIN_PATH}" | tr -d ' ')
    result_labels+=("${label}")
    result_sizes+=("${size}")
    cp "${BIN_PATH}" "${RESULTS_DIR}/bin.${label}"
    printf "    %s: %d bytes\n" "${label}" "${size}"
}

echo "==> Building ring baseline"
cargo build --release --features ring
record_size "ring"
ring_size="${result_sizes[0]}"

# All 2^3 = 8 combinations of the three flags, including the empty (no-flags)
# combination that reproduces the default aws-lc-rs build.
for mask in $(seq 0 7); do
    cflags=""
    label_parts=()
    for i in 0 1 2; do
        if (( (mask >> i) & 1 )); then
            cflags+=" ${FLAGS[$i]}"
            label_parts+=("${LABELS[$i]}")
        fi
    done
    cflags="${cflags# }"

    if [ ${#label_parts[@]} -eq 0 ]; then
        label="aws-lc-default"
    else
        joined=$(IFS=-; echo "${label_parts[*]}")
        label="aws-lc-${joined}"
    fi

    echo "==> Building ${label}"
    if [ -n "${cflags}" ]; then
        echo "    CFLAGS=\"${cflags}\""
    fi

    # Force aws-lc-sys to recompile so the new CFLAGS take effect. Without
    # this the cached static lib from a previous iteration gets reused.
    cargo clean -p aws-lc-sys -q 2>/dev/null || true

    env "${ENV_VAR}=${cflags}" \
        cargo build --release --features aws-lc
    record_size "${label}"
done

# Final table.
echo
echo "============================================================"
printf "%-30s %12s %15s\n" "Build" "Size (KiB)" "Diff vs ring"
echo "------------------------------------------------------------"
for i in "${!result_labels[@]}"; do
    label="${result_labels[$i]}"
    size="${result_sizes[$i]}"
    diff=$((size - ring_size))
    kib=$(awk -v s="${size}" 'BEGIN { printf "%d", s/1024 }')
    if [ "${diff}" -gt 0 ]; then
        diff_kib=$(awk -v d="${diff}" 'BEGIN { printf "+%d KiB", d/1024 }')
    elif [ "${diff}" -lt 0 ]; then
        diff_kib=$(awk -v d="${diff}" 'BEGIN { printf "%d KiB", d/1024 }')
    else
        diff_kib="0"
    fi
    printf "%-30s %12s %15s\n" "${label}" "${kib}" "${diff_kib}"
done
