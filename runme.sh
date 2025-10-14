#!/bin/bash

# A flexible build-and-run script for the Zcsv project.
#
# Usage:
#   ./run.sh [release] [ Zcsv arguments... ]
#
# Examples:
#   ./run.sh                          # Builds in Debug, runs with default file
#   ./run.sh Data/other.csv           # Builds in Debug, runs with a specific file
#   ./run.sh release                  # Builds in Release, runs with default file
#   ./run.sh release Data/other.csv   # Builds in Release, runs with a specific file

# --- 1. Set Build Mode ---

# Default to Debug mode
BUILD_MODE="Debug"
OPTIMIZE_FLAG="-Doptimize=Debug"

# Check if the first argument is "release"
if [ "$1" == "release" ]; then
    BUILD_MODE="ReleaseFast"
    OPTIMIZE_FLAG="-Doptimize=ReleaseFast"
    echo "Release mode specified."
    
    # CRUCIAL: Consume the 'release' argument so it's not passed to the program
    shift
fi

# --- 2. Build the Program ---

echo "Building in $BUILD_MODE mode..."
if ! zig build $OPTIMIZE_FLAG; then
    echo "Build failed!"
    exit 1
fi

# --- 3. Run the Executable ---

EXECUTABLE="./zig-out/bin/Zcsv"

# Check if any arguments *remain*
if [ "$#" -eq 0 ]; then
    # No arguments remain, so run with the default example
    echo "No file specified, running with default example..."
#    $EXECUTABLE ./Data/cities.csv
    $EXECUTABLE ./Data/data.csv
#    $EXECUTABLE ./Data/large.csv
else
    # Arguments remain, pass them all to the program
    echo "Running with specified arguments..."
    $EXECUTABLE "$@"
fi
