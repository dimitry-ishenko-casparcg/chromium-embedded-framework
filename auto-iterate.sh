#!/bin/bash
# Auto-iteration script for CEF Debian build
# Automatically fixes missing BUILD.gn files until a different error occurs

MAX_ITERATIONS=100
ITERATION=42
BASE_DIR="/home/mendezr/development/debian/chromium-embedded-framework/chromium-embedded-framework"

cd "$BASE_DIR"

while [ $ITERATION -le $MAX_ITERATIONS ]; do
    echo "========================================="
    echo "Starting iteration $ITERATION"
    echo "========================================="

    # Clean and build
    chmod -R u+w chromium_src/ depot_tools/ 2>/dev/null
    rm -rf chromium_src/ depot_tools/

    LOG_FILE="$BASE_DIR/../build-iteration${ITERATION}.log"
    dpkg-buildpackage -us -uc -b 2>&1 | tee "$LOG_FILE"
    EXIT_CODE=$?

    echo "Build exit code: $EXIT_CODE"

    # Check for "Unable to load" errors (missing BUILD.gn files)
    MISSING_FILE=$(grep -oP 'Unable to load "\K[^"]+' "$LOG_FILE" | head -1)

    if [ -n "$MISSING_FILE" ]; then
        echo "Found missing file: $MISSING_FILE"

        # Convert GN path to filesystem path
        FILE_PATH=$(echo "$MISSING_FILE" | sed 's|^//|chromium_src/chromium/src/|')

        # Check if it's a BUILD.gn or .gni file
        if [[ "$MISSING_FILE" == *.gni ]]; then
            echo "ERROR: .gni file missing - requires manual intervention"
            echo "File: $MISSING_FILE"
            exit 1
        fi

        # Extract target name from error context
        REFERRER=$(grep -B 2 "$MISSING_FILE" "$LOG_FILE" | head -1)
        echo "Referenced from: $REFERRER"

        # For now, stop and report - this needs manual analysis
        echo "Stopping for analysis. Missing: $MISSING_FILE"
        exit 0

    elif grep -q "Disallowed exec_script" "$LOG_FILE"; then
        echo "ERROR: exec_script error - requires manual intervention"
        exit 1

    elif grep -q "Done. Made" "$LOG_FILE"; then
        echo "SUCCESS: GN generation completed!"
        echo "Build may still be running or may have compilation errors"
        exit 0

    else
        echo "ERROR: Unknown error type - requires manual intervention"
        echo "Check log: $LOG_FILE"
        exit 1
    fi

    ITERATION=$((ITERATION + 1))
done

echo "Reached maximum iterations ($MAX_ITERATIONS)"
exit 1
