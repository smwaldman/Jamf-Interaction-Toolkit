#!/bin/bash
set -x
jamfBinary="/usr/local/jamf/bin/jamf"

launchDaemonName="github.cubandave.UEX-uex_inventory_update_agent"
nameOfCustomEvent="uex_inventory_update_agent"

##########################################################################################
##										Functions										##
##########################################################################################


fn_checkIfRunningAsDaemon () {
	#only kill the pleaseWaitDaemon if it's running
	launchcltList=$( launchctl list )
	launchcltPID=$( launchctl list  | grep "$launchDaemonName" | awk '{ print $1 }'  )
	if [[ "$launchcltList" == *"$launchDaemonName"* ]] && [[ "$launchcltPID" != "-" ]] ; then
		#statements
		echo true
	else
		echo false
	fi
}

fn_makePolicyADaemon () {
	if [[ "$(fn_checkIfRunningAsDaemon)" == false ]] || [[ -e "/Library/LaunchDaemons/$launchDaemonName.plist" ]] ; then
		fn_writeLaunchDaemonForAgent
		exit 0
	fi
}

fn_writeLaunchDaemonForAgent () {
	rm "/Library/LaunchDaemons/$launchDaemonName.plist" 
	cat >> "/Library/LaunchDaemons/$launchDaemonName.plist" <<EndUexAgentDaemon
	<?xml version="1.0" encoding="UTF-8"?>
	<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
	<plist version="1.0">
	<dict>
		<key>Label</key>
		<string>$launchDaemonName</string>
		<key>ProgramArguments</key>
		<array>
			<string>/bin/bash</string>
			<string>-c</string>
			<string>$jamfBinary policy -event $nameOfCustomEvent</string>
		</array>
		<key>RunAtLoad</key>
		<false/>
	</dict>
	</plist>
EndUexAgentDaemon

	chown root:wheel "/Library/LaunchDaemons/$launchDaemonName.plist"
	chmod 644 "/Library/LaunchDaemons/$launchDaemonName.plist"

	launchctl unload -w "/Library/LaunchDaemons/$launchDaemonName.plist"
	launchctl load -w "/Library/LaunchDaemons/$launchDaemonName.plist"
	launchctl start -w "/Library/LaunchDaemons/$launchDaemonName.plist"
}

fn_removeLaunchDaemon () {


	# delete the daemon for cleanup #
	# /bin/rm "/Library/LaunchDaemons/$launchDaemonName.plist"
	launchctl remove -w "$launchDaemonName"

	# only kill the pleaseWaitDaemon if it's running
	launchcltList=$( launchctl list )
	if [[ "$launchcltList" == *"$launchDaemonName"* ]] ; then
		#statements
		launchctl unload -w "/Library/LaunchDaemons/$launchDaemonName.plist" > /dev/null 2>&1
	fi
}

fn_makePolicyADaemon

# uex_inventory_update_agent

# Wait until only the UEX agents are running then run a recon
## This is needed to rule out only what's needed
# shellcheck disable=SC2009
otherJamfprocess=$( ps aux | grep jamf | grep -v grep | grep -v launchDaemon | grep -v jamfAgent | grep -v uexrestartagent | grep -v uex_inventory_update_agent | grep -v uexlogoutagent )
while [[ $otherJamfprocess != "" ]] ; do 
	sleep 15
	## This is needed to rule out only what's needed
	# shellcheck disable=SC2009
	otherJamfprocess=$( ps aux | grep jamf | grep -v grep | grep -v launchDaemon | grep -v jamfAgent | grep -v uexrestartagent | grep -v uex_inventory_update_agent | grep -v uexlogoutagent )
done


$jamfBinary recon

fn_removeLaunchDaemon

exit 0

##########################################################################################
##									Version History										##
##########################################################################################
# 
# Oct 24, 2018 	v4.0	--cubandave--	All Change logs are available now in the release notes on GITHUB