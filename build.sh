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
if [ "$DEMO_MODE" = "true" ]; then
  echo "Building in DEMO_MODE..."
  flutter build web --release --dart-define=DEMO_MODE=true
else
  echo "Building with Firebase configuration..."
  flutter build web --release \
    --dart-define=FIREBASE_API_KEY="$FIREBASE_API_KEY" \
    --dart-define=FIREBASE_APP_ID="$FIREBASE_APP_ID" \
    --dart-define=FIREBASE_MESSAGING_SENDER_ID="$FIREBASE_MESSAGING_SENDER_ID" \
    --dart-define=FIREBASE_PROJECT_ID="$FIREBASE_PROJECT_ID" \
    --dart-define=FIREBASE_AUTH_DOMAIN="$FIREBASE_AUTH_DOMAIN" \
    --dart-define=FIREBASE_DATABASE_URL="$FIREBASE_DATABASE_URL" \
    --dart-define=API_BASE_URL="$API_BASE_URL"
fi

echo "Build complete!"
