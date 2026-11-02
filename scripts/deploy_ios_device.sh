#!/bin/sh
# Compile (signature automatique) et installe l'app sur un iPhone appairé.
# Usage : scripts/deploy_ios_device.sh <UDID de l'appareil> <ID d'équipe Apple>
#   UDID : xcrun devicectl list devices      (appareil « physical »)
# Prérequis : export_presets.cfg avec le même ID d'équipe (application/app_store_team_id),
# iPhone déverrouillé, mode développeur activé, profil développeur approuvé sur l'iPhone
# (Réglages > Général > VPN et gestion de l'appareil) au premier lancement.
DEVICE="${1:?UDID manquant}"; TEAM="${2:?identifiant equipe manquant}"
cd "$(dirname "$0")/.." || exit 1
rm -rf build/ios build/derived-device && mkdir -p build/ios || exit 1
godot --headless --path . --export-debug "iOS" build/ios/TrainWork.ipa || exit 1
(cd build/ios && xcodebuild -project TrainWork.xcodeproj -scheme TrainWork -configuration Debug \
	-destination "id=$DEVICE" -derivedDataPath ../derived-device -allowProvisioningUpdates \
	DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic build) || exit 1
xcrun devicectl device install app --device "$DEVICE" build/derived-device/Build/Products/Debug-iphoneos/TrainWork.app || exit 1
xcrun devicectl device process launch --device "$DEVICE" com.trainwork.prototype
