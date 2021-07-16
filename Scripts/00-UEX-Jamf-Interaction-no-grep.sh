#!/bin/sh
##########################################################################################
##									Script Information									##
##########################################################################################
sfdc_uexvers="1.3.13"
#
# Created Jan 18, 2016 by David Ramirez
#
# January 23rd, 2017 by
# DR = David Ramirez (David.Ramirez@adidas-group.com)
#
# Updated: Feb 21th, 2017 by
# DR = David Ramirez (David.Ramirez@adidas-group.com)
#
# Updated: 2018-2021 by
# MK = Manjunath Kosigi (manjunth.kosigi@salesforce.com)
# SW = Shayna Waldman (swaldman@salesforce.com)
##########################################################################################
##								Paramaters for Branding									##
##########################################################################################

#Your title here for patching dialog
title=""
#Jamf Pro 10 icon if you want another custom one then please update it here.
customLogo=""
#if you you jamf Pro 10 to brand the image for you self sevice icon will be here
SelfServiceIcon=""
# UEX directory (no quotes). Update as needed.
UEXPath=/Library/UEX
#logging variables. Update paths as needed.
logfilename="uex-patching.log"
logdir="$UEXPath/UEX_Logs/"

##########################################################################################
##							STATIC VARIABLES AND PARAMETERS								##
##########################################################################################

loggedInUser=$(/bin/ls -l /dev/console | /usr/bin/awk '{ print $3 }' | grep -v root)
jamfBinary="/usr/local/jamf/bin/jamf"

#uex parameters
altpaths=(
"/Users/Shared/"
"/Library/Application Support/"
"~/Library/Application Support/"
)

#CD variables
CocoaDialog="$UEXPath/resources/cocoaDialog.app/Contents/MacOS/cocoaDialog"
sCocoaDialog_App="$CocoaDialog"

#JH variables
UEXplist=true
jhPath="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"

#if the icon file doesn't exist then set to a standard icon
if [[ -e "$customLogo" ]]; then
	icon="$customLogo"
else
	icon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertNoteIcon.icns"
fi


##########################################################################################
##										FUNCTIONS										##
##########################################################################################

logInUEX(){
	echo $(date)	line "$BASH_LINENO"	:	"$1" >> "$logfilepath"
}

logInUEX4DebugMode() {
	if [[ $debug = true ]]; then
		logMessage="-DEBUG- $1"
		logInUEX $logMessage
	fi
}

#log critical uex errors directly to jamf console. Set error logging policy trigger here. 
logCriticalErrors(){
	$jamfBinary policy -event UEXCriticalErrors > /dev/null
}

log2Jamf(){
	$jamfBinary policy -event UEXAllLogs > /dev/null
}

fn_checkJSSConnection(){
connectionStatus=$($jamfBinary checkJSSConnection) #> /dev/null 2>&1
if [[ "$connectionStatus" != *"The JSS is available." ]]; then
	logInUEX "failed to contact JSS : $1"
	/bin/rm "$UEXPath/block_jss/${packageName}.plist" > /dev/null 2>&1
	logCriticalErrors
	exit 13
fi
}

trigger(){
	$jamfBinary policy -forceNoRecon -trigger $1
}

triggerNgo(){
	$jamfBinary policy -forceNoRecon -trigger $1 &
}

fn_getLoggedinUser(){
	loggedInUser=$(/usr/bin/stat -f%Su /dev/console)
	logInUEX "fn_getLoggedinUser returned $loggedInUser"
}

fn_waitForUserToLogout(){
	if [[ $logoutReqd = true ]]; then
		fn_getLoggedinUser
		while [[ $loggedInUser != root ]]; do
			fn_getLoggedinUser
		done
		# echo no user logged in
	fi
}

fn_getPlistValue(){
	/usr/libexec/PlistBuddy -c "print $1" $UEXPath/$2/"$3"
}

fn_addPlistValue(){
	/usr/libexec/PlistBuddy -c "add $1 $2 ${3}" $UEXPath/"$4"/"$5"
	# log the values of the plist
	logInUEX4DebugMode "Plist Details: $1 $2 $3"
}

fn_setPlistValue(){
	/usr/libexec/PlistBuddy -c "set $1 ${2}" $UEXPath/"$3"/"$4"
	# log the values of the plist
	logInUEX4DebugMode "Plist Details Updated: $1 $2 $3"
}

fn_addcomma(){
	namelist=("$@")
	size=${#namelist[*]}
	size=$((size - 1))
	comma=","
	for ((i=0; i<$size; i++))
	do
		namelist[$i]="${namelist[$i]}"$comma
	done
	namelist[$i]="${namelist[$i]}"
}

#SW 02/07/19
fn_deadline(){
	# get values to math with and determine days left to due date
	nowEpoch=$(date +%s)
	dlEpoch=$(date -jf '%Y%m%d%H%M' $deadline +%s)
	timeLeft=$(expr $dlEpoch - $nowEpoch)
	daysLeft=$(expr $timeLeft / 86400)
	# get due date in local time to print for dialog box
	wordDeadline=$(date -jf '%Y%m%d%H%M' $deadline '+%b %d, %Y %I:%M%p %Z')
	# if past deadline, require immediate update. Otherwise provide time left to update.
	deadlineMessage="This update must be installed by $wordDeadline. "
	if [[ $timeLeft -le 0 ]]; then
		if [[ $postponesLeft -ge 0 ]]; then
			maxdefer=0
			forceInstall="true"
			deadlineMessage="This update was due on $wordDeadline and must be installed now. "
		fi
	elif [[ $postponesLeft == "0" ]] && [[ $timeLeft -gt 0 ]]; then
		deadlineMessage=""
	elif [[ $daysLeft -gt 0 ]]; then
			deadlineMessage+=" You have $daysLeft day(s) left. "
	elif [[ $timeLeft -gt 0 ]]; then
			hrsLeft=$(expr $timeLeft / 3600)
			deadlineMessage+=" You have $hrsLeft hour(s) left. "
	fi
}
#end SW

##########################################################################################
#								check whether deferal time has elapsed					 #
##########################################################################################

i="UEX;ClientPatching;1.0.plist"

if [[ ! -e $UEXPath/defer_jss/"$i" ]]; then
		UEXplist=false #jamf plist creation policy, if plist not exist
fi

if [[ "$UEXplist" != "false" ]]; then
	delayDate=$(/usr/libexec/PlistBuddy -c "print delayDate" $UEXPath/defer_jss/"$i")
	runDate=$(date +%s)
	# calculate the time elapsed
	timeelapsed=$((delayDate-runDate))
	if [[ "$timeelapsed" -gt 0 ]]; then
		echo "deferal date is $(date -r $delayDate), skipping the installation."
		exit 1
	fi
fi

##########################################################################################
#								SELF SERVICE APP DETECTION								 #
##########################################################################################

sspolicyRunning=$(ps aux | grep "00-UEX-Update-via-Self-Service" | grep -v grep | grep -v PATH)

if [[ "$sspolicyRunning" == *"00-UEX-Update-via-Self-Service"* ]]; then
	selfservicePackage=true
fi

##########################################################################################
##								check for new patches 								##
##########################################################################################

if [[ $selfservicePackage = true ]]; then
	"$jhPath" -windowType hud -lockHUD -description "Please wait while we check for updates. This will take a few minutes…" -icon $customLogo -title "$title" &
fi

if [[ "$UEXplist" == "false" ]]; then
	#fn_checkJSSConnection "Before Initiate plist creation"
	$jamfBinary policy -event InitiatePatching # trigger plist creation policy
fi

if [[ ! -e $UEXPath/defer_jss/"$i" ]]; then
	if [[ $selfservicePackage = true ]]; then
		killall jamfHelper  > /dev/null 2>&1
	fi
	if [[ $selfservicePackage = true ]]; then
		msg='Your computer is up to date!
Please click OK to close this pop-up.'
		"$jhPath" -windowType hud -lockHUD -windowPostion center -button1 OK -title "$title" -description "$msg" -icon "$icon" -timeout 300
	fi
	logInUEX "computer is up to date!"
	log2Jamf
	exit 0
fi

##########################################################################################
##								Pre Processing of Variables								##
##########################################################################################

fn_checkJSSConnection "Pre Processing" #check the jamf connection
installDuration=0
daysLeft=11654 # junk value to skip if hard date is not passed to the script
triggers=$(fn_getPlistValue "patchTrigger" "defer_jss" "$i")
apps=$(fn_getPlistValue "BlockApps" "defer_jss" "$i")
checks=$(echo "$(fn_getPlistValue "checks" "defer_jss" "$i")" | tr '[:upper:]' '[:lower:]')
packages=$(fn_getPlistValue "patchNames" "defer_jss" "$i")
installDuration=$(fn_getPlistValue "installDuration" "defer_jss" "$i")
UEXpolicyTrigger=$(fn_getPlistValue "policyTrigger" "defer_jss" "$i")
deadline=$(fn_getPlistValue "HardDate" "defer_jss" "$i")
maxdefer=$(fn_getPlistValue "MaxDefer" "defer_jss" "$i")
failedInstall=true
ShutdownFlag=0

if [[ -z $maxdefer ]]; then
	maxdefer=3
fi

set -- "$triggers"
IFS=";"
declare -a triggers=($*)
unset IFS

AppVendor="SFDC"
AppName="Mandatory Patching"
AppVersion="1.0"
packageName="UEX;ClientPatching;1.0"
heading="${AppName}                     "

# Silent install during provisioning
loggedInUser=$(/bin/ls -l /dev/console | /usr/bin/awk '{ print $3 }' | grep -v root)
splashBuddyRunning=$(ps aux | grep SplashBuddy.app/Contents/MacOS/ | grep -v grep | grep -v jamf | awk {'print $2'})
AppleSetupDoneFile="/var/db/.AppleSetupDone"

if [[ $splashBuddyRunning ]]; then
	silentPackage=true
fi

if [[ "$loggedInUser" == "_mbsetupuser" ]] && [[ ! -f "$AppleSetupDoneFile" ]]; then
	silentPackage=true
	logInUEX "First time setup running. Allowing all installations to run silently."
fi

if [[ "$checks" == *"ssavail"* ]]; then
	ssavail=true
fi

if [[ "$checks" == *"silent"* ]]; then
	silentPackage=true
fi

if [[ "$checks" == *"ssavail"* ]]; then
	ssavail=true
fi

if [[ $silentPackage != true ]]; then
	silentPackage=false
fi

if [[ $selfservicePackage != true ]]; then
	selfservicePackage=false
fi

#########################################################################################
#								Start Log												#
#########################################################################################

mkdir "$logdir" > /dev/null 2>&1
chmod -R 755 "$logdir"
logfilepath="$logdir""$logfilename"
linkaddress="/Library/Logs/"
ln -s "$logdir" "$linkaddress" > /dev/null 2>&1
chmod -R 777 "$logdir"

#Empty lines
echo ""
logInUEX "******* Script Started ******"
logInUEX4DebugMode "DEBUG MODE: ON"
logInUEX "User Experience Version: $sfdc_uexvers"
logInUEX "checks=$checks"
logInUEX "altpaths=${altpaths[@]}"
logInUEX "maxdefer=$maxdefer"
logInUEX "packages=${packages[@]}"

#Start SW 6/22/2020
####################################################
#		adobecc section
####################################################

fn_adobeApp(){
	adobeShortCode=$1
	adobeAppName=$2
	if [[ "$adobeUpdates" == *"$adobeShortCode"* ]]; then
		if [[ "$packages" == "" ]]; then
			packages+="$adobeAppName"
		else
			packages+=";$adobeAppName"
		fi
		adobeShortCode_arr+=($adobeShortCode)
		IFS=$'\n'
		tmp_arr=( $(ls /Applications/ | grep -i "$adobeAppName" |grep .app) )
		tmp_arr+=( $(find /Applications/Adobe* -type d -depth 1 |cut -d'/' -f4- |grep "$adobeAppName" |grep .app) )
		for app in ${tmp_arr[@]}; do
			if [[ $apps == "" ]]; then
				apps+="$app"
			else
				apps+=";$app"
			fi
		done
		logInUEX "apps list check following adobe fn: ${apps[@]}" #remove eventually
		unset IFS
		installDuration=$((installDuration + 10))
		checks+=";block"
	fi
}

fn_removeAdobeCC(){
	if [[ "$checks" == *";adobecc"* ]]; then 
		checks=${checks//;adobecc/}
	elif [[ "$checks" == *"adobecc"* ]]; then
		checks=${checks//adobecc/}
	fi
	if [[ $checks == "" ]]; then
		checks="quit"
		apps="xayasdf.app;asdfasfd.app"
		installDuration=1
		skipNotices="true"
	fi
	logInUEX "adobecc removed from checks"
	logInUEX "checks: ${checks}"
}

#testing
# checks+=";adobecc"
if [[ "$checks" != *"adobecc"* ]]; then
	logInUEX "adobecc check not set. Skipping Adobe section."
else
	logInUEX "Adobecc check set. Checking for Adobe apps"
	adobecc_arr=( $(ls /Applications/ |grep -i "Adobe" |grep -v 'Flash Player\|Acrobat' |grep .app) )
	adobecc_arr+=( $(find /Applications/Adobe* -type d -depth 1 |cut -d'/' -f4- |grep -i "Adobe" |grep -v 'Flash Player\|Acrobat' |grep .app) )
	if [[ "${adobecc_arr[@]}" == "" ]]; then
		logInUEX "No Adobe Creative Cloud apps exist"
		fn_removeAdobeCC
	else #Adobe CC apps exist; proceed with creative cloud update check
		#ensure required update tools are installed
		rum="/usr/local/bin/RemoteUpdateManager"
		armdcVers=$(defaults read "/Library/Application Support/Adobe/ARMDC/Application/Acrobat Update Helper.app/Contents/Info" CFBundleVersion)
		#regex to match less than 1.0.19
		armdcVersReq='^(0|1($|\.0$)|1\.0\.([0-9]|1[0-9])$)'
		#remove spaces from adobe's reported version to allow it to be parsed
		armdcVersNoSpaces=${acrobatUpdVers// /}
		if [[ ! -e "$rum" ]]; then
			logInUEX "Installing RUM"
			"$jamfBinary" policy -forceNoRecon -event adoberum
		else
			logInUEX "RUM present. Continuing"
		fi
		if [[ $armdcVersNoSpaces =~ $armdcVersReq ]]; then
			echo "Installing latest Acrobat Updater"
			"$jamfBinary" policy -forceNoRecon -event adobeAcrobatUpdater
		else
			echo "Acrobat updater up to date. Continuing"
		fi
		rumlog="/tmp/rum.log"
		"$rum" --action=list > "$rumlog"
		adobeUpdates=$(cat $rumlog)
		
		#testing
		# adobeUpdates=" RemoteUpdateManager version is : 2.4.0.3
		# Starting the RemoteUpdateManager...
		# 
		# **************************************************
		# Following Acrobat/Reader updates are applicable on the system : 
		# 		(AdobeAcrobatDC-20.0/20.009.20074)
		# **************************************************
		# No new applicable Updates. Seems like all products are up-to-date.
		# RemoteUpdateManager exiting with Return Code (0)"
		
		logInUEX "adobe updates: $adobeUpdates"
		if [[ "$adobeUpdates" != *"Following"* ]]; then
			adobeUpdatesAvail=false
			logInUEX "no adobe updates found"
			#remove adobecc from checks
			fn_removeAdobeCC
		else # updates are avlaible. check if they're managed and add them if yes
			#add adobe apps that need to be blocked to update here. Inlcude SAP codes.
			fn_adobeApp "AEFT" "Adobe After Effects"
			fn_adobeApp "FLPR" "Adobe Animate CC and Mobile Device Packaging"
			fn_adobeApp "AUDT" "Adobe Audition"
			fn_adobeApp "KBRG" "Adobe Bridge"
			fn_adobeApp "CHAR" "Adobe Character Animator"
			fn_adobeApp "ESHR" "Adobe Dimension"
			fn_adobeApp "DMWV" "Adobe Dreamweaver"
			fn_adobeApp "ILST" "Adobe Illustrator"
			fn_adobeApp "AICY" "Adobe InCopy"
			fn_adobeApp "IDSN" "Adobe InDesign"
			fn_adobeApp "LRCC" "Adobe Lightroom"
			fn_adobeApp "LTRM" "Adobe Lightroom Classic"
			fn_adobeApp "AME" "Adobe Media Encoder"
			fn_adobeApp "MUSE" "Adobe Muse"
			fn_adobeApp "PHSP" "Adobe Photoshop"
			fn_adobeApp "PRLD" "Adobe Prelude"
			fn_adobeApp "PPRO" "Adobe Premiere Pro"
			fn_adobeApp "RUSH" "Adobe Premiere Rush"
			fn_adobeApp "SPRK" "Adobe XD"
			fn_adobeApp "AdobeAcrobatDC" "Adobe Acrobat"
		fi
		if [[ ${adobeShortCode_arr[@]} == "" ]]; then
			logInUEX "No managed adobe updates found"
			fn_removeAdobeCC
		else
			adobeUpdatesAvail=true
			installDuration=$((installDuration + 5))
			adobeUpdatesFiltered=$(cat $rumlog | grep "(" | grep -v "(0)" | cut -c 4- | tr -d ')')
			logInUEX '**Adobe CC Updates Available**'
			logInUEX "${adobeUpdatesFiltered[@]}"
			logInUEX "Downloading all Adobe CC updates"
			"$rum" --action=download
			#if self service, inform user that we are downloading adobe updates
			if [[ $selfservicePackage = true ]]; then
				killall jamfHelper  > /dev/null 2>&1
				sleep 1
				"$jhPath" -windowType hud -lockHUD -windowPostion center -title "$title" -description 'Please wait while we download required Adobe Creative Cloud updates for your computer.' -icon "$icon"  &
			fi
		fi
	fi
fi
#end SW

### SW 1/17/19#
#########################################################################################
##									SUS Variable Settings								##
##########################################################################################

if [[ "$checks" == *"suspackage"* ]]; then
	suspackage=true
fi

if [[ "$suspackage" == true ]]; then
	swulog="/tmp/swu.log"
	softwareupdate -l > $swulog 
	updates=$(cat $swulog)
	logInUEX "Apple updates: $updates"
	if [[ "$updates" != *"*"* ]]; then
		updatesavail=false
		#remove suspackage from checks
		checks=${checks//suspackage/}
		suspackage=false
		if [[ $checks == "" ]]; then
			checks="quit"
			apps="xayasdf.app;asdfasfd.app"
			installDuration=1
			skipNotices="true"
		fi

		if [[ $selfservicePackage == true ]] && [[ ${triggers[@]} == "" ]]; then
			killall jamfHelper  > /dev/null 2>&1
			sleep 1
			logInUEX "computer is up to date!, Deleting $i"
			/bin/rm $UEXPath/defer_jss/"$i" > /dev/null 2>&1
			msg='Your computer is up to date!
Please click OK to close this pop-up.'

			"$jhPath" -windowType hud -lockHUD -windowPostion center -button1 OK -title "$title" -description "$msg" -icon "$icon" -timeout 300
			log2Jamf
			exit 0
		else
			killall jamfHelper  > /dev/null 2>&1
		fi
	else # update are avlaible
		updatesavail=true
		installDuration=$((installDuration + 15))
	fi

	if [[ $updatesavail == true ]]; then
		#code to show updates to user. Does not work, because apple changed softwareupdate output.
#		IFS=$'\n'
#		appleUpdatesArr=($(cat $swulog |grep -i Label | awk -F': '  {'print $2'} | cut -f1 -d'-'))
#		unset IFS
#		if [[ $packages != "" ]]; then
#			packages+=";${appleUpdatesArr[0]}"
#		else
#			packages+="${appleUpdatesArr[0]}"
#		fi
#		for item in "${appleUpdatesArr[@]:1}"; do
#			packages+=";$item"
#		done
		if [[ $packages != "" ]]; then
			packages+=";Apple Updates"
		else
			packages+="Apple Updates"
		fi

		#inform user that we are downloading the apple updates
		if [[ $selfservicePackage = true ]]; then
				killall jamfHelper  > /dev/null 2>&1
				sleep 1
				"$jhPath" -windowType hud -lockHUD -windowPostion center -title "$title" -description 'Please wait while we download required Apple Updates for your computer.' -icon "$icon"  &
		fi
		logInUEX "Downloading recommended apple updates"
		softwareupdate -dr
		
		if [[ "$updates" == *"Security"* ]]; then
			installDuration=$((installDuration + 5))
		fi

		if [[ "$updates" == *"OS X"* ]]; then
			checks+=";power"
			installDuration=$((installDuration + 5))
		fi
		if [[ "$updates" == *"macOS"* ]]; then
			checks+=";power"
			installDuration=$((installDuration + 5))
		fi
		if [[ "$updates" == *"Firmware"* ]]; then
			checks+=";power"
			checks+=";restart"
			logInUEX "contains Firmware Update"
		fi
		if [[ "$updates" == *"restart"* ]]; then
			checks+=";restart"
			installDuration=$((installDuration + 5))
			logInUEX "requires restart"
		fi
		if [[ "$updates" == *"iTunes"* ]] && [[ "$updates" == *"Safari"* ]]; then
			checks+=";block"
			if [[ $apps == "" ]]; then
			apps+="iTunes.app;Safari.app"
			else
				apps+=";iTunes.app;Safari.app"
			fi
		elif [[ "$updates" == *"iTunes"* ]]; then
			checks+=";block"
			if [[ $apps == "" ]]; then
			apps+="iTunes.app"
			else
				apps+=";iTunes.app"
# 			logInUEX contains restart and iTunes updates
			fi
		elif [[ "$updates" == *"Safari"* ]]; then
			checks+=";block"
			logInUEX "contains restart and safari updates"
			if [[ $apps == "" ]]; then
			apps+="Safari.app"
			else
				apps+=";Safari.app"
			fi
		#SW mar 25 2020. Added beats becasue apple apparently considers it to be recommended.
		elif [[ "$updates" == *"Beats"* ]]; then
			checks+=";block"
			logInUEX "contains Beats update"
			if [[ $apps == "" ]]; then
			apps+="Beats Updater.app"
			else
				apps+=";Beats Updater.app"
			fi
		fi
		
		#if there are apple updates that aren't safari, itunes, or beats, and they don't require a restart or ac power, ignore them
		if [[ "$apps" == "" ]] && [[ "$checks" != *"power"* ]] && [[ "$checks" != *"restart"* ]]; then
			checks=${checks//suspackage/}
			updatesavail=false
			checks+=";quit"
			installDuration=1
			apps="xayasdf.app;asdfasfd.app"
			skipNotices="true"
			logInUEX "The following apple updates will be skipped: $updates"
		fi

		updatesfiltered=$(cat $swulog | grep "*" -A 1 | grep -v "*" | awk -F ',' '{print $1}' | awk -F '\t' '{print $2}' | sed '/^\s*$/d')

		set -- "$updatesfiltered"
		IFS="--"; declare -a updatesfiltered=($*)
		unset IFS
		logInUEX "**Apple Updates Available**"
		logInUEX "updatesfiltered: ${updatesfiltered[@]}"

		if [[ $selfservicePackage = true ]]; then
			killall jamfHelper  > /dev/null 2>&1
		fi
	fi
fi
### SW

#if after checking for apple and adobe updates there are no checks, apps, or apple/adobe updates to install, input dummy values
if [[ "$checks" == "" ]]; then
	checks+=";quit"
	installDuration=1
	skipNotices="true"
fi
if [[ "$apps" == "" ]] && [[ "$checks" == "" ]]; then
	checks+=";quit"
	apps="xayasdf.app;asdfasfd.app"
fi

##########################################################################################
##							List Creations and PLIST Variables							##
##########################################################################################

# create a list of apps that need to be display to users.
checks+=";install"
patchnames=$packages
set -- "$patchnames"
IFS=";"; declare -a patchnames=($*)
unset IFS
fn_addcomma "${patchnames[@]}"
patch4dialog=$( printf '%s ' $( echo "${namelist[*]}" )) # | sed 's/.\{4\}$//') )

#need to produce blocking lost for plist
apps4plist="$apps"
IFS=";"
set -- "$apps"
declare -a apps=($*)
unset IFS

##############################
# action and heading changes #
##############################

if [[ "$checks" == *"install"* ]] && [[ "$checks" != *"uninstall"* ]]; then
	action="install"
	actioncap="Install"
	actioning="installing"
	actionation="Installation"
elif [[ "$checks" == *"update"* ]]; then
	action="update"
	actioncap="Update"
	actioning="updating"
	actionation="Updates"
elif [[ "$checks" == *"uninstall"* ]]; then
	action="uninstall"
	actioncap="Uninstall"
	actioning="uninstalling"
	actionation="Removal"
else
	action="install"
	actioncap="Install"
	actioning="installing"
	actionation="Installation"
fi
# increase installation duration by 15% of the given time
bufferTime="1.15"
userInstallDur=$(echo "$installDuration*$bufferTime" | bc)
installDuration=${userInstallDur%.*}

##########################################################################################
##						DO NOT MAKE ANY CHANGES BELOW THIS LINE!						##
##########################################################################################

#set to true to skip some errors
debug=false

##########################################################################################
#								RESOURCE LOADER											 #
##########################################################################################

# only check for the self service icon image if the use is using a custom one
if [[ "$SelfServiceIcon" != *"com.jamfsoftware.selfservice.mac/Documents/Images/brandingimage.png"* ]]; then
	SelfServiceIconCheck="$SelfServiceIcon"
fi

# only check for the self service icon image if the use is using a custom one
if [[ "$customLogo" != *"Jamf.app/Contents/Resources/AppIcon.icns"* ]]; then
	customLogoCheck="$customLogo"
fi

resources=(
"$customLogoCheck"
"$SelfServiceIconCheck"
"$UEXPath/resources/cocoaDialog.app"
"$UEXPath/resources/battery_white.png"
)
for i in "${resources[@]}"; do
	resourceName="$(echo "$i" | sed 's@.*/@@')"
	pathToResource=$(dirname "$i")
	if [[ ! -e "$i" ]] && [[ "$i" ]]; then
		# does not exist...
		missingResources=true
	fi
done

if [[ $missingResources = true ]]; then
	trigger uexresources
fi

#if the icon file doesn't exist then set to a standard icon
if [[ -e "$SelfServiceIcon" ]]; then
	icon="$SelfServiceIcon"
elif [[ -e "$customLogo" ]]; then
	icon="$customLogo"
else
	icon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertNoteIcon.icns"
fi

##########################################################################################
##							Default variables for Post install							##
##########################################################################################

pathToScript=$0
targetLocation=$2
targetVolume=$3

#need to produce blocking lost for plist
apps2block="$apps4plist"

##########################################################################################
##								Date for Plists Creation								##
##########################################################################################

runDate=$(date +%s)
runDateFriendly=$(date -r$runDate)

##########################################################################################
##									SETTING FOR DEBUG MODE								##
##########################################################################################

debugDIR="$UEXPath/debug/"

if [[ -e "$debugDIR""$packageName" ]]; then
	debug=true
fi
if [[ "$checks" == *"debug"* ]]; then
	debug=true
fi
if [[ $debug = true ]]; then
	"$jhPath" -windowType hud -lockHUD -windowPosition ll -title "$title" -description "UEX Script Running in debug mode." -button1 "OK" -timeout 30 > /dev/null 2>&1 &
		# for testing paths
	if [[ $pathToPackage == "" ]]; then
		pathToPackage="/Users/ramirdai/Desktop/aG - Google - Google Chrome 47.0.2526.73 - OSX EN - SRXXXXX - 1.0.pkg"
		packageName="$(echo "$pathToPackage" | sed 's@.*/@@')"
		pathToFolder=$(dirname "$pathToPackage")
	fi
	mkdir -p "$debugDIR" > /dev/null 2>&1
	touch "$debugDIR""$packageName"
fi

# SSplaceholderDIR="$UEXPath/selfservice_jss/"

##########################################################################################
##								MAKE DIRECTORIES FOR PLISTS								##
##########################################################################################
blockJSSfolder="$UEXPath/block_jss/"
deferJSSfolder="$UEXPath/defer_jss/"
logoutJSSfolder="$UEXPath/logout_jss/"

plistFolders=(
"$blockJSSfolder"
"$deferJSSfolder"
"$logoutJSSfolder"
)

for i in "${plistFolders[@]}"; do
	if [[ ! -e "$i" ]]; then
		mkdir "$i" > /dev/null 2>&1
	fi
done

##########################################################################################
##								FIX	PERMISSIONS ON RESOURCES							##
##########################################################################################

#chmod 644 /Library/LaunchDaemons/com.UEX-*  > /dev/null 2>&1
chmod -R 755 $UEXPath  > /dev/null 2>&1

##########################################################################################
##								FIX	ONWERSHIP ON RESOURCES								##
##########################################################################################

#chown root:wheel /Library/LaunchDaemons/com.UEX-* > /dev/null 2>&1
chown -R root:wheel $UEXPath > /dev/null 2>&1

##########################################################################################
# 										START LOGGING									 #
##########################################################################################

fn_generatateApps2quit () {
	apps2quit=()
	for app in "${apps[@]}"; do
		IFS=$'\n'
		appid=$(ps aux | grep ${app}/Contents/MacOS/ | grep -v grep | grep -v jamf | awk {'print $2'})
	# 	echo Processing application $app
		if  [[ "$appid" != "" ]]; then
			apps2quit+=(${app})
			logInUEX "$app is still running. Notifiying user"
		fi
	done
	unset IFS
}

if [[ "$checks" == *"quit"* ]] || [[ "$checks" == *"block"* ]]; then logInUEX "apps: $apps; apps2block: $apps2block"; fi


##########################################################################################
##									RESOURCE CHECKS										##
##########################################################################################

if [[ ! -e "$jamfBinary" ]]; then
warningmsg=$("$CocoaDialog" ok-msgbox --icon caution --title "$title" --text "Error" \
	--informative-text "There is Scheduled $action being attempted but the computer doesn't have JAMF Management software installed correctly. Please contact the service desk for support." \
	--float --no-cancel)
	badvariable=true
	logInUEX "ERROR: JAMF binary not found"
fi

jamfhelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"

if [[ ! -e "$jamfhelper" ]]; then
warningmsg=$("$CocoaDialog" ok-msgbox --icon caution --title "$title" --text "Error" \
	--informative-text "There is Scheduled $action being attempted but the computer doesn't have JAMF Management software installed correctly. Please contact the service desk for support." \
	--float --no-cancel)
	badvariable=true
	logInUEX "ERROR: jamfHelper not found"
fi

if [[ ! -e "$CocoaDialog" ]]; then
	badvariable=true
	logInUEX "ERROR: cocoaDialog not found"
fi

##########################################################################################
##									Checking for errors									##
##########################################################################################

if [[ -z $AppVendor ]]; then
	badvariable=true
	logInUEX "ERROR: The variable 'AppVendor' is blank"
fi

if [[ -z $AppName ]]; then
	badvariable=true
	logInUEX "ERROR: The variable 'AppName' is blank"
fi

if [[ -z $AppVersion ]]; then
	badvariable=true
	logInUEX "ERROR: The variable 'AppVersion' is blank"
fi

if [[ "$checks" != *"quit"* ]] && [[ "$checks" != *"block"* ]] && [[ "$checks" != *"logout"* ]] && [[ "$checks" != *"restart"* ]] && [[ "$checks" != *"notify"* ]] && [[ "$checks" != *"custom"* ]] && [[ "$checks" != *"saveallwork"* ]] && [[ "$checks" != *"power"* ]]; then
	badvariable=true
	logInUEX "ERROR: The variable 'checks' is not set correctly."
fi

for app in "${apps[@]}"; do
	if [[ "$checks" == *"quit"* ]] && [[ "$app" != *".app" ]]; then
		badvariable=true
		logInUEX "ERROR: The variable, ${app}, in 'apps' is not set correctly."
	fi
	if [[ "$checks" == *"block"* ]] && [[ "$app" != *".app" ]]; then
		badvariable=true
		logInUEX "ERROR: The variable, ${app}, in 'apps' is not set correctly."
	fi
done

if [[ -z $installDuration ]]; then
	badvariable=true
	logInUEX "ERROR: The variable 'installDuration' is not set correctly."
fi

if [[ -z $maxdefer ]]; then
	badvariable=true
	logInUEX "ERROR: The variable 'maxdefer' is not set correctly."
fi

if [[ $installDuration =~ ^-?[0-9]+$ ]]; then
	echo integer > /dev/null 2>&1 &
else
	badvariable=true
	logInUEX "ERROR: The variable 'installDuration' is not set correctly."
fi

if [[ $maxdefer =~ ^-?[0-9]+$ ]]; then
	echo integer > /dev/null 2>&1 &
else
	badvariable=true
	logInUEX "ERROR: The variable 'maxdefer' is not set correctly."
fi

if [[ "$apps2block" == *";"* ]] && [[ "$apps2block" == *"; "* ]]; then
	badvariable=true
	logInUEX "ERROR: The variable 'apps' is not set correctly. It contains spaces between the delimiters."
fi

if [[ "$apps2block" == *";"* ]] && [[ "$apps2block" == *" ;"* ]]; then
	badvariable=true
	logInUEX "ERROR: The variable 'apps' is not set correctly. It contains spaces between the delimiters."
fi

##########################################################################################
##					 Wrapping errors that need to be skipped for debugging				##
##########################################################################################

if [[ $debug != true ]]; then
	if [[ ! -e "$CocoaDialog" ]]; then
		failedInstall=true
	fi
	if [[ "$AppVendor" == *"AppVendor"* ]]; then
	# 	badvariable=true
		logInUEX "ERROR: The variable 'AppVendor' is not set correctly. Please update it from the default."
	fi
	if [[ "$AppName" == *"AppName"* ]]; then
	# 	badvariable=true
		logInUEX "ERROR: The variable 'AppName' is not set correctly. Please update it from the default."
	fi
	if [[ "$AppVersion" == *"AppVersion"* ]]; then
	# 	badvariable=true
		logInUEX "ERROR: The variable 'AppVersion' is not set correctly. Please update it from the default."
	fi
fi

##########################################################################################
##						Wrapping badvariable errors in 									##
##########################################################################################

if [[ $badvariable != true ]]; then
##########################################################################################

##########################################################################################
##									 Battery Test										##
##########################################################################################

Laptop=$(system_profiler SPHardwareDataType | grep -E "MacBook")
VmTest=$(ioreg -l | grep -e Manufacturer -e 'Vendor Name' | grep 'Parallels\|VMware\|Oracle\|VirtualBox' | grep -v IOAudioDeviceManufacturerName)

if [[ "$VmTest" ]]; then
	Laptop="MacBook"
fi

BatteryTest=$(pmset -g batt)
batteryCustomIcon="$UEXPath/resources/battery_white.png"

#if the icon file doesn't exist then set to a standard icon
if [[ -e "$batteryCustomIcon" ]]; then
	baticon="$batteryCustomIcon"
else
	baticon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertNoteIcon.icns"
fi

if [[ "$BatteryTest" =~ "AC" ]]; then
	#on AC power
	power=true
	logInUEX "Computer on AC power"
else
	#on battery power
	power=false
	logInUEX "Computer on battery power"
fi

##########################################################################################
##								Pre-Processing Paramaters (APPS)						##
##########################################################################################

# user needs to be notified about all applications that need to be blocked
# Create dialog list with each item on a new line for the dialog windows
# If the list is too long then put two on a line separated by ||
if [[ "$checks" == *"block"* ]]; then
	for app in "${apps[@]}"; do
		IFS=$'\n'
		loggedInUser=$(/bin/ls -l /dev/console | /usr/bin/awk '{ print $3 }' | grep -v root)
		appfound=$(/usr/bin/find /Applications -maxdepth 3 -iname "$app")
		if [[ -e /Users/"$loggedInUser"/Applications/ ]]; then
			userappfound=$(/usr/bin/find /Users/"$loggedInUser"/Applications/ -maxdepth 3 -iname "$app")
		fi
# 		altpathsfound=""
		for altpath in "${altpaths[@]}"; do
			if [[ "$altpath" == "~"* ]]; then
				altpathshort=$(echo $altpath | cut -c 2-)
				altuserpath="/Users/${loggedInUser}${altpathshort}"
				if [[ -e "$altuserpath" ]]; then
				foundappinalthpath=$(/usr/bin/find "$altuserpath" -maxdepth 3 -iname "$app")
				fi
			else
				if [[ -e "$altpath" ]]; then
					foundappinalthpath=$(/usr/bin/find "$altpath" -maxdepth 3 -iname "$app")
				fi
			fi
			if [[ "$foundappinalthpath" != "" ]]; then
				altpathsfound+=(${foundappinalthpath})
				logInUEX "Application $app was found in $altpath"
			else
				logInUEX4DebugMode "Application $app not found in $altpath"
			fi
		done
		if  [[ "$appfound" != "" ]] || [[ "$userappfound" != "" ]] || [[ "$altpathsfound" != "" ]]; then
			appsinstalled+=(${app})
		else
			logInUEX4DebugMode "Applicaiton not found in any specified paths."
		fi
	done
#	fn_addcomma "${appsnames[@]}"
	apps4dialog=$( printf '%s ' $( echo "${namelist[*]}" ) )
fi

##########################################################################################
##							Pre-Processing Paramaters (pkg2install)						##
##########################################################################################

pathtopkg="$waitingRoomDIR"

# Notes
# The Variable for the whole list of applications is ${apps[@]}

##########################################################################################
## 									 No Apps to be blocked								##
##########################################################################################

if [[ $checks == *"block"* ]] && [[ $appsinstalled == "" ]]; then
	checks="${checks/block/quit}"
fi

##########################################################################################
## 									Quit Application Processing							##
##########################################################################################

#Generate list of apps that are running that need to be quit
fn_generatateApps2quit

# Create dialog list with each item on a new line for the dialog windows
# If the list is too long then put two on a line separated by ||
if [[ "$checks" == *"quit"* ]]; then
#	fn_addcomma "${appsnames[@]}"
	apps4dialog=$( printf '%s ' $( echo "${namelist[*]}" ))
fi

# modify lists for quitting and removing apps from lists
for app2quit in "${apps2quit[@]}"; do
	delete_me=$app2quit
	for i in ${!appsinstalled[@]};do
		if [[ "${appsinstalled[$i]}" == "$delete_me" ]]; then
			unset appsinstalled[$i]
		fi
	done
done

fn_addcomma "${apps2quit[@]}"
apps4dialogquit=$( printf '%s ' $( echo "${namelist[*]}" ))
fn_addcomma "${appsinstalled[@]}"
apps4dialogblock=$( printf '%s ' $( echo "${namelist[*]}" ))

##########################################################################################
## 									Logout and restart Processing						##
##########################################################################################

if [[ $checks == *"quit"* ]] && [[ $checks == *"logout"* ]] && [[ $apps2quit == "" ]]; then
	logInUEX " None of the apps are running that would need to be quit. Switching to logout only."
	checks="${checks/quit/}"
fi

if [[ $checks == *"quit"* ]] && [[ $checks == *"restart"* ]] && [[ $apps2quit == "" ]]; then
	logInUEX " None of the apps are running that would need to be quit. Switching to restart only."
	checks="${checks/quit/}"
fi

##########################################################################################
## 									POSTPONE DIALOGS									##
##########################################################################################

#get the delay number from the plist or set it to zero
if [[ -e $UEXPath/defer_jss/"$packageName".plist ]]; then
	delayNumber=$(fn_getPlistValue "delayNumber" "defer_jss" "$packageName.plist")
	else
		delayNumber=0
fi

if [[ $delayNumber == *"File Doesn"* ]]; then delayNumber=0; fi

logInUEX4DebugMode "maxdefer is $maxdefer"
logInUEX4DebugMode "delayNumber is $delayNumber"
postponesLeft=$((maxdefer-delayNumber))
logInUEX4DebugMode "postponesLeft is $postponesLeft"

##########################################################################################
## 									BUILDING DIALOGS FOR POSTPONE						##
##########################################################################################

if [[ $checks == *"install"* ]] && [[ $checks != *"uninstall"* ]]; then
	heading="$AppName" #heading="Installing $AppName"
	action="install"
elif [[ $checks == *"update"* ]]; then
	heading="$AppName" #"Updating $AppName"
	action="update"
elif [[ $checks == *"uninstall"* ]]; then
	heading="Uninstalling $AppName $AppVersion"
	action="uninstall"
else
	heading="$AppName"
	action="install"
fi

if [[ "$deadline" ]]; then
	fn_deadline
	heading+="     "
	PostponeMsg+="$deadlineMessage"
fi

customMessage="The following updates will be installed:                      
$patch4dialog"

if [[ $checks == *"critical"* ]]; then
	PostponeMsg+="This is a critical $action.
"
fi

if [[ "$customMessage" ]]; then
	PostponeMsg+="$customMessage
"
fi

if [[ "${apps2quit[@]}" == *".app"*  ]] && [[ "$checks" != *"custom"* ]]; then
	PostponeMsg+="
Before the $action starts:                      
• Please save all work and quit: $apps4dialogquit
"
fi

if [[ "$Laptop" ]] && [[ $checks == *"power"* ]] && [[ "$checks" != *"custom"* ]]; then
	PostponeMsg+="
During the $action:                      
"
elif [[ "${appsinstalled[@]}" == *".app"* ]] && [[ "$checks" == *"block"* ]] && [[ "$checks" != *"custom"* ]]; then
PostponeMsg+="
During the $action:                      
"
fi

if [[ "$Laptop" ]] && [[ $checks == *"power"* ]] && [[ "$checks" != *"custom"* ]]; then
	PostponeMsg+="• Keep your computer connected to a charger.               
"
fi

if [[ "${appsinstalled[@]}" == *".app"* ]] && [[ "$checks" == *"block"* ]] && [[ "$checks" != *"custom"* ]]; then
	PostponeMsg+="• Do not open: $apps4dialogblock
               "
fi

if [[ $checks == *"power"* ]] && [[ $checks != *"block"* ]] && [[ $checks != *"quit"* ]] && [[ "$checks" != *"custom"* ]]; then
	PostponeMsg+="
               "
fi

if [[ $checks == *"restart"* ]] || [[ $checks == *"logout"* ]] && [[ "$checks" != *"custom"* ]]; then
	PostponeMsg+="
After the $action completes:                      
"
fi

if [[ $checks == *"macosupgrade"* ]] && [[ "$checks" != *"custom"* ]]; then
	PostponeMsg+="After the preparation completes:
"
fi

if [[ $checks == *"macosupgrade"* ]] && [[ "$checks" != *"custom"* ]]; then
	PostponeMsg+="• Your computer will restart automatically.
"
fi

if [[ $checks == *"restart"* ]] && [[ "$checks" != *"custom"* ]]; then
	PostponeMsg+="• You will need to restart within 1 hour.
               "
fi

if [[ $checks == *"logout"* ]] && [[ "$checks" != *"custom"* ]]; then
	PostponeMsg+="• You will need to logout within 1 hour.
"
fi

if [[ $selfservicePackage != true ]] && [[ $checks != *"critical"* ]] && [[ $delayNumber -lt $maxdefer ]]; then
	if [[ $postponesLeft -ge 1 ]]; then
		PostponeMsg+="
Start now or select a reminder. You may delay $postponesLeft more times. This $action may take about $installDuration minutes."
	fi # more than one
	else
		PostponeMsg+="
This $action may take about $installDuration minutes."
fi #selfservice is not true

if [[ $selfservicePackage = true ]]; then
	PostponeMsg+="
You can decide to 'Start now' or 'Cancel'.
               "
fi

PostponeMsg+="
                      
                      
"

if [[ -e "$SelfServiceIcon" ]]; then
	ssicon="$SelfServiceIcon"
else
	ssicon="/Applications/Self Service.app/Contents/Resources/Self Service.icns"
fi

SelfServiceAppPath=$( /usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf self_service_app_path 2>/dev/null)
SelfServiceAppName=$( echo "$SelfServiceAppPath" |\
					  /usr/bin/sed -ne 's|^.*/\(.*\).app$|\1|p' )
SelfServiceAppFolder=$(dirname "$SelfServiceAppPath")

if [[ -z "${SelfServiceAppName}" ]]; then
	SelfServiceAppName="Self Service"
fi

SelfServiceAppNameDockPlist=$(/bin/echo ${SelfServiceAppName// /"%20"})
SelfServersioninDock=$(sudo -u "$loggedInUser" -H defaults read com.apple.Dock | grep "$SelfServiceAppNameDockPlist")

# dynamically detect the location of where the user can find self service and update the dialog
if [[ "$SelfServersioninDock" ]]; then
	SSLocation="your Dock or $SelfServiceAppFolder,"
else
	SSLocation="$SelfServiceAppFolder"
fi

selfservicerunoption="Open up $SelfServiceAppName from $SSLocation and start the $action of $AppName at any time.

Otherwise you will be reminded about the $action automatically after your chosen interval."

##########################################################################################
##								INSTALL LOGOUT MESSAGE SETTING							##
##########################################################################################
# notice about needing charger connect if you want to install at logout
loggedInUser=$(/bin/ls -l /dev/console | /usr/bin/awk '{ print $3 }' | grep -v root)
usernamefriendly=$(id -P $loggedInUser | awk -F: '{print $8}')
logoutMessage="To start the $action:

"

if [[ $checks == *"power"* ]] && [[ "$Laptop" ]]; then
	logoutMessage+="• Connect to a Charger
"
fi

logoutMessage+="• Open the (Apple) Menu
• Click 'Log Out $usernamefriendly...'

You have until tomorrow, then you will be prompted again to start the $action."

##########################################################################################
##								CHARGER REQUIRED MESSAGE								##
##########################################################################################

battMessage="Please note that the MacBook must be connected to a charger for successful $action. Please connect it now.
"

if [[ $checks != *"critical"* ]] && [[ $delayNumber -lt $maxdefer ]]; then
	battMessage+="
Otherwise click OK and choose a delay time."
fi

battMessage+="
Thank you!"

##########################################################################################
##									TIME OPITIONS FOR DELAYS							##
##########################################################################################

#if [[ "$debug" = true ]]; then
if [[ $daysLeft -eq 0 ]]; then
	delayOptions="0, 1800, 3600, 7200, 14400"
else
	delayOptions="0, 3600, 7200, 14400, 86400"
fi

##########################################################################################
## 							Login Check Run if no on is logged in						##
##########################################################################################
# no login  RUN NOW
# (skip to install stage)
loggedInUser=$(/bin/ls -l /dev/console | /usr/bin/awk '{ print $3 }' | grep -v root)
logoutHookRunning=$(ps aux | grep "JAMF/ManagementFrameworkScripts/logouthook.sh" | grep -v grep)
logInUEX "loggedInUser is $loggedInUser"

if [[ "$logoutHookRunning" ]]; then
	loggedInUser=""
fi

# if there is a Apple Setup Done File but the setup user is running assumge it's running migration assistanant and act as if there is no one logged in
# This will cause restart and long block installations to be put on a 1 hour delay automatically
if [[ "$loggedInUser" == "_mbsetupuser" ]] && [[ -f "$AppleSetupDoneFile" ]]; then
	loggedInUser=""
	logInUEX "Migration Assistant running, delaying restart and block installations by 1 hour"
fi

##########################################################################################
##										Postpone Stage									##
##########################################################################################

PostponeClickResult=""
skipNotices="false"

if [[ -e $UEXPath/defer_jss/"$packageName".plist ]]; then

	delayNumber=$(fn_getPlistValue "delayNumber" "defer_jss" "$packageName.plist")
	presentationDelayNumber=$(fn_getPlistValue "presentationDelayNumber" "defer_jss" "$packageName.plist")
	inactivityDelay=$(fn_getPlistValue "inactivityDelay" "defer_jss" "$packageName.plist")
else
	delayNumber=0
	presentationDelayNumber=0
	inactivityDelay=0
fi

if [[ $delayNumber == *"File Doesn"* ]]; then
	delayNumber=0
	presentationDelayNumber=0
	inactivityDelay=0
fi

if [[ -z $delayNumber ]]; then
	delayNumber=0
fi

if [[ -z $presentationDelayNumber ]]; then
	presentationDelayNumber=0
fi

if [[ -z $inactivityDelay ]]; then
	inactivityDelay=0
fi

##########################################################################################
##									Login screen safety									##
##########################################################################################

loginscreeninstall=true

if [[ $installDuration -ge 0 ]] && [[ $checks == *"restart"* ]]; then
	loginscreeninstall=false
fi

if [[ $installDuration -ge 0 ]] && [[ $checks == *"notify"* ]]; then
	loginscreeninstall=false
fi

if [[ $installDuration -ge 0 ]] && [[ $checks == *"macosupgrade"* ]]; then
	loginscreeninstall=false
fi

if [[ $installDuration -ge 2 ]] && [[ $checks == *"block"* ]]; then
	loginscreeninstall=false
fi

##########################################################################################
##										Login Check										##
##########################################################################################

fn_getLoggedinUser
if [[ "$loggedInUser" != root ]]; then
# 	This is if for if a user is logged in

	##############################
	##	PRESENTATION DETECTION	##
	##############################
	presentationApps=(
	"Microsoft PowerPoint.app"
	"Keynote.app"
	"VidyoDesktop.app"
	"Vidyo Desktop.app"
	"Meeting Center.app"
	"People + Content IP.app"
	"GoToMeeting.app"
	"GoToWebinar.app"
	)

	for app in "${presentationApps[@]}"; do
		IFS=$'\n'
		appid=$(ps aux | grep ${app}/Contents/MacOS/ | grep -v grep | grep -v jamf | awk {'print $2'})
	# 	echo Processing application $app
		if  [[ "$appid" != "" ]]; then
			presentationRunning=true
		fi
	done

	#######################################
	##	PRIMARY DIALOGS FOR INTERACTION	 ##
	#######################################
	#fn_checkJSSConnection "Before Initiate PRIMARY DIALOGBOX"
	reqlooper=1
	while [[ $reqlooper = 1 ]]; do

		PostponeClickResultFile=/tmp/$UEXpolicyTrigger.txt
		jhTimeOut=1200 # keep the JH window on for 20 mins
		timeLimit=900
		if [[ $silentPackage = true ]]; then
			logInUEX "Slient packge install deployment."
			echo 0 > $PostponeClickResultFile &
			PostponeClickResult=0
			checks="${checks/quit/}"
			checks="${checks/block/}"
			checks="${checks/logout/}"
			skipNotices=true
			skipOver=true
		elif [[ -z "$apps2quit" ]] && [[ $checks == *"quit"* ]] && [[ $checks != *"restart"* ]] && [[ $checks != *"power"* ]] && [[ $checks != *"logout"* ]] && [[ $checks != *"notify"* ]]; then
			logInUEX "No apps need to be quit so $action can occur."
			echo 0 > $PostponeClickResultFile &
			PostponeClickResult=0
			skipNotices=true
		elif [[ "$presentationRunning" = true ]] && [[ $presentationDelayNumber -lt 3 ]] && [[ $selfservicePackage != true ]] && [[ $checks != *"critical"* ]]; then
			echo 3600 > $PostponeClickResultFile &
			PostponeClickResult=3600
			presentationDelayNumber=$((presentationDelayNumber+1))
			logInUEX "Presentation running, delaying the install for 1 hour."
			# subtracting 1 so that thy don't get dinged for an auto delay
			delayNumber=$((delayNumber-1))
			skipNotices=true
			skipOver=true
		else
			if [[ $checks == *"critical"* ]]; then
				"$jhPath" -windowType hud -lockHUD -title "$title" -heading "$heading" -description "$PostponeMsg" -button1 "OK" -icon "$icon" -windowPosition center -timeout $jhTimeOut > $PostponeClickResultFile &
			else
				if [[ $selfservicePackage = true ]]; then
					"$jhPath" -windowType hud -lockHUD -title "$title" -heading "$heading" -description "$PostponeMsg" -button1 "Start now" -button2 "Cancel" -icon "$icon" -windowPosition center -timeout $jhTimeOut > $PostponeClickResultFile &
				else
					if [[ $delayNumber -ge $maxdefer ]]; then
						"$jhPath" -windowType hud -lockHUD -title "$title" -heading "$heading" -description "$PostponeMsg" -button1 "OK" -icon "$icon" -windowPosition center -timeout $jhTimeOut > $PostponeClickResultFile &
					elif [[ $checks == *"restart"* ]] || [[ $checks == *"logout"* ]] || [[ $checks == *"macosupgrade"* ]] || [[ $checks == *"loginwindow"* ]] || [[ $checks == *"lock"* ]] || [[ $checks == *"saveallwork"* ]]; then
						"$jhPath" -windowType hud -lockHUD -title "$title" -heading "$heading" -description "$PostponeMsg" -showDelayOptions "$delayOptions" -button1 "OK" -icon "$icon" -windowPosition center -timeout $jhTimeOut > $PostponeClickResultFile &
					else
						"$jhPath" -windowType hud -lockHUD -title "$title" -heading "$heading" -description "$PostponeMsg" -showDelayOptions "$delayOptions" -button1 "OK" -icon "$icon" -windowPosition center -timeout $jhTimeOut > $PostponeClickResultFile &
					fi # Max defer exceeded
				fi # self service true
			fi # Critical install
		fi # if apps are empty & quit is set but no restart & no logout
		# this is a safety net for closing and for 10.9 skiping jamfHelper windows
		sleep 5
		counter=0
		jamfHelperOn=$(ps aux | grep jamfHelper | grep -v grep)
		while [[ $jamfHelperOn != "" ]]; do
			let counter=counter+1
			sleep 1
			if [[ "$counter" -ge $timeLimit ]]; then
				killall jamfHelper
			fi
			jamfHelperOn=$(ps aux | grep jamfHelper | grep -v grep)
		done
		PostponeClickResult=$(cat $PostponeClickResultFile)

		if [[ $delayNumber -ge $maxdefer ]]; then
			PostponeClickResult=0
		#elif [[ -z $PostponeClickResult ]] || [[ $inactiveFlag == true ]]; then
		elif [[ -z $PostponeClickResult ]]; then
			if [[ "$forceInstall" == "true" ]]; then
				PostponeClickResult=""
			else
				if [[ $inactivityDelay -ge 3 ]]; then
						PostponeClickResult=86400
						inactivityDelay=0
				else
					PostponeClickResult=6300
					delayNumber=$((delayNumber-1))
					inactivityDelay=$((inactivityDelay+1))
				fi
			fi
		else
			inactivityDelay=0
		fi

		logoutClickResult=""
		if [[ $PostponeClickResult == *2 ]] && [[ $selfservicePackage != true ]]; then
			if [[ $checks == *"power"* ]] && [[ "$Laptop" ]]; then
				logouticon="$baticon"
			else
				logouticon="$icon"
			fi
			logInUEX "User chose to install at logout"
			logoutClickResult=$( "$jhPath" -windowType hud -lockHUD -icon "$logouticon" -title "$title" -heading "Install at logout" -description "$logoutMessage" -button1 "OK" -button2 "Go Back")
			if [[ $logoutClickResult = 0 ]]; then
				PostponeClickResult=86400
				loginscreeninstall=true
			else
				if [[ $logoutClickResult = 2 ]]; then logInUEX "User cliked go back."; fi
			fi
		fi

		if [[ $PostponeClickResult = "" ]] || [[ -z $PostponeClickResult ]]; then
			reqlooper=1
			skipOver=true
			logInUEX "User either skipped or Jamf helper did not return a result."
		else # User chose an option
			skipOver=false
			PostponeClickResult=$(echo $PostponeClickResult | sed 's/1$//')
			if [[ "$PostponeClickResult" = 0 ]]; then
				PostponeClickResult=""
			fi # ppcr=0
		fi # if PPCR is blank because the user clicked close
		if [[ ! -z $PostponeClickResult ]] && [[ $PostponeClickResult -gt 0 ]] && [[ $selfservicePackage != true ]] && [[ "$ssavail" == true ]] && [[ "$skipOver" != true ]] && [[ $skipNotices != "true" ]]; then
			"$jhPath" -windowType hud -title "$title" -heading "Start the $action anytime" -description "$selfservicerunoption" -showDelayOptions -timeout 20 -icon "$ssicon" -windowPosition lr | grep -v 239 &
		fi

		###############################
		##	ARE YOU SURE SAFTEY NET  ##
		###############################
		#Generate list of apps that are running that need to be quit
		fn_generatateApps2quit
		#appsnames=( "${apps2quit[@]/#/⋆ }" )
		fn_addcomma "${apps2quit[@]}"
		apps4dialogquit=$( printf '%s ' $( echo "${namelist[*]}" ))
		logInUEX "apps2quit : ${apps2quit[@]}"
		areyousureHeading="Please save your work"

		if [[ "$checks" == *"saveallwork"* ]]; then
			areyousureMessage="Please save ALL your work before clicking continue."
		else # use for quigign spefic apps
			areyousureMessage="Please save your work before clicking continue.
$actionation cannot begin until the apps below are closed:
                  "
			areyousureMessage+="
$apps4dialogquit
                  "
		fi #if save all work is set

			areyousureMessage+="
Current work may be lost if you do not save before proceeding.
                  "
		areYouSure=""
		logInUEX "skipNotices is $skipNotices"
		if [[ "$skipNotices" != true ]]; then
			if [[ "$apps2quit" == *".app"* ]] && [[ -z $PostponeClickResult ]] || [[ "$checks" == *"saveallwork"* ]] && [[ -z $PostponeClickResult ]]; then
				if [[ $checks == *"critical"* ]] || [[ $delayNumber -ge $maxdefer ]]; then
					areYouSure=$( "$jhPath" -windowType hud -lockHUD -icon "$icon" -title "$title" -heading "$areyousureHeading" -description "$areyousureMessage" -button1 "Continue" -timeout 300 -countdown)
				else
					areYouSure=$( "$jhPath" -windowType hud -lockHUD -icon "$icon" -title "$title" -heading "$areyousureHeading" -description "$areyousureMessage" -button1 "Continue" -button2 "Go Back" -timeout 600 -countdown)
				fi
				# logInUEX "areYouSure Button result was: $areYouSure"
				if [[ "$areYouSure" = "2" ]]; then
					reqlooper=1
					skipOver=true
				else
					reqlooper=0
					if [[ $areYouSure = 2 ]]; then
						logInUEX "User Clicked continue."
					fi
				fi
			fi # ARE YOU SURE? if apps are still running
		fi #SkipOver is not true

		##########################
		##	BATTERY SAFTEY NET	##
		##########################
		BatteryTest=$(pmset -g batt)
		if [[ $checks == *"power"* ]] && [[ "$BatteryTest" != *"AC"* ]] && [[ -z $PostponeClickResult ]] && [[ "$skipOver" != true ]]; then
			reqlooper=1
			"$jhPath" -windowType hud -lockHUD -icon "$baticon" -title "$title" -heading "Charger Required" -description "$battMessage" -button1 "OK" -timeout 60 > /dev/null 2>&1 &
			batlooper=1
			jamfHelperOn=$(ps aux | grep jamfHelper | grep -v grep)
			while [[ $batlooper = 1 ]] && [[ $jamfHelperOn != "" ]]; do
				BatteryTest=$(pmset -g batt)
				jamfHelperOn=$(ps aux | grep jamfHelper | grep -v grep)

				if [[ "$BatteryTest" != *"AC"* ]] && [[ $checks == *"critical"* ]]; then
					# charger still not connected
					batlooper=1
					sleep 1
				elif [[ "$BatteryTest" != *"AC"* ]]; then
					# charger still not connected
					batlooper=1
					sleep 1
				else
					batlooper=0
					killall jamfHelper
					logInUEX "AC power connected"
					sleep 1
				fi
			done
		elif [[ "$skipOver" != true ]]; then
			reqlooper=0
		fi # if power required and  on AC and PostPoneClickResult is Empty
		BatteryTest=$(pmset -g batt)
		if [[ $checks == *"power"* ]] && [[ "$BatteryTest" != *"AC"* ]] && [[ -z $PostponeClickResult ]]; then
			reqlooper=1
		else
			if [[ $logoutClickResult == *"2" ]]; then
				reqlooper=1
			elif [[ -z $logoutClickResult ]] && [[ "$skipOver" != true ]]; then
				reqlooper=0
			elif [[ "$skipOver" != true ]]; then
				reqlooper=0
			fi
		fi # power reqlooper change
	done # reqlooper is on = 1 for logged in users

	## Count up on Delay choice
	if [[ $PostponeClickResult -gt 0 ]]; then
		# user chose to postpone so add number to postpone
		delayNumber=$((delayNumber+1))
	fi

else # loginuser is null therefore no one is logged in and
	logInUEX "No one is logged in"
	if [[ -a $UEXPath/defer_jss/"$packageName".plist ]]; then
		# echo delay exists
		# installNow=$(/usr/libexec/PlistBuddy -c "print loginscreeninstall" $UEXPath/defer_jss/"$packageName".plist 2>/dev/null)
		installNow=$(fn_getPlistValue "loginscreeninstall" "defer_jss" "$packageName.plist")
		echo $installNow
		if [[ $installNow == "true" ]]; then
			logInUEX "Install at login permitted"
			# install at login permitted
			BatteryTest=$(pmset -g batt)
			if [[ $checks == *"power"* ]] && [[ "$BatteryTest" != *"AC"* ]]; then
				logInUEX "Power not connected postponing 24 hours"
				echo power not connected postponing 24 hours
				delayNumber=$((delayNumber+0))
				PostponeClickResult=86400
			else
				logInUEX "All requirements complete $actioning"
				# all requirements complete installing
# 				skipNotices="true"
				PostponeClickResult=""
			fi
		else
		logInUEX "Install at login NOT permitted"
		# install at login NOT permitted
			skipNotices="true"
			PostponeClickResult=3600
		fi
	fi
fi # No user is logged in

##########################################################################################
##										Postpone Stage									##
##########################################################################################

if [[ $PostponeClickResult -gt 0 ]]; then
	if [[ $PostponeClickResult = 86400 ]]; then
		# get the time tomorrow at 9am and delay until that time.
		tomorrow=$(date -v+1d)
		tomorrowTime=$(echo $tomorrow | awk '{ print $4}')
		tomorrow9am="${tomorrow/$tomorrowTime/09:00:00}"
		tomorrow9amEpoch=$(date -j -f '%a %b %d %T %Z %Y' "$tomorrow9am" '+%s')
		nowEpoch=$(date +%s)
		PostponeClickResult=$((tomorrow9amEpoch-nowEpoch))
	fi
	# User chose postpone time
	delaytime=$PostponeClickResult
	logInUEX "Delay Time = $delaytime"
	# calculate time and date just before plist creation
	runDate=$(date +%s)
	runDate=$((runDate-300))
	runDateFriendly=$(date -r$runDate)
	# Calculate the date that
	delayDate=$((runDate+delaytime))
	delayDateFriendly=$(date -r $delayDate)
	##### set delay date to deadline date if user postponed the defferal is more than the deadline
	if [[ $daysLeft -eq 0 ]] &&  [[ $delayDate -gt $dlEpoch ]]; then
		delayDate=$dlEpoch
		delayDateFriendly=$(date -r $delayDate)
		logInUEX "Overwrote user's delay date to deadline date: $delayDateFriendly"
	fi
	logInUEX "The install is postponed until $delayDateFriendly"
	if [[ $selfservicePackage = true ]]; then
		logInUEX "SELF SERVICE postponed section"
	else
		#if the defer folder if empty and i'm creating the first deferal then invetory updates are needed to the comptuer is in scope of the deferral service
		deferfolderContents=$(ls "$UEXPath/defer_jss/" | grep plist)
		if [[ -z "$deferfolderContents" ]]; then
			InventoryUpdateRequired=true
		fi
		if [[ -a $UEXPath/defer_jss/"$packageName".plist ]]; then
		# Create Plist with postpone properties
			fn_setPlistValue "folder" "$deferpackages" "defer_jss" "$packageName.plist"
			fn_setPlistValue "delayDate" "$delayDate" "defer_jss" "$packageName.plist"
			fn_setPlistValue "delayDateFriendly" "$delayDateFriendly" "defer_jss" "$packageName.plist"
			fn_setPlistValue "delayNumber" "$delayNumber" "defer_jss" "$packageName.plist"
			fn_setPlistValue "presentationDelayNumber" "$presentationDelayNumber" "defer_jss" "$packageName.plist"
			fn_setPlistValue "inactivityDelay" "$inactivityDelay" "defer_jss" "$packageName.plist"
			fn_setPlistValue "loginscreeninstall" "$loginscreeninstall" "defer_jss" "$packageName.plist"
		else
			# Create Plist with postpone properties
			fn_addPlistValue "folder" "string" "$deferpackages" "defer_jss" "$packageName.plist"
			fn_addPlistValue "delayDate" "string" "$delayDate" "defer_jss" "$packageName.plist"
			fn_addPlistValue "delayDateFriendly" "string" "$delayDateFriendly" "defer_jss" "$packageName.plist"
			fn_addPlistValue "delayNumber" "string" "$delayNumber" "defer_jss" "$packageName.plist"
			fn_addPlistValue "presentationDelayNumber" "string" "$presentationDelayNumber" "defer_jss" "$packageName.plist"
			fn_addPlistValue "inactivityDelay" "string" "$inactivityDelay" "defer_jss" "$packageName.plist"
			fn_addPlistValue "loginscreeninstall" "string" "$loginscreeninstall" "defer_jss" "$packageName.plist"
		fi
	fi
fi

##########################################################################################
##									Installation Stage									##
##########################################################################################

# If no postpone time was set then start the install
if [[ $PostponeClickResult == "" ]]; then
# Do not update invtory update if UEX is only being used for notificaitons
# if its an innstallation polciy then update invetory at the end
	if [[ "$checks" != "notify" ]] || [[ "$checks" != "notify custom" ]]; then
		InventoryUpdateRequired=true
	fi
	logInUEX "Starting the installation stage."

	##########################
	# Install Started Notice #
	##########################
	if [[ $selfservicePackage = true ]] || [[ $skipNotices != "true" ]]; then
		if [[ $installDuration -le 4 ]]; then
		status="$heading
starting $action..."
			if [[ "$loggedInUser" ]]; then
				"$CocoaDialog" bubble --title "$title" --text "$status" --icon-file "$icon"
			else
				"$jhPath" -icon "$icon" -windowType hud -windowPosition lr -startlaunchd -title "$title" -description "$status" -timeout 5 > /dev/null 2>&1
			fi
		fi
		logInUEX "Notified user $heading, starting $action... "
		if [[ -z "$loggedInUser" ]]; then
# 		"$jhPath" -icon "$icon" -windowType hud -windowPosition lr -startlaunchd -title "$title" -description "$status" -timeout 5 > /dev/null 2>&1 &

		/bin/rm /Library/LaunchAgents/com.UEX.jamfhelper.plist > /dev/null 2>&1
	cat <<EOT >> /Library/LaunchAgents/com.UEX.jamfhelper.plist
		<?xml version="1.0" encoding="UTF-8"?>
		<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
		<plist version="1.0">
		<dict>
		<key>Label</key>
		<string>com.jamfsoftware.jamfhelper.plist</string>
		<key>RunAtLoad</key>
		<true/>
		<key>LimitLoadToSessionType</key>
		<string>LoginWindow</string>
		<key>ProgramArguments</key>
		<array>
		<string>/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper</string>
		<string>-windowType</string>
		<string>hud</string>
		<string>-windowPosition</string>
		<string>lr</string>
		<string>-title</string>
		<string>"$title"</string>
		<string>-lockHUD</string>
		<string>-description</string>
		<string>$heading, $action is in progress please do not power off the computer.</string>
		<string>-icon</string>
		<string>"$icon"</string>
		</array>
		</dict>
		</plist>
EOT

		chown root:wheel /Library/LaunchAgents/com.UEX.jamfhelper.plist
		chmod 644 /Library/LaunchAgents/com.UEX.jamfhelper.plist
		launchctl load /Library/LaunchAgents/com.UEX.jamfhelper.plist
		sleep 5
		killall loginwindow > /dev/null 2>&1
		sleep 1
		rm /Library/LaunchAgents/com.UEX.jamfhelper.plist

		fi # no on logged in
	fi # skip notice is not true or is a self service install
	#mkosigi

	##########################################################################################
	##									STARTING ACTIONS									##
	##########################################################################################

		#####################
		# 		Quit	 	#
		#####################
		if [[ "$checks" == *"quit"* ]]; then
		# Quit all the apps2quit that were running at the time of the notifcation
		# Generate the list of apps still running that need to
			fn_generatateApps2quit
			if [[ $apps2quit != "" ]]; then
				apps2Relaunch=()
				for app in "${apps2quit[@]}"; do
					IFS=$'\n'
					appid=$(ps ax | grep /Applications/"$app"/ | grep -v grep | grep -v jamf | awk {'print $1'})
					# Processing application $app
						if  [[ $appid != "" ]]; then
							for id in $appid; do
								# Application  $app is still running.
								# Killing $app. pid is $id
								logInUEX "$app is still running. Quitting app."
								apps2Relaunch+=($app)
								kill -9 $id
							done
						fi
				done
				unset IFS
			fi
		fi

		#####################
		# 		Block	 	#
		#####################
		if [[ "$checks" == *"block"* ]]; then
			# Quit all the apps
			for app in "${apps[@]}"; do
				IFS=$'\n'
				appid=$(ps ax | grep /Applications/"$app"/ | grep -v grep | grep -v jamf | awk {'print $1'})
				# Processing application $app
					if  [[ $appid != "" ]]; then
						for id in $appid; do
							# Application  $app is still running.
							# Killing $app. pid is $id
							kill -9 $id
							logInUEX "$app is still running. Quitting app."
						done
					fi
			done
		unset IFS
		# calculate time and date just before plist creation
		runDate=$(date +%s)
		runDateFriendly=$(date -r$runDate)
		fn_addPlistValue "name" "string" "$heading" "block_jss" "$packageName.plist"
		fn_addPlistValue "packageName" "string" "$packageName" "block_jss" "$packageName.plist"
		fn_addPlistValue "runDate" "string" "$runDate" "block_jss" "$packageName.plist"
		fn_addPlistValue "runDateFriendly" "string" "$runDateFriendly" "block_jss" "$packageName.plist"
		fn_addPlistValue "apps2block" "string" "$apps2block" "block_jss" "$packageName.plist"
		fn_addPlistValue "checks" "string" "$checks" "block_jss" "$packageName.plist"
		# Start the agent to actively block the applications
		logInUEX "Starting Blocking Service"
		triggerNgo uexblockagent
	fi

	#####################
	# 		Logout	 	#
	#####################
	if [[ "$checks" == *"logout"* ]]; then
	logInUEX "script wants me to logout"
		loggedInUser=$(/bin/ls -l /dev/console | /usr/bin/awk '{ print $3 }')
		# calculate time and date just before plist creation
		runDate=$(date +%s)
		runDateFriendly=$(date -r$runDate)

		if [[ -a $UEXPath/logout_jss/"$packageName".plist ]]; then
			fn_setPlistValue "name" "$heading" "logout_jss" "$packageName.plist"
			fn_setPlistValue "packageName" "$packageName" "logout_jss" "$packageName.plist"
			fn_setPlistValue "runDate" "$runDate" "logout_jss" "$packageName.plist"
			fn_setPlistValue "runDateFriendly" "$runDateFriendly" "logout_jss" "$packageName.plist"
			fn_setPlistValue "loggedInUser" "$loggedInUser" "logout_jss" "$packageName.plist"
			fn_setPlistValue "checked" "false" "logout_jss" "$packageName.plist"
		else
			fn_addPlistValue "name" "string" "$heading" "logout_jss" "$packageName.plist"
			fn_addPlistValue "packageName" "string" "$packageName" "logout_jss" "$packageName.plist"
			fn_addPlistValue "runDate" "string" "$runDate" "logout_jss" "$packageName.plist"
			fn_addPlistValue "runDateFriendly" "string" "$runDateFriendly" "logout_jss" "$packageName.plist"
			fn_addPlistValue "loggedInUser" "string" "$loggedInUser" "logout_jss" "$packageName.plist"
			fn_addPlistValue "checked" "bool" "false" "logout_jss" "$packageName.plist"
		fi
	fi

	########################################################################################
	## 									INSTALL STAGE									  ##
	########################################################################################
	#Inform user that items are being installed, if the duration is 5 minutes or longer
		if  [[ "$loggedInUser" ]] && [[ $installDuration -ge 3 ]] && [[ $skipNotices != "true" ]]; then
		 	InstallationMsg="Now installing:

$patch4dialog

This will take about $installDuration minutes…
                 
"
	  	 "$jhPath" -windowType hud -lockHUD -description "$InstallationMsg" -icon "$icon" -title "$title" -heading "$heading" &
		fi

	# start SW 01/18/2018
	if [[ ${triggers[@]} != "" ]]; then
		logInUEX "==== installation started ${triggers[@]}"
		for trigger in ${triggers[@]}; do
			#fn_checkJSSConnection "trigger - $trigger"
			echo "$jamfBinary" policy -forceNoRecon -trigger "$trigger"
			"$jamfBinary" policy -forceNoRecon -trigger "$trigger" | /usr/bin/tee -a "$logfilepath"
		done
	fi
	
	# start SW 06/22/2020
	#adobe update install section
	if [[ $adobeUpdatesAvail == true ]]; then
		logInUEX "Starting Adobe software updates"
		adobeUpdateStatus=$("$rum" --action=install)
		logInUEX "$updatestatus"
		if [[ "$adobeUpdateStatus" == *"Fail"* ]]; then
			failedInstall=true
		fi
	fi
	#end SW

	# start SW 01/18/2019
		#sus version
	if [[ $updatesavail == true ]]; then
		logInUEX "Starting Apple software updates"
		updatestatus=$(softwareupdate -ir)
		logInUEX "$updatestatus"
		if [[ "$updatestatus" == *"Error"* ]]; then
			checks=${checks//restart/}
			logInUEX "Remove restart from checks"
			failedInstall=true
		else
			if [[ "$updatestatus" == *"halt"* ]]; then
				checks+=";shutdown"
#				checks=${checks//restart/} 
				logInUEX "Remove restart from checks and adding Shutdown as update needs shutdown"
				logInUEX "checks are: $checks; shutdownflag is: $ShutdownFlag"
			fi
		fi
	fi
	# end SW

	########################################################################################
	## 									POST INSTALL ACTIONS 							  ##
	########################################################################################

	#####################
	# Stop Progress Bar #
	#####################
	#kill user notification
	logInUEX "killing install notification"
	killall jamfHelper  > /dev/null 2>&1

	###########################
	# Install Complete Notice #
	###########################
	#stop the currently installing if no one is logged in
	if [[ -z $loggedInUser ]]; then
		killall jamfHelper
	fi
	if [[ $selfservicePackage = true ]] || [[ $skipNotices != "true" ]]; then
		status="$heading
$action completed."
		logInUEX "selfservicepackae=true || skipnotices != true"
		if [[ "$loggedInUser" ]]; then
			logInUEX "there is a logged in user"
			"$CocoaDialog" bubble --title "$title" --text "$status" --icon-file "$icon"
		else
			logInUEX "there is not a logged in user"
			"$jhPath" -icon "$icon" -windowType hud -windowPosition lr -startlaunchd -title "$title" -description "$status" -timeout 5 > /dev/null 2>&1
		fi
		logInUEX "Notified user $heading, Completed"
	fi

	#####################
	# 		Block	 	#
	#####################
	if [[ "$checks" == *"block"* ]]; then
		# delete the plist with properties to stop blocking
		logInUEX "Deleting the blocking plist"
		/bin/rm "$UEXPath/block_jss/${packageName}.plist" > /dev/null 2>&1
	fi

	#####################
	# 		Logout	 	#
	#####################
	if [[ "$checks" == *"logout"* ]]; then
		# Start the agent to prompt logout
		logInUEX "Starting logout Daemon"
		triggerNgo uexlogoutagent &
	fi

	#####################
	# 		Restart	 	#
	#####################
	if [[ "$checks" == *"shutdown"* ]]; then
		# Start the agent to prompt Shutdown
		logInUEX " shutdown required"
		checks=${checks//restart/}
		ShutdownFlag=1
		#testing
		logInUEX "shutdownflag is : $ShutdownFlag"
	fi
	if [[ "$checks" == *"restart"* ]]; then
			#testing
			logInUEX "checks are: $checks; shutdownflag is: $ShutdownFlag"
		# Start the agent to prompt restart
		logInUEX "restart required"
		ShutdownFlag=2
	fi
	failedInstall=false
	#testing
	logInUEX "failedInstall: $failedInstall"
fi

##########################################################################################
##							Wrapping Error Ending for badVariable						##
##							DO NOT PUT ANY ACTIONS UNDER HERE							##
##########################################################################################

else
	failedInstall=true
	logInUEX "Critical error. Sending log to Jamf and exiting."
	logCriticalErrors
	#testing
		logInUEX "failedInstall: $failedInstall"
fi # Installations

##########################################################################################
#									 Stop LaunchDaemon									 #
##########################################################################################
if [[ "$failedInstall" = true ]]; then
	exit 1
fi

##################
# Clear Deferral #
##################
# Delete defer plist so the agent doesn't start it again
logInUEX "Deleting defer plist so the agent does not start it again"

# go thourgh all the deferal plist and if any of them mention the same triggr then delete them
plists=$(ls $UEXPath/defer_jss/ | grep ".plist")
IFS=$'\n'
for i in $plists; do
	deferPolicyTrigger=$(fn_getPlistValue "policyTrigger" "defer_jss" "$i")
	if [[ "$deferPolicyTrigger" == "$UEXpolicyTrigger" ]]; then
		logInUEX "Deleting $i"
		/bin/rm $UEXPath/defer_jss/"$i" > /dev/null 2>&1
	fi
done

#remove plist before shutdowns to prevent daemon from launching at startup
if [[ -e "/Library/LaunchDaemons/com.sfdc-patching.uex.plist" ]]; then
	rm -f /Library/LaunchDaemons/com.sfdc-patching.uex.plist
	logInUEX "Deleting Daemon plist so the agent does not start again"
fi

sleep 5
logInUEX "checks are: $checks; shutdownflag is: $ShutdownFlag"

if [[ $ShutdownFlag -gt 0 ]] && [[ $loggedInUser ]]; then
	notice='In order for the changes to complete you must restart your computer. Please save your work and click "Restart Now" within the allotted time.

Your computer will be automatically restarted at the end of the countdown.'
	restartclickbutton=$("$jhPath" -windowType hud -lockHUD -windowPostion lr -title "$title" -description "$notice" -icon "$icon" -timeout 3599 -countdown -alignCountdown center -button1 "Restart Now")
# restart or shutdown depending on apple update
	osVers=$(sw_vers -productVersion |awk -F'.' '{print$1}')
	if [[ "$osVers" -gt "10" && ("$ShutdownFlag" == "1" || "$ShutdownFlag" == "2") ]]; then
		##section suggested by Mike Lynn (kill processes of logged in user)
		#get GUI logged in username
		user=$( /usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }} ' )
		# grab all user processes, filter to those that are not built-in core applications or known CLI tools, obtain the PIDs of the remaining processes and kill -9 them
		/bin/ps uxww -U "$user" | /usr/bin/grep "$user" | /usr/bin/grep -v -e "/System/Library" -e "/usr/" -e ".appex/Contents" | /usr/bin/grep "/" | /usr/bin/awk '{ print $2 };' | while IFS= read -r pid; do kill -9 "$pid"; done
		#back to the normally scheduled program (restart with -irR)
		logInUEX "Initiating 'softwareupdate -irR --force'"
		log2Jamf
		sleep 3
		softwareupdate -irR --force
	elif [[ "$ShutdownFlag" == "1" ]]; then
		#shutdown
		logInUEX "Initiating 'shutdown -h now'"
		log2Jamf
		sleep 3
		shutdown -h now
	elif [[ "$ShutdownFlag" == "2" ]]; then
		#restart
		logInUEX "Initiating 'shutdown -r now'"
		log2Jamf
		sleep 3
		shutdown -r now
	fi
fi

if [[ "$InventoryUpdateRequired" == true ]] && [[ $packages != "" ]]; then
	logInUEX "Inventory Update Required"
	$jamfBinary recon
fi

# check if launchdaemon is running
launchdstatus=$(launchctl list | grep -i com.sfdc-patching.uex | awk {'print $3'})
if [[ "$launchdstatus" != "" ]]; then
	logInUEX "unloading uex agent"
	logInUEX "******* Script Complete *******"
	echo "" >> "$logfilepath"
	log2Jamf
	launchctl unload /Library/LaunchDaemons/com.sfdc-patching.uex.plist
	launchctl remove com.sfdc-patching.uex	# patching is completed remove the agent
fi

logInUEX "******* Script Complete *******"
echo "" >> "$logfilepath"
log2Jamf

exit 0
