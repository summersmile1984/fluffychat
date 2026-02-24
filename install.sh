#!/bin/bash

# Path to the APK file
APK_PATH="build/app/outputs/flutter-apk/app-debug.apk"

# Ensure adb is in PATH
if ! command -v adb &> /dev/null; then
    echo "Error: adb could not be found."
    echo "Please ensure Android SDK platform-tools are installed and in your PATH."
    exit 1
fi

# Check if APK exists
if [ ! -f "$APK_PATH" ]; then
    echo "Error: APK not found at $APK_PATH"
    echo "Please run 'flutter build apk --debug' first."
    exit 1
fi

# Check for connected devices
DEVICE_COUNT=$(adb devices | grep -v "List" | grep "device" | wc -l)

if [ "$DEVICE_COUNT" -eq 0 ]; then
    echo "No devices found. Please connect your phone and enable USB Debugging."
    exit 1
fi

echo "Found $DEVICE_COUNT device(s)."

echo "Installing APK from $APK_PATH..."
adb install -r "$APK_PATH"

RET=$?
if [ $RET -eq 0 ]; then
    echo "Installation successful!"
else
    echo "Installation failed."
    echo "If the error is 'INSTALL_FAILED_VERSION_DOWNGRADE', please uninstall the existing app first:"
    echo "  adb uninstall chat.fluffy.fluffychat"
fi
