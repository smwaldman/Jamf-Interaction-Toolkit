#!/bin/bash

# Used for major debugging
# set -x

##### Static Variables #####

debug=false
pathToScriptRunning="$0"
checkInDaemon="/Library/LaunchDaemons/com.jamfsoftware.task.1.plist"
checkInFixerDaemon="/Library/LaunchDaemons/github.cubandave-uex.checkfixer.plist"
checkInFixerScript="/usr/local/libexec/00-UEX-Fix-Check-in-Daemon-jss.sh"

##### Functions #####

fn_checkIfJamfProcessIsRunning () {
	pgrep -f "jamf $1"
}

fn_wait4ManagementFrameworkUpdate () { 
	while [[ -n "$(fn_checkIfJamfProcessIsRunning "manage")" ]] ; do
		sleep 1
	done
}

fn_wait4CheckInToFinish () { 
	while [[ -n "$(fn_checkIfJamfProcessIsRunning "policy -randomDelaySeconds")" ]] ; do
		sleep 1
	done
}


fn_writeAndLoadCheckinDaemonFixer () {
	echo '<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Disabled</key>
	<false/>
	<key>Label</key>
	<string>github.cubandave-uex.checkinfixer</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/local/libexec/00-UEX-Fix-Check-in-Daemon-jss.sh</string>
	</array>
	<key>RunAtLoad</key>
	<false/>
	<key>WatchPaths</key>
	<array>
		<string>/Library/LaunchDaemons/</string>
	</array>
</dict>
</plist>' > "$checkInFixerDaemon"

	chown root:wheel "$checkInFixerDaemon"
	chmod 644 "$checkInFixerDaemon"

	launchctl unload "$checkInFixerDaemon" 2> /dev/null
	launchctl load "$checkInFixerDaemon"

}

fn_copyScriptLocally () {
	if [[ ! -d "/usr/local/libexec" ]] ; then
		mkdir -p "/usr/local/libexec"
	fi

	cp "$pathToScriptRunning" "$checkInFixerScript"
	chown root:wheel "$checkInFixerScript"
	chmod 755 "$checkInFixerScript"
}

if [[ "$debug" != true ]]; then 
	# If the script is running from the JSS it will write the script and daemon and stop
	if [[ "$pathToScriptRunning" != "$checkInFixerScript" ]] ; then
		fn_copyScriptLocally
		fn_writeAndLoadCheckinDaemonFixer
		touch "$checkInDaemon"
		exit 0
	fi
fi

##### Magic Starts Here #####

fn_wait4CheckInToFinish
fn_wait4ManagementFrameworkUpdate


# make the contents of the daemon, this is genralised so you kned to spefiy your check in time
# These are needed to pass to xpath and the format needed for xpath to work
# shellcheck disable=SC2002,SC2140
mainXML="$(cat "$checkInDaemon" | xpath "/plist[@version="1.0"]/dict" 2> /dev/null)"

# if theres a checkin daemon, and it contains content in the $mainXML and it doesn't already have the setting set
if [[ -e "$checkInDaemon" ]] && [[ "$mainXML" != *"AbandonProcessGroup"* ]] && [[ "$mainXML" ]] ; then

	# make the start of the plist
	newDaemon="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
"
	# remove the </dict> since it will be added later
	newDaemon+="${mainXML//<\/dict>/}"

	# add the abandon proccess to the check in daemon an close up the plist
	newDaemon+="	<key>AbandonProcessGroup</key>
	<true/>
</dict>
</plist>"

	# overwrite with  a new plist, overwriting the old one and set permissions
	echo "$newDaemon" > "$checkInDaemon"
	chown root:wheel "$checkInDaemon"
	chmod 644 "$checkInDaemon"

	# unload and reload daemon so it takes effect
	launchctl unload "$checkInDaemon"
	launchctl load "$checkInDaemon"

	exit 0

else 
	exit 0

fi
