#!/bin/bash
#
# PRODUKSJONSBYGG — alle plattformer, ett byggnummer.
#
# Dobbeltklikk fila i Finder, eller kjør ./build_prod_mac.command i Terminal.
#
# Øker byggnummeret, bygger Android phone-aab, Android watch-aab og iOS .ipa
# UTEN testerflagget, og legger alt i dist/prod-v<nummer>/ som åpnes i Finder.
# Betalingsmuren er hard i disse filene — de er trygge å sende til
# produksjonssporet i Play og til App Review.
#
# Varianter:
#   SKIP_IOS=1 ./build_prod_mac.command       kun Android
#   SKIP_ANDROID=1 ./build_prod_mac.command   kun iOS
#   NO_BUMP=1 ./build_prod_mac.command        bygg om uten å øke nummeret

cd "$(dirname "$0")" || exit 1
MODE="prod"
source ./build_mac_common.sh
