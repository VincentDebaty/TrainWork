#!/bin/sh
# Exporte le projet Xcode iOS puis compile l'app pour le simulateur (sans signature).
# Résultat : build/derived/Build/Products/Debug-iphonesimulator/TrainWork.app
# Prérequis : Xcode, modèles d'export Godot 4.7.2 (iOS), export_presets.cfg (préréglage « iOS »).
cd "$(dirname "$0")/.." || exit 1
rm -rf build/ios build/derived && mkdir -p build/ios || exit 1
godot --headless --path . --export-debug "iOS" build/ios/TrainWork.ipa || exit 1
cd build/ios || exit 1
exec xcodebuild -project TrainWork.xcodeproj -scheme TrainWork -configuration Debug \
	-sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath ../derived \
	ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
