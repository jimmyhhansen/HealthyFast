#!/bin/bash
#
# TESTERBYGG — alle plattformer, ett byggnummer.
#
# Dobbeltklikk fila i Finder, eller kjør ./build_testers_mac.command i Terminal.
#
# Samme som produksjonsbygget, men med --dart-define=TESTER_BUILD=true, slik at
# testere kan låse opp appen uten å betale. Legger alt i dist/testers-v<nummer>/
# som åpnes i Finder.
#
# Disse filene skal til lukket testing i Play og til TestFlight — ALDRI til
# produksjonssporet eller App Review, siden bypass-knappen er synlig.
#
# Varianter:
#   SKIP_IOS=1 ./build_testers_mac.command       kun Android
#   SKIP_ANDROID=1 ./build_testers_mac.command   kun iOS
#   NO_BUMP=1 ./build_testers_mac.command        bygg om uten å øke nummeret

cd "$(dirname "$0")" || exit 1
MODE="testers"
source ./build_mac_common.sh
