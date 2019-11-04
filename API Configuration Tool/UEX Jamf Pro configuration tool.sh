#!/bin/bash
set -x
loggedInUser=$( /bin/ls -l /dev/console | /usr/bin/awk '{ print $3 }' | grep -v root )

fn_write_uex_Preference () {
	local domain="$1"
	local key="$2"
	defaults write github.cubandave.uex.api.plist "$domain" "$key" 2> /dev/null
}

fn_read_uex_Preference () {
	local domain="$1"
	defaults read github.cubandave.uex.api.plist "$domain" 2> /dev/null
}

fn_delete_JamfUEXGETfolder () {
	if [[ "$AylaMethod" == y ]] ; then
		rm -rf "$AylaMethodFolder"
		printf "Deleting '%s ]:\n" "$AylaMethodFolder"
	fi
}

##########################################################################################
##								Jamf Interaction Configuration 							##
##########################################################################################


# if you use the general method of addind and removing the requiremnt for help desk support to clear
# disk space then you should leave these as is
UEXhelpticketTrigger="add_to_group_for_disk_space_help_ticket"
ClearHelpTicketRequirementTrigger="remove_from_group_for_disk_space_help_ticket"

standardIcon="/Library/Application Support/JAMF/Jamf.app/Contents/Resources/AppIcon.icns"

title="UEX - Jamf Pro Configuration Tool"

##########################################################################################
##								Start of Configuration 									##
##########################################################################################
##########################################################################################
##							DO NOT MAKE ANY CHANGES BELOW								##
##########################################################################################


##########################################################################################
##										Functions										##
##########################################################################################


fn_getAPICredentials	() {
	DefaultJssUser="$(fn_read_uex_Preference "DefaultJssUser")"
	DefaultJssUser="${DefaultJssUser:-jssadmin}"
	
	fn_genericDialogCocoaDialogStyleAnswer "$title" "Please enter your the User Name for the jamf admin account:" "" "$DefaultJssUser" "Cancel" "OK" "" "$standardIcon"
	jss_user="$myTempResult"

	if [[ "$jss_user" != "$DefaultJssUser" ]]; then
		#statements
		fn_Check2SaveDefault "DefaultJssUser" "$DefaultJssUser" "$jss_user"
	fi


	jss_pass="$(sudo -u "$loggedInUser" /usr/bin/osascript -e 'display dialog "Please enter your current password for the account: (default: jamf1234)" with hidden answer default answer "jamf1234" with title "UEX - Jamf Pro Configuration Tool" with text buttons {"Cancel","OK"} default button 2 with icon file ("/Library/Application Support/JAMF/Jamf.app/Contents/Resources/AppIcon.icns" as POSIX file)' -e 'text returned of result')"

	DefaultJssURL="$(fn_read_uex_Preference "DefaultJssURL")"
	DefaultJssURL="${DefaultJssURL:-https://cubandave.local:8443}"
	fn_genericDialogCocoaDialogStyleAnswer "$title" "Please enter the URL for your Jamf Pro Server:" "" "$DefaultJssURL" "Cancel" "OK" "" "$standardIcon"
	jss_url="$myTempResult"

	## strip trailing slash
	if [[ "$jss_url" == *"/" ]]; then
		jss_url=$(/bin/echo "$jss_url" | /usr/bin/sed -e "s/.$//g" )

	fi
	jss_url="${jss_url// /:}" 

	if [[ "$jss_url" != "$DefaultJssURL" ]]; then
		#statements
		fn_Check2SaveDefault "DefaultJssURL" "$DefaultJssURL" "$jss_url"
	fi


}

fn_Check2SaveDefault () {
	local domain="$1"
	local previous="$2"
	local new="$3"

	local Check2SaveMessage
	Check2SaveMessage="Do you want to save this as a new default $domain for next time?
New Setting: 
${new}
Previous Default: 
${previous}"

	fn_genericDialogCocoaDialogStyle3Buttons "$title" "$Check2SaveMessage" "" "Cancel" "No" "Save" "" "$standardIcon"
	Check2SaveButton="$myTempResult"

	if [[ "$Check2SaveButton" == "Save" ]] ; then
		fn_write_uex_Preference "$domain" "$new"
	fi

}

fn_genericDialogCocoaDialogStyle3Buttons() 
{
    myTempResult=""
    myTempResult=$(osascript <<OSA
        try
        display dialog "$(printf '%s\n' "$2")" with title "$(printf '%s' "$1")" buttons {"$(printf '%s' "$4")", "$(printf '%s' "$5")", "$(printf '%s' "$6")"} with icon POSIX file "$(printf '%s' "$8")" default button 3

        on error number -128
			set myTempResult to "result:Cancel" as text
		end try

OSA
)
	if [[ "$myTempResult" == "result:Cancel" ]] ; then /bin/echo "User cancelled" ; fn_cleanExit 1 ; fi
	myTempResult="$(echo "$myTempResult" | awk -F':' '{ print $2 }')"
}

# fn_genericDialogCocoaDialogStyleAnswer "This is a title" "This is the text" "" "default answer" "Not OK" "OK" "" "caution")
fn_genericDialogCocoaDialogStyleAnswer () 
{
    myTempResult=""
    myTempResult=$(osascript <<OSA
        try
        display dialog "$(printf '%s\n' "$2")" with title "$(printf '%s' "$1")" default answer "$(printf '%s' "$4")" buttons {"$(printf '%s' "$5")", "$(printf '%s' "$6")"} with icon POSIX file "$(printf '%s' "$8")" default button 2

        on error number -128
			set myTempResult to "result:Cancel" as text
		end try
OSA
)
	if [[ "$myTempResult" == "result:Cancel" ]] ; then /bin/echo User cancelled ; fn_cleanExit 1 ; fi
	myTempResult="$(echo "$myTempResult" | awk -F':' '{ $1=""; $2=""; print}' | cut -c 3- )"
}

fn_cleanExit (){
	##echo Error
	if [[ "$2" ]] ; then /bin/echo "$2" ; fi 
	exit "$1"

}

fn_genericDialogCocoaDialogStyle3ButtonsWithDefaultButton() 
{
    myTempResult=""
    myTempResult=$(osascript <<OSA
        try
        display dialog "$(printf '%s\n' "$2")" with title "$(printf '%s' "$1")" buttons {"$(printf '%s' "$4")", "$(printf '%s' "$5")", "$(printf '%s' "$6")"} with icon POSIX file "$(printf '%s' "$8")" default button "$(printf '%s' "$9")"

        on error number -128
			set myTempResult to "result:Cancel" as text
		end try

OSA
)
	if [[ "$myTempResult" == "result:Cancel" ]] ; then /bin/echo "User cancelled" ; fn_cleanExit 1 ; fi
	myTempResult="$(echo "$myTempResult" | awk -F':' '{ print $2 }')"
}

# fn_genericDialogCocoaDialogStyleError "This is the text" "$standardIcon" "exitCode"
fn_genericDialogCocoaDialogStyleError() {
   
    myTempResult=""
    myTempResult=$(osascript <<OSA
        display dialog "$(printf '%s\n' "$1")" with title "$(printf '%s' "$title")" buttons {"OK"} with icon POSIX file "$(printf '%s' "$2")" default button 1

OSA
)
	fn_cleanExit "$3"
}


# fn_genericDialogCocoaDialogStyleMessage "This is the text" "$standardIcon"
fn_genericDialogCocoaDialogStyleMessage() {
   
    myTempResult=""
    myTempResult=$(osascript <<OSA
        display dialog "$(printf '%s\n' "$1")" with title "$(printf '%s' "$title")" buttons {"OK"} with icon POSIX file "$(printf '%s' "$2")" default button 1

OSA
)
}

##########################################################################################
#		 							Data Gathering!										 #
##########################################################################################

AylaMethodDefault="$(fn_read_uex_Preference "JamfCloud")"
AylaMethodDefault="${AylaMethodDefault:-Yes}"

AylaMethodMessage="Do you use jamf cloud or have been having problems with the API tool?"
fn_genericDialogCocoaDialogStyle3ButtonsWithDefaultButton "$title" "$AylaMethodMessage" "" "Cancel" "No" "Yes" "" "$standardIcon" "$AylaMethodDefault"
AylaMethodAnswer="$myTempResult"


if [[ "$AylaMethodAnswer" != "$AylaMethodDefault" ]]; then
	#statements
	fn_Check2SaveDefault "JamfCloud" "$AylaMethodDefault" "$AylaMethodAnswer"
fi


if [ "$AylaMethodAnswer" == "Yes" ] ;then
    AylaMethod=y
elif [ "$AylaMethodAnswer" == "No" ];then
    AylaMethod=n
fi

if [[ "$AylaMethod" == "y" ]] ; then 
	AylaMethodFolder="/private/tmp/uexGETXMLs/"
	if [[ ! -d "$AylaMethodFolder" ]] ;then
		mkdir "$AylaMethodFolder"
	fi

	AylaMethodNotification="This will write all the XMLs from the GET Commands to 
$AylaMethodFolder
Then it will delete the folder when done"
	fn_genericDialogCocoaDialogStyleMessage "$AylaMethodNotification" "$standardIcon"

fi

DebugMessage="Do you want to enable debug mode?"
fn_genericDialogCocoaDialogStyle3Buttons "$title" "$DebugMessage" "" "Cancel" "Yes" "No" "" "$standardIcon"
debugAnswer="$myTempResult"

if [ "$debugAnswer" == "Yes" ] ;then
    debug=true
elif [ "$debugAnswer" != "No" ];then
    debug=false
fi

if [[ "$debug" == true ]] ; then 
	debugFolder="/private/tmp/uexdebug-$(date)/"
	mkdir "$debugFolder"
	curlOptions="-s --show-error -v"
else
	curlOptions="-s --show-error"
fi

fn_getAPICredentials


# Set the category you'd like to use for all the policies

UEXCategoryNameDefault="$(fn_read_uex_Preference "UEXCategoryNameDefault")"
UEXCategoryNameDefault="${UEXCategoryNameDefault:-User Experience}"

fn_genericDialogCocoaDialogStyleAnswer "$title" "Enter the name of the category you want to use" "" "$UEXCategoryNameDefault" "Cancel" "OK" "" "$standardIcon"
UEXCategoryName="$myTempResult"

if [[ "$UEXCategoryName" != "$UEXCategoryNameDefault" ]]; then
	#statements
	fn_Check2SaveDefault "UEXCategoryNameDefault" "$UEXCategoryNameDefault" "$UEXCategoryName"
fi



packagesDefault="$(fn_read_uex_Preference "packagesDefault")"
packagesDefault="${packagesDefault:-UEXresourcesInstaller-201903130155.pkg}"

fn_genericDialogCocoaDialogStyleAnswer "$title" "Enter the package name for the UEX resources." "" "$packagesDefault" "Cancel" "OK" "" "$standardIcon"
packages="$myTempResult"

if [[ "$packages" != "$packagesDefault" ]]; then
	#statements
	fn_Check2SaveDefault "packagesDefault" "$packagesDefault" "$packages"
fi

## Keeping here to make testing easier
# packages=(
# "UEXresourcesInstaller-201903130155.pkg"
# )

# This enables the interaction for Help Disk Tickets
# By default it is disabled. For more info on how to use this check the wiki in the Help Desk Ticket Section

helpTicketsEnabledViaAppRestrictionDefault="$(fn_read_uex_Preference "helpTicketsEnabledViaAppRestriction")"
helpTicketsEnabledViaAppRestrictionDefault="${helpTicketsEnabledViaAppRestrictionDefault:-No}"

helpTicketsEnabledViaAppRestrictionMessage="Do you want to use the Restricted Software feature to be notfied to create Helpdesk tickets?"
fn_genericDialogCocoaDialogStyle3ButtonsWithDefaultButton "$title" "$helpTicketsEnabledViaAppRestrictionMessage" "" "Cancel" "No" "Yes" "" "$standardIcon" "$helpTicketsEnabledViaAppRestrictionDefault"
helpTicketsEnabledViaAppRestrictionAnswer="$myTempResult"


if [[ "$helpTicketsEnabledViaAppRestrictionAnswer" != "$helpTicketsEnabledViaAppRestrictionDefault" ]]; then
	#statements
	fn_Check2SaveDefault "helpTicketsEnabledViaAppRestriction" "$helpTicketsEnabledViaAppRestrictionDefault" "$helpTicketsEnabledViaAppRestrictionAnswer"
fi

if [ "$helpTicketsEnabledViaAppRestrictionAnswer" == "Yes" ] ;then
    helpTicketsEnabledViaAppRestriction=true
elif [ "$helpTicketsEnabledViaAppRestrictionAnswer" != "No" ];then
    helpTicketsEnabledViaAppRestriction=false
fi


if [[ "$helpTicketsEnabledViaAppRestriction" == true ]] ;then
	
	restrictedAppNameDefault="$(fn_read_uex_Preference "restrictedAppNameDefault")"
	restrictedAppNameDefault="${restrictedAppNameDefault:-User Needs Helps Clearing Space.app}"

	fn_genericDialogCocoaDialogStyleAnswer "$title" "Enter the package name for the UEX resources." "" "$restrictedAppNameDefault" "Cancel" "OK" "" "$standardIcon"
	restrictedAppName="$myTempResult"

	if [[ "$restrictedAppName" != "$restrictedAppNameDefault" ]]; then
		#statements
		fn_Check2SaveDefault "restrictedAppNameDefault" "$restrictedAppNameDefault" "$restrictedAppName"
	fi
fi


helpTicketsEnabledViaGeneralStaticGroupDefault="$(fn_read_uex_Preference "helpTicketsEnabledViaAppRestriction")"
helpTicketsEnabledViaGeneralStaticGroupDefault="${helpTicketsEnabledViaGeneralStaticGroupDefault:-No}"

helpTicketsEnabledViaGeneralStaticGroupMessage="Do you want to use a general static group to be notified to create Helpdesk tickets?"
fn_genericDialogCocoaDialogStyle3ButtonsWithDefaultButton "$title" "$helpTicketsEnabledViaGeneralStaticGroupMessage" "" "Cancel" "No" "Yes" "" "$standardIcon" "$helpTicketsEnabledViaGeneralStaticGroupDefault"
helpTicketsEnabledViaGeneralStaticGroupAnswer="$myTempResult"


if [[ "$helpTicketsEnabledViaGeneralStaticGroupAnswer" != "$helpTicketsEnabledViaGeneralStaticGroupDefault" ]]; then
	#statements
	fn_Check2SaveDefault "helpTicketsEnabledViaAppRestriction" "$helpTicketsEnabledViaGeneralStaticGroupDefault" "$helpTicketsEnabledViaGeneralStaticGroupAnswer"
fi

if [ "$helpTicketsEnabledViaAppRestrictionAnswer" == "Yes" ] ;then
    helpTicketsEnabledViaAppRestriction=true
elif [ "$helpTicketsEnabledViaAppRestrictionAnswer" != "No" ];then
    helpTicketsEnabledViaAppRestriction=false
fi


if [ "$helpTicketsEnabledViaGeneralStaticGroupAnswer" == "Yes" ] ;then
    helpTicketsEnabledViaGeneralStaticGroup=true
elif [ "$helpTicketsEnabledViaGeneralStaticGroupAnswer" == "No" ];then
    helpTicketsEnabledViaGeneralStaticGroup=false
fi

if [[ "$helpTicketsEnabledViaGeneralStaticGroup" == true ]] ;then
	
	staticGroupNameDefault="$(fn_read_uex_Preference "staticGroupNameDefault")"
	staticGroupNameDefault="${staticGroupNameDefault:-User Needs Helps Clearing Space}"

	fn_genericDialogCocoaDialogStyleAnswer "$title" "Enter the package name for the UEX resources." "" "$staticGroupNameDefault" "Cancel" "OK" "" "$standardIcon"
	staticGroupName="$myTempResult"

	if [[ "$staticGroupName" != "$staticGroupNameDefault" ]]; then
		#statements
		fn_Check2SaveDefault "staticGroupNameDefault" "$staticGroupNameDefault" "$staticGroupName"
	fi

fi


# helpTicketsEnabledViaAppRestriction=false
# helpTicketsEnabledViaGeneralStaticGroup=false
# restrictedAppName="User Needs Helps Clearing Space.app"
# staticGroupName="User Needs Help Clearing Disk Space"


##########################################################################################
# 								Do not change anything below!							 #
##########################################################################################

scripts=(
	"00-PleaseWaitUpdater-jss"
	"00-UEX-Deploy-via-Trigger"
	"00-UEX-Install-Silent-via-trigger"
	"00-UEX-Install-via-Self-Service"
	"00-UEX-Jamf-Interaction-no-grep"
	"00-UEX-Uninstall-via-Self-Service"
	"00-UEX-Update-via-Self-Service"
	"00-uexblockagent-jss"
	"00-uexdeferralservice-jss"
	"00-uexlogoutagent-jss"
	"00-uexrestartagent-jss"
	"00-uex_inventory_update_agent-jss"
	"00-API-Add-Current-Computer-to-Static-Group.sh"
	"00-API-Remove-Current-Computer-from-Static-Group.sh"
)

triggerscripts=(
	"00-UEX-Deploy-via-Trigger"
	"00-UEX-Install-Silent-via-trigger"
	"00-UEX-Install-via-Self-Service"
	"00-UEX-Uninstall-via-Self-Service"
	"00-UEX-Update-via-Self-Service"
)

apiScripts=(
	"00-API-Add-Current-Computer-to-Static-Group.sh"
	"00-API-Remove-Current-Computer-from-Static-Group.sh"
)

UEXInteractionScripts=(
"00-UEX-Jamf-Interaction-no-grep"
)



##########################################################################################
# 									API Functions										 #
##########################################################################################


FNputXML () 
	{
# shellcheck disable=SC2086
		# echo /usr/bin/curl ${curlOptions} -k "${jss_url}/JSSResource/$1/id/$2" -u "${jss_user}:${jss_pass}" -H \"Content-Type: text/xml\" -X PUT -d "$3"
		local result
# shellcheck disable=SC2086
		result=$(/usr/bin/curl ${curlOptions} -k "${jss_url}/JSSResource/$1/id/$2" -u "${jss_user}:${jss_pass}" -H "Content-Type: text/xml" -X PUT -d "$3")
		# updated to account for #86
		if [[ "$result" == *"<html>"* ]]; then
    		#statements
    		echo "ERROR: There was a problem updating $1: $2"
    		echo "$result"
    	fi

    }

FNpostXML () 
	{
		local name
		name="$3"
# shellcheck disable=SC2086
		# echo /usr/bin/curl ${curlOptions} -k "${jss_url}/JSSResource/$1/id/0" -u "${jss_user}:${jss_pass}" -H \"Content-Type: text/xml\" -X POST -d "$2"
		local result
# shellcheck disable=SC2086
		result=$(/usr/bin/curl ${curlOptions} -k "${jss_url}/JSSResource/$1/id/0" -u "${jss_user}:${jss_pass}" -H "Content-Type: text/xml" -X POST -d "$2")
    	# updated to account for #86
    	if [[ "$result" == *"<html>"* ]]; then
    		#statements
    		echo "ERROR: There was a problem with creating a new $1: $name"
    		echo "$result"
    	fi

    }

FNput_postXML () 
	{

	FNgetID "$1" "$2"
	pid=$retreivedID

	if [ "$pid" ] ; then
		echo "updating $1: ($pid) \"$2\"" 
		FNputXML "$1" "$pid" "$3"
		# echo ""
	else
		echo "creating $1: \"$2\""
		FNpostXML "$1" "$3" "$2"
		# echo ""
	fi

 	# updated to account for #86
	# FNtestXML "$1" "$2"
	}

FNput_postXMLFile () 
	{

	FNgetID "$1" "$2"
	pid=$retreivedID

	if [ "$pid" ] ; then
		echo "updating $1: ($pid) \"$2\"" 
		FNputXMLFile "$1" "$pid" "$3"
		# echo ""
	else
		echo "creating $1: \"$2\""
		FNpostXMLFile "$1" "$3"
		# echo ""
	fi

	# updated to account for #86
	# FNtestXML "$1" "$2"
	}

FNputXMLFile () 
	{	# echo /usr/bin/curl ${curlOptions} -k "${jss_url}/JSSResource/$1/id/$2" -u "${jss_user}:${jss_pass}" -H \"Content-Type: text/xml\" -X PUT -d "$3"
		# shellcheck disable=SC2086
		/usr/bin/curl ${curlOptions} -k "${jss_url}/JSSResource/$1/id/$2" -u "${jss_user}:${jss_pass}" -H "Content-Type: text/xml" -X PUT -T "$3"
	}


FNpostXMLFile () 
	{
		# shellcheck disable=SC2086
		# echo /usr/bin/curl ${curlOptions} -k "${jss_url}/JSSResource/$1/id/0" -u "${jss_user}:${jss_pass}" -H \"Content-Type: text/xml\" -X POST -d "$2"
		# shellcheck disable=SC2086
		/usr/bin/curl ${curlOptions} -k "${jss_url}/JSSResource/$1/id/0" -u "${jss_user}:${jss_pass}" -H "Content-Type: text/xml" -X POST -T "$2"
	}

FNtestXML () 
	{
	sleep .5
	FNgetID "$1" "$2"
	pid=$retreivedID

	if [ -z "$pid" ] ; then
		# echo ""$1" \"$2\" exists ($pid)" 
		# echo ""
	# else
		echo "ERROR $1 \"$2\" does not exist" 
		exit 1
	fi
	}

FNgetID () 
	{
		retreivedID=""
		retreivedXML=""
		name="$2"

		if [[ "$debug" == true ]] ; then
			logfile="$debugFolder$1-for$2-$(date).xml"
			# shellcheck disable=SC2086
			/usr/bin/curl ${curlOptions} -k "${jss_url}/JSSResource/$1" -u "${jss_user}:${jss_pass}" -H "Accept: application/xml" -o "$logfile"
			retreivedID=$( /usr/bin/xmllint --format "$logfile" | grep -B 1 "$name" | /usr/bin/awk -F'<id>|</id>' '{print $2}' | sed '/^\s*$/d' )
		elif [[ "$AylaMethod" == "y" ]]; then
			logfile="$AylaMethodFolder$1-for$2-$(date).xml"
			# shellcheck disable=SC2086
			/usr/bin/curl ${curlOptions} -k "${jss_url}/JSSResource/$1" -u "${jss_user}:${jss_pass}" -H "Accept: application/xml" -o "$logfile"
			retreivedID=$( /usr/bin/xmllint --format "$logfile" | grep -B 1 "$name" | /usr/bin/awk -F'<id>|</id>' '{print $2}' | sed '/^\s*$/d' )
		else
			# shellcheck disable=SC2086
			retreivedID=$( /usr/bin/curl ${curlOptions} -k "${jss_url}/JSSResource/$1" -u "${jss_user}:${jss_pass}" -H "Accept: application/xml" | /usr/bin/xmllint --format - | grep -B 1 "$name" | /usr/bin/awk -F'<id>|</id>' '{print $2}' | sed '/^\s*$/d' )
		fi
    }

FNgetXML () 
	{
		local resourceName="$1"
		local IDtoRead="$2"
		# shellcheck disable=SC2086
		retreivedXML=$( /usr/bin/curl ${curlOptions} -k "${jss_url}/JSSResource/$resourceName/id/$IDtoRead" -u "${jss_user}:${jss_pass}" -H "Accept: application/xml" )

    }

FNcreateCategory () {
	CategoryName="$1"
	newCategoryNameXML="<category><name>$CategoryName</name><priority>9</priority></category>"

	FNput_postXML categories "$CategoryName" "$newCategoryNameXML"
	FNgetID categories "$CategoryName"
}

fn_createAgentPolicy () {
	local scriptID=""
	local policyScript="$1"
	local policyTrigger="$2"
	local agentPolicyName
	agentPolicyName="${policyScript//.sh}"
	local agentPolicyName+=" - Trigger"
	# echo "$agentPolicyName"

	FNgetID scripts "$policyScript"
	local scriptID="$retreivedID"

	local agentPolicyXML="<policy>
  <general>
    <name>$agentPolicyName</name>
    <enabled>true</enabled>
    <trigger>EVENT</trigger>
    <trigger_other>$policyTrigger</trigger_other>
    <frequency>Ongoing</frequency>
    <category>
      <id>$UEXCategoryID</id>
    </category>
  </general>
  <scope>
    <all_computers>true</all_computers>
  </scope>
  <scripts>
    <size>1</size>
    <script>
      <id>$scriptID</id>
      <priority>After</priority>
    </script>
  </scripts>
</policy>"

FNput_postXML "policies" "$agentPolicyName" "$agentPolicyXML"

}

fn_createAPIPolicy () {
	local scriptID=""
	local policyScript="$1"
	local policyTrigger="$2"
	local APIPolicyName 
	APIPolicyName="${policyScript//.sh}"
	local APIPolicyName+=" - Disk Space - Trigger"
	local parameter4="$3"
	local parameter5="$4"
	# echo "$APIPolicyName"

	FNgetID scripts "$policyScript"
	local scriptID="$retreivedID"

	FNgetID "policies" "$APIPolicyName"
	if [ "$retreivedID" ] ; then
		FNgetXML "policies" "$retreivedID"

		parameter6=$( echo "$retreivedXML" | /usr/bin/xmllint --xpath "/policy/scripts/script/parameter6/text()" - )
		parameter7=$( echo "$retreivedXML" | /usr/bin/xmllint --xpath "/policy/scripts/script/parameter7/text()" - )
	fi

	local APIPolicyXML="<policy>
  <general>
    <name>$APIPolicyName</name>
    <enabled>true</enabled>
    <trigger>EVENT</trigger>
    <trigger_other>$policyTrigger</trigger_other>
    <frequency>Ongoing</frequency>
    <category>
      <id>$UEXCategoryID</id>
    </category>
  </general>
  <scope>
    <all_computers>true</all_computers>
  </scope>
  <scripts>
    <size>1</size>
    <script>
      <id>$scriptID</id>
      <priority>After</priority>
      <parameter4>$parameter4</parameter4>
      <parameter5>$parameter5</parameter5>
      <parameter6>$parameter6</parameter6>
      <parameter7>$parameter7</parameter7>
    </script>
  </scripts>
</policy>"

FNput_postXML "policies" "$APIPolicyName" "$APIPolicyXML"

}


fn_checkForSMTPServer () {
	# shellcheck disable=SC2086
	/usr/bin/curl ${curlOptions} -k "${jss_url}/JSSResource/smtpserver" -u "${jss_user}:${jss_pass}" -H "Accept: application/xml" | /usr/bin/xmllint --format - | grep -c "<enabled>true</enabled>"
}

fn_createTriggerPolicy () {
	local triggerPolicyName="$1"
	local policyTrigger2Run="$2"
	FNgetID "scripts" "00-UEX-Deploy-via-Trigger"
	local triggerScripID="$retreivedID"
	local triggerPolicyScopeXML="$3"

	local triggerPolicyXML="<policy>
  <general>
    <name>$triggerPolicyName</name>
    <enabled>true</enabled>
    <trigger_checkin>true</trigger_checkin>
    <trigger_logout>true</trigger_logout>
    <frequency>Ongoing</frequency>
    <category>
      <id>$UEXCategoryID</id>
    </category>
  </general>
  <scope>
	$triggerPolicyScopeXML
  </scope>
  <scripts>
    <size>1</size>
    <script>
      <id>$triggerScripID</id>
      <priority>After</priority>
      <parameter4>$policyTrigger2Run</parameter4>
    </script>
  </scripts>
</policy>"

FNput_postXML "policies" "$triggerPolicyName" "$triggerPolicyXML"

}


fn_createTriggerPolicy4Pkg () {
	local packagePolicyName="$1"
	local pkg2Install="$2"
	local customEventName="$3"
	FNgetID "packages" "$pkg2Install"
	local policypackageID="$retreivedID"
	local packagePolicyScopeXML="$4"

	local packagePolicyXML="<policy>
  <general>
    <name>$packagePolicyName</name>
    <enabled>true</enabled>
    <trigger>EVENT</trigger>
    <trigger_other>$customEventName</trigger_other>
    <frequency>Ongoing</frequency>
    <category>
      <id>$UEXCategoryID</id>
    </category>
  </general>
  <scope>
	$packagePolicyScopeXML
  </scope>
  <package_configuration>
    <packages>
      <size>1</size>
      <package>
        <id>$policypackageID</id>
        <action>Install</action>
      </package>
    </packages>
  </package_configuration>
</policy>"

FNput_postXML "policies" "$packagePolicyName" "$packagePolicyXML"
}

fn_createSmartGroup () {
	local smartGroupName="$1"
	local smartGroupCriteriaSize="$2"
	local smartGroupCriterionXML="$3"

	local SmartGroupXML="<computer_group>
	  <name>$smartGroupName</name>
	  <is_smart>true</is_smart>
	  <site>
	    <id>-1</id>
	    <name>None</name>
	  </site>
	  <criteria>
	    <size>$smartGroupCriteriaSize</size>
	    $smartGroupCriterionXML
	  </criteria>
	  </computer_group>"

	  FNput_postXML "computergroups" "$1" "$SmartGroupXML"
}


fn_updateCategory () {
	local resourceID="$1"
	local xmlStart="$2"
	local categoryName="$3"
	local JSSResourceName="$4"

	local categoryXML="<$xmlStart>
		<category>$categoryName</category>
		</$xmlStart>"

		
		FNputXML "$JSSResourceName" "$resourceID" "$categoryXML"
}

fn_setScriptParameters () {
	local scriptName="$1"
	local parameter4="$2"
	local parameter5="$3"
	local parameter6="$4"
	local parameter7="$5"
	local parameter8="$6"
	local parameter9="$7"
	local parameter10="$8"
	local parameter11="$9"

	local scriptParameterXML="<script>
	<parameters>
<parameter4>$parameter4</parameter4>
<parameter5>$parameter5</parameter5>
<parameter6>$parameter6</parameter6>
<parameter7>$parameter7</parameter7>
<parameter8>$parameter8</parameter8>
<parameter9>$parameter9</parameter9>
<parameter10>$parameter10</parameter10>
<parameter11>$parameter11</parameter11>
</parameters>
 </script>"


	FNput_postXML scripts "$scriptName" "$scriptParameterXML"
}


fn_CreateAppRestrictionPolicy () {


restrictedsoftwareXML="<restricted_software>
  <general>
    <name>$restrictedAppName</name>
    <process_name>$restrictedAppName</process_name>
    <match_exact_process_name>true</match_exact_process_name>
    <send_notification>true</send_notification>
    <kill_process>true</kill_process>
    <delete_executable>false</delete_executable>
    <display_message/>
    <site>
      <id>-1</id>
      <name>None</name>
    </site>
  </general>
  <scope>
    <all_computers>true</all_computers>
    <computers/>
    <computer_groups/>
    <buildings/>
    <departments/>
    <exclusions>
      <computers/>
      <computer_groups/>
      <buildings/>
      <departments/>
      <users/>
    </exclusions>
  </scope>
</restricted_software>"

	FNput_postXML restrictedsoftware "$restrictedAppName" "$restrictedsoftwareXML"


}

fn_create_staticGroup_for_Disk_Space () {
	StaticGroupXMLForDiskSpace="<computer_group>
  <name>$staticGroupName</name>
  <is_smart>false</is_smart>
  <site>
    <id>-1</id>
    <name>None</name>
  </site>
</computer_group>"

	FNput_postXML "computergroups" "$staticGroupName" "$StaticGroupXMLForDiskSpace"
}

fn_create_MonititoringSmartGroup_for_Disk_Space () {
	SmartGroupXMLForDiskSpace="<computer_group>
  <name>Monitoring - UEX - $staticGroupName</name>
  <is_smart>true</is_smart>
  <site>
    <id>-1</id>
    <name>None</name>
  </site>
  <criteria>
    <size>1</size>
    <criterion>
      <name>Computer Group</name>
      <priority>0</priority>
      <and_or>and</and_or>
      <search_type>member of</search_type>
      <value>$staticGroupName</value>
      <opening_paren>false</opening_paren>
      <closing_paren>false</closing_paren>
    </criterion>
  </criteria>
</computer_group>"

	FNput_postXML "computergroups" "Monitoring - UEX - $staticGroupName" "$SmartGroupXMLForDiskSpace"
}

fn_openMonitoringSmartGroup () {
	FNgetID "computergroups" "Monitoring - UEX - $staticGroupName"
	MonitoringGroupID="$retreivedID"
	sudo -u "$loggedInUser" -H open "$jss_url/smartComputerGroups.html?id=$MonitoringGroupID&o=u"
}
fn_openAPIPolicies () {
	FNgetID "policies" "00-API-Add-Current-Computer-to-Static-Group - Disk Space - Trigger"
	sudo -u "$loggedInUser" -H open "$jss_url/policies.html?id=$retreivedID&o=u"

	FNgetID "policies" "00-API-Remove-Current-Computer-from-Static-Group - Disk Space - Trigger"
	sudo -u "$loggedInUser" -H open "$jss_url/policies.html?id=$retreivedID&o=u"
}

##########################################################################################
# 								API MAGIC Starts Here									 #
##########################################################################################
# create category
	FNcreateCategory "$UEXCategoryName"
	UEXCategoryID="$retreivedID"


if [[ "$helpTicketsEnabledViaAppRestriction" = true ]] || [[ "$helpTicketsEnabledViaGeneralStaticGroup" = true ]] ;then
	if [[ $(fn_checkForSMTPServer) -eq 0 ]] ; then
		SMTPNotification="No SMTP server configured. 
Please check your Jamf Pro server or disbale helpTicketsEnabledViaAppRestriction or helpTicketsEnabledViaGeneralStaticGroup"
		fn_genericDialogCocoaDialogStyleError "$SMTPNotification" "$standardIcon" "1"
		
	fi
fi

if [[ "$helpTicketsEnabledViaAppRestriction" = true ]]; then
	#statements
	fn_CreateAppRestrictionPolicy
fi


if [[ "$helpTicketsEnabledViaGeneralStaticGroup" = true ]]; then
	#statements
	fn_create_staticGroup_for_Disk_Space
	fn_create_MonititoringSmartGroup_for_Disk_Space
	
	for apiScript in "${apiScripts[@]}" ; do
		fn_setScriptParameters "$apiScript" "Group Name" "JSS URL - No Trailing Slash" "JSS Username (encrypted)" "JSS Password (encrypted)"
	done

	fn_createAPIPolicy "00-API-Add-Current-Computer-to-Static-Group" "$UEXhelpticketTrigger" "$staticGroupName" "$jss_url"
	fn_createAPIPolicy "00-API-Remove-Current-Computer-from-Static-Group" "$ClearHelpTicketRequirementTrigger" "$staticGroupName" "$jss_url"

fi


# check for all copmonents and update their category 
	for script in "${scripts[@]}" ; do 
		FNgetID "scripts" "$script" 
		if [ -z "$retreivedID" ] ; then

			ScriptNotification="ERROR: Script "$script" not found on jamf server "$jss_url""
			fn_genericDialogCocoaDialogStyleError "$ScriptNotification" "$standardIcon" "1"

		else
			echo "updating category on \"$script\" to \"$UEXCategoryName\""
			fn_updateCategory "$retreivedID" "script" "$UEXCategoryName" "scripts"
		fi
	done

	for package in "${packages[@]}" ; do 
		FNgetID "packages" "$package" 
		if [ -z "$retreivedID" ] ; then

			PackageError="ERROR: Package $package not found on jamf server $jss_url"
			fn_genericDialogCocoaDialogStyleError "$PackageError" "$standardIcon" "1"

		else
			echo "updating category on \"$package\" to \"$UEXCategoryName\""
			fn_updateCategory "$retreivedID" "package" "$UEXCategoryName" "packages"
		fi
	done

# update scripts paramters
	for triggerscript in "${triggerscripts[@]}" ; do
		fn_setScriptParameters "$triggerscript" "Trigger names separated by semi-colon"
	done

	# "Vendor;AppName;Version;SpaceReq"
	# "Checks"
	# "Apps for Quick and Block"
	# "InstallDuration - Must be integer"
	# "MaxDefer;DiskTicketLimit"
	# "Packages separated by ;"
	# "Trigger Names separated by ;"
	# "Custom Message - optional"

	for UEXInteractionScript in "${UEXInteractionScripts[@]}" ; do
		fn_setScriptParameters "$UEXInteractionScript" "Vendor;AppName;Version;SpaceReq" "Checks" "Apps for Quick and Block" "InstallDuration - Must be integer" "MaxDefer;DiskTicketLimit" "Packages separated by ;" "Trigger Names separated by ;" "Custom Message - optional"
	done


# create agent policies
	fn_createAgentPolicy "00-uexblockagent-jss" "uexblockagent"
	fn_createAgentPolicy "00-uexlogoutagent-jss" "uexlogoutagent"
	fn_createAgentPolicy "00-uexrestartagent-jss" "uexrestartagent"
	fn_createAgentPolicy "00-uex_inventory_update_agent-jss" "uex_inventory_update_agent"
	fn_createAgentPolicy "00-uexdeferralservice-jss" "uexdeferralservice"
	fn_createAgentPolicy "00-PleaseWaitUpdater-jss" "PleaseWaitUpdater"


# Check for EA
	extAttrName="UEX - Deferral Detection"
	FNgetID computerextensionattributes "$extAttrName"
	if [ -z "$retreivedID" ] ;then
		EAError="ERROR: Exentsion Attribute $extAttrName not found on jamf server $jss_url"
		fn_genericDialogCocoaDialogStyleError "$EAError" "$standardIcon" "1"

	fi

# Create smart group
	smartGroupName="UEX - Active Deferrals"

	criterionXML="<criterion>
	      <name>$extAttrName</name>
	      <priority>0</priority>
	      <and_or>and</and_or>
	      <search_type>like</search_type>
	      <value>active</value>
	      <opening_paren>false</opening_paren>
	      <closing_paren>false</closing_paren>
	    </criterion>"

	fn_createSmartGroup "$smartGroupName" "1" "$criterionXML"
	SmargroupID="$retreivedID"

# create deferal policy
defferalPolicyScopeXML="<all_computers>false</all_computers>
    <computers/>
    <computer_groups>
      <computer_group>
        <id>$SmargroupID</id>
      </computer_group>
    </computer_groups>"

fn_createTriggerPolicy "00-uexdeferralservice-jss - Checkin and Logout" "uexdeferralservice" "$defferalPolicyScopeXML"

# create UEX resources policy
fn_createTriggerPolicy4Pkg "00-uexresources-jss - Trigger" "${packages[0]}" "uexresources" "<all_computers>true</all_computers>"

if [[ "$helpTicketsEnabledViaGeneralStaticGroup" = true ]]; then
	OpenNotification="Now Opening the Monitoring Smart Group
Make sure the Notification Setting is on
Also opening API scripts. Make sure to add the JSS User and Password"
	fn_genericDialogCocoaDialogStyleMessage "$OpenNotification" "$standardIcon"

	sleep 3
	fn_openMonitoringSmartGroup
	fn_openAPIPolicies

fi

fn_delete_JamfUEXGETfolder

fn_genericDialogCocoaDialogStyleMessage "The world is now your burrito!🌯" "$standardIcon"
echo "The world is now your burrito!"


##########################################################################################
exit 0
