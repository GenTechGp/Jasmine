#!/usr/bin/env bash
#
# Jasmine test harness: build, correctness check (tiny fixtures), and a
# timed run against the realistic-scale HG002 trio demo dataset.
#
# All generated files go under test_data/work/ (gitignored) - nothing is
# written outside this repo, and inputs under test_data/ are never modified.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
REPO_ROOT=$(dirname "$SCRIPT_DIR")
WORKDIR="$SCRIPT_DIR/work"
DEMO_DIR="$SCRIPT_DIR/demo_test"

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"

FAILED=0

section() {
    echo ""
    echo "=== $1 ==="
}

# ---------------------------------------------------------------------------
section "Build (build_no_iris.sh)"
# ---------------------------------------------------------------------------
BUILD_LOG="$WORKDIR/build.log"
time_start=$(date +%s.%N)
if ! "$REPO_ROOT/build_no_iris.sh" >"$BUILD_LOG" 2>&1; then
    echo "BUILD FAILED - see $BUILD_LOG"
    exit 1
fi
time_end=$(date +%s.%N)
echo "Build OK ($(awk -v s="$time_start" -v e="$time_end" 'BEGIN{printf "%.1f", e-s}')s)"

# ---------------------------------------------------------------------------
section "Correctness check (tiny fixtures: a.vcf + b.vcf -> c.vcf)"
# ---------------------------------------------------------------------------
SMALL_OUT="$WORKDIR/small_merged.vcf"
SMALL_LOG="$WORKDIR/small_run.log"
"$REPO_ROOT/run.sh" \
    file_list="$SCRIPT_DIR/a.vcf,$SCRIPT_DIR/b.vcf" \
    out_file="$SMALL_OUT" \
    --comma_filelist >"$SMALL_LOG" 2>&1

if diff -w "$SMALL_OUT" "$SCRIPT_DIR/c.vcf" >"$WORKDIR/small_diff.log" 2>&1; then
    echo "PASS - small fixture output matches c.vcf"
else
    echo "FAIL - small fixture output does not match c.vcf (see $WORKDIR/small_diff.log)"
    FAILED=1
fi

# ---------------------------------------------------------------------------
section "Demo-scale run (HG002 trio, timed)"
# ---------------------------------------------------------------------------
if [ ! -d "$DEMO_DIR" ]; then
    echo "SKIPPED - $DEMO_DIR not found (download the demo VCFs first, see README.md)"
else
    # Jasmine refuses gzipped VCFs, so decompress into the work dir only.
    for f in "$DEMO_DIR"/*vGRCh38*.vcf.gz; do
        gunzip -c "$f" > "$WORKDIR/$(basename "${f%.gz}")"
    done
    ls "$WORKDIR"/*vGRCh38*.vcf > "$WORKDIR/filelist.txt"

    MERGE_LOG="$WORKDIR/demo_merge.log"
    MERGED_VCF="$WORKDIR/demo_merged.vcf"

    echo "Merging 3 samples ($(wc -l < "$WORKDIR/filelist.txt") files)..."
    { time "$REPO_ROOT/run.sh" file_list="$WORKDIR/filelist.txt" out_file="$MERGED_VCF" ; } \
        >"$MERGE_LOG" 2>"$WORKDIR/demo_merge.time"
    cat "$WORKDIR/demo_merge.time"

    echo "Postprocessing (--dup_to_ins --postprocess_only)..."
    { time "$REPO_ROOT/run.sh" --dup_to_ins --postprocess_only out_file="$MERGED_VCF" ; } \
        >>"$MERGE_LOG" 2>"$WORKDIR/demo_postprocess.time"
    cat "$WORKDIR/demo_postprocess.time"

    EXPECTED_GZ="$DEMO_DIR/HG002Trio_HiFi.merged.vcf.gz"
    if [ -f "$EXPECTED_GZ" ]; then
        gunzip -c "$EXPECTED_GZ" > "$WORKDIR/expected_merged.vcf"
        if diff -w "$MERGED_VCF" "$WORKDIR/expected_merged.vcf" >"$WORKDIR/demo_diff.log" 2>&1; then
            echo "PASS - demo output matches HG002Trio_HiFi.merged.vcf"
        else
            DIFF_LINES=$(wc -l < "$WORKDIR/demo_diff.log")
            echo "FAIL - demo output differs from expected ($DIFF_LINES diff lines, see $WORKDIR/demo_diff.log)"
            FAILED=1
        fi
    else
        echo "SKIPPED correctness diff - $EXPECTED_GZ not found"
    fi
fi

# ---------------------------------------------------------------------------
section "Summary"
# ---------------------------------------------------------------------------
if [ "$FAILED" -eq 0 ]; then
    echo "ALL TESTS PASSED"
else
    echo "SOME TESTS FAILED - see logs under $WORKDIR"
fi
exit "$FAILED"
