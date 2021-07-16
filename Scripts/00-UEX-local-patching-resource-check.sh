#!/bin/bash

# Author: Shayna Waldman
# Date: Sept. 5, 2019
#
# This script checks for and installs resources for local UEX patching

resourcesPath="/Library/UEX/resources"
resources=(
"$resourcesPath"/local_scoping/src/version_check.py
"$resourcesPath"/local_scoping/src/local_installed_apps.py
"$resourcesPath"/local_scoping/src/__init__.py
"$resourcesPath"/local_scoping/00-UEX-SFDC-ComboPatchingInitiator.py
"$resourcesPath"/cocoaDialog.app
"$resourcesPath"/cocoaDialog.app/Contents/MacOS/cocoaDialog
"$resourcesPath"/PleaseWait.app
"$resourcesPath"/icon_white2.png
"$resourcesPath"/battery_white.png
"$resourcesPath"/icon_white.png
)

checkresources(){
missingresources=false
for localpath in "${resources[@]}"; do
	if [[ ! -e $localpath ]]; then
		missingresources=true
		echo "Did not find $localpath"
	fi
done
}

version_gt(){
  test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1";
}

initiator_version="$(grep __version__= "$resourcesPath"/local_scoping/00-UEX-ComboPatchingInitiator.py | awk -F"='" '{print $NF}' | sed 's/.$//')"
initiator_version_to_install="$4"

checkresources
if [[ $missingresources == true ]]; then
	sudo jamf policy -event localpatchingresources
	checkresources
  echo "pass 1"

	if [[ $missingresources == true ]]; then
		echo "Failed to install resources."
		exit 1
	fi
else
  echo "All local patching components found. Proceeding."

  if version_gt "$initiator_version" "$initiator_version_to_install"  || [[ "$initiator_version_to_install" == "$initiator_version" ]]; then
    echo "version up to date"
  else
    echo "needs patching"
    sudo jamf policy -event localpatchingresources
  fi
fi

exit 0
