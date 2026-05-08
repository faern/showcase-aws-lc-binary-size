#!/usr/bin/env bash
# Build the ring baseline and every combination of three aws-lc-sys CFLAGS,
# then print a table comparing binary sizes against ring.
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
RESULTS_DIR="size-results"

# We set AWS_LC_SYS_TARGET_CFLAGS per iteration. That's step 2 in
# aws-lc-sys's resolution chain, and it outranks the project's per-target
# AWS_LC_SYS_CFLAGS_<target> entries from .cargo/config.toml (step 5),
# so we don't need to fight cargo's [env] re-injection.
#
# The only thing that could still shadow us is a higher-priority
# AWS_LC_SYS_* CFLAGS variant exported in the surrounding shell -
# specifically AWS_LC_SYS_TARGET_CFLAGS_<host>. Clear any such variant
# from the env without bothering to detect or format the triple.
while IFS= read -r var; do
    case "$var" in
        AWS_LC_SYS_*CFLAGS*) unset "$var" ;;
    esac
done < <(compgen -e)

ENV_VAR="AWS_LC_SYS_TARGET_CFLAGS"

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
    local file_label="$1"
    local display_label="$2"
    local size
    size=$(wc -c < "${BIN_PATH}" | tr -d ' ')
    result_labels+=("${display_label}")
    result_sizes+=("${size}")
    cp "${BIN_PATH}" "${RESULTS_DIR}/bin.${file_label}"
    printf "    %s: %d bytes\n" "${display_label}" "${size}"
}

echo "==> Building ring baseline"
cargo build --release --features ring
record_size "ring" "ring"
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
        file_label="aws-lc-default"
        display_label="aws-lc (default)"
    else
        joined=$(IFS=-; echo "${label_parts[*]}")
        file_label="aws-lc-${joined}"
        display_label="aws-lc (${cflags})"
    fi

    echo "==> Building ${display_label}"

    # Force aws-lc-sys to recompile so the new CFLAGS take effect. Without
    # this the cached static lib from a previous iteration gets reused.
    cargo clean -p aws-lc-sys -q 2>/dev/null || true

    env "${ENV_VAR}=${cflags}" \
        cargo build --release --features aws-lc
    record_size "${file_label}" "${display_label}"
done

# Final table. Width of the label column adapts to the longest value so
# columns line up regardless of which flag combinations were built.
max_w=5  # at least "Build"
for label in "${result_labels[@]}"; do
    [ "${#label}" -gt "${max_w}" ] && max_w="${#label}"
done
size_w=10
diff_w=12
total_w=$((max_w + size_w + 4 + diff_w))

echo
printf '%*s\n' "${total_w}" '' | tr ' ' '='
printf "%-${max_w}s%${size_w}s    %${diff_w}s\n" "Build" "Size (KiB)" "Diff vs ring"
printf '%*s\n' "${total_w}" '' | tr ' ' '-'
for i in "${!result_labels[@]}"; do
    label="${result_labels[$i]}"
    size="${result_sizes[$i]}"
    diff=$((size - ring_size))
    kib=$(awk -v s="${size}" 'BEGIN { printf "%d", s/1024 }')
    if [ "${diff}" -gt 0 ]; then
        diff_str=$(awk -v d="${diff}" 'BEGIN { printf "+%d KiB", d/1024 }')
    elif [ "${diff}" -lt 0 ]; then
        diff_str=$(awk -v d="${diff}" 'BEGIN { printf "%d KiB", d/1024 }')
    else
        diff_str="0"
    fi
    printf "%-${max_w}s%${size_w}s    %${diff_w}s\n" "${label}" "${kib}" "${diff_str}"
done
