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

echo "Validating production dashboard configuration..."
required_variables=(
  API_BASE_URL FIREBASE_API_KEY FIREBASE_APP_ID FIREBASE_MESSAGING_SENDER_ID
  FIREBASE_PROJECT_ID FIREBASE_AUTH_DOMAIN FIREBASE_DATABASE_URL
)
for name in "${required_variables[@]}"; do
  value="${!name:-}"
  if [ -z "$value" ]; then
    echo "Missing required build variable: $name" >&2
    exit 1
  fi
  normalised="${value,,}"
  if [[ "$normalised" == *"change-me"* || "$normalised" == *"your-"* || "$normalised" == *"example"* || "$normalised" == *"placeholder"* ]]; then
    echo "Unsafe build variable: $name" >&2
    exit 1
  fi
done
if [ "${DEMO_MODE:-false}" = "true" ]; then
  echo "DEMO_MODE cannot be enabled for a release dashboard build." >&2
  exit 1
fi
for url_name in API_BASE_URL FIREBASE_DATABASE_URL; do
  url="${!url_name}"
  if [[ "$url" != https://* || "$url" == *"localhost"* || "$url" == *"127.0.0.1"* ]]; then
    echo "Release URL must be public HTTPS: $url_name" >&2
    exit 1
  fi
done

echo "Building Flutter Web application..."
flutter build web --release \
  --dart-define=FIREBASE_API_KEY="$FIREBASE_API_KEY" \
  --dart-define=FIREBASE_APP_ID="$FIREBASE_APP_ID" \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID="$FIREBASE_MESSAGING_SENDER_ID" \
  --dart-define=FIREBASE_PROJECT_ID="$FIREBASE_PROJECT_ID" \
  --dart-define=FIREBASE_AUTH_DOMAIN="$FIREBASE_AUTH_DOMAIN" \
  --dart-define=FIREBASE_DATABASE_URL="$FIREBASE_DATABASE_URL" \
  --dart-define=API_BASE_URL="$API_BASE_URL"

echo "Build complete!"
