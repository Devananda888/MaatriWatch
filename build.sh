#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "Cloning Flutter stable channel..."
git clone https://github.com/flutter/flutter.git -b stable --depth 1

# Add Flutter to the path
export PATH="$PATH:`pwd`/flutter/bin"

# Enable web support (in case it's not enabled by default)
flutter config --enable-web

echo "Running flutter doctor..."
flutter doctor -v

echo "Navigating to the dashboard directory..."
cd dashboard

echo "Getting packages..."
flutter pub get

echo "Building Flutter Web application..."
flutter build web --release

echo "Build complete!"
