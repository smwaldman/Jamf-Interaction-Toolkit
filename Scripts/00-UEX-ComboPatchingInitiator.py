#!/usr/bin/python
import subprocess, sys
import json, os, re, plistlib, argparse
import time, datetime
from src.local_installed_apps import installed_apps_version
from src.version_check import SemVer
import logging
#import src.cpe_logger.log as log

logname="/Library/UEX/UEX_Logs/uex_scoping.log"
#clean start log
#newsyslog -R 'begin script' /Library/UEX/UEX_Logs/uex_scoping.log
os.system('/usr/sbin/newsyslog -R "begin script" /Library/UEX/UEX_Logs/uex_scoping.log')
logging.basicConfig(level=logging.INFO, filename='/Library/UEX/UEX_Logs/uex_scoping.log', format='%(asctime)s - %(levelname)s - %(message)s')

__version__='0.17'
MaxDefer=""
HardDate=""
checks=""
patchNames=""
triggers=""
BlockApps=""
InstallationDuration=0
flag1=0
selfservice=0

initiate_patching_trigger = 'patchVersions'

parser = argparse.ArgumentParser()
parser.add_argument("-b", "--beta", help="beta",
                    action="store_true")
parser.add_argument('-v', '--version', action='version', version='%(prog)s ' + __version__)
args = parser.parse_args()


if args.beta:
   initiate_patching_trigger += "-beta"

logging.info('%s', initiate_patching_trigger)

jamf_return = subprocess.check_output(['/usr/local/bin/jamf', 'policy', '-event', initiate_patching_trigger])
extract_json = re.compile(r"(Script result:\s\n)(\{.*\})", re.S)
app_json = json.loads(re.search(extract_json, jamf_return).group(2))


HardDate = app_json['HardDate']
ScriptName = app_json['ScriptName']
MaxDefer = app_json['MaxDefer']


if app_json['AppleUpdates']:
    checks="suspackage;"
    
if app_json['AdobeUpdates']:
    checks+="adobecc;"

logging.info('HardDate: %s, ScriptName: %s, MaxDefer: %s, checks: %s', HardDate, ScriptName, MaxDefer, checks)

app_dict = {}
app_dict_version = {}

for app in app_json['apps_list']:
    app_dict[app['DisplayName']] = app


installed_app  = installed_apps_version(app_dict.keys())


for app, data in installed_app.items():

    version = data['version']
    path = data['path']
    installed_version = SemVer(version)


    if len(app_dict[app]['Details']) > 1:
        for i in range(len(app_dict[app]['Details'])):
            tmp_patch_version = SemVer(app_dict[app]['Details'][i]['Version'])
            installed_major_version = int(version.split('.')[0])
            if tmp_patch_version.major_check(installed_major_version):
                patch_version = SemVer(app_dict[app]['Details'][i]['Version'])
                pvassist = i
    else:
        patch_version = SemVer(app_dict[app]['Details'][0]['Version'])
        pvassist = 0


    if installed_version < patch_version:
        logging.info('%s needs patching, patching version: %s installed version: %s @ %s', app, patch_version, version, path)
        patchNames+=app_dict[app]['DisplayName'] + ';'
        checks+=app_dict[app]['checks'] + ';'
        BlockApps+=app_dict[app]['BlockApps'] + ';'
        InstallationDuration+=int(app_dict[app]['InstallationDuration'])
        triggers+=app_dict[app]['Details'][pvassist]['CustomTrigger'] + ';'
    else:
        logging.info('%s up to date, patch version: %s installed version: %s @ %s', app, patch_version, version, path)


# Check to see if Self Service script is running
if not subprocess.call(['pgrep', '00-UEX-Update-via-Self-Service'], stdout=subprocess.PIPE, stderr=subprocess.PIPE):
    logging.info('triggered from selfservice')
    selfservice=1


# Remove trailing ; from strings
checks = checks[:-1] if checks.endswith(';') else checks
patchNames = patchNames[:-1] if patchNames.endswith(';') else patchNames
triggers = triggers[:-1] if triggers.endswith(';') else triggers
BlockApps = BlockApps[:-1] if BlockApps.endswith(';') else BlockApps


# Plist creation
if (triggers or checks) :

    logging.info('Applicable triggers: %s', triggers)
    logging.info('Applicable checks: %s', checks)
    # UEX plsit creation
    UEXPathDeffer = "/Library/UEX/defer_jss"
    PlistPath= UEXPathDeffer + "/UEX;ClientPatching;1.0.plist"

    delayDate=int(time.mktime(datetime.datetime.now().timetuple()))
    delayDateFriendly=datetime.datetime.now()

    if not (os.path.exists(PlistPath)):
        if not os.path.exists(UEXPathDeffer):
            os.makedirs(UEXPathDeffer)
        pl = {
           "checks" : checks,
           "delayDate" : str(delayDate),
           "delayDateFriendly" : str(delayDateFriendly),
           "delayNumber" : "0",
           "folder" : "",
           "inactivityDelay" : "0",
           "loginscreeninstall" : "false",
           "BlockApps" : BlockApps,
           "policyTrigger" : "ComboPatch-Deployment",
           "patchTrigger" : triggers,
           "patchNames" : patchNames,
           "HardDate" : HardDate,
           "MaxDefer" : MaxDefer,
           "presentationDelayNumber" : "0",
           "installDuration" : InstallationDuration,
           "package": "UEX;ClientPatching;1.0",
           "ScriptName" : ScriptName
        }
        flag1=1
    else:
            # update existing plist
        pl = plistlib.readPlist(PlistPath)
        pl["checks"] = str(checks)
        pl["BlockApps"] = str(BlockApps)
        pl["patchTrigger"] = str(triggers)
        pl["patchNames"] = str(patchNames)
        pl["installDuration"] = str(InstallationDuration)
        pl["ScriptName"] = str(ScriptName)
        pl["HardDate"] = str(HardDate)

    # create or update plist
    with open(PlistPath, 'wb') as ua:
        plistlib.writePlist(pl, ua)

    logging.info('Plist Created successfully')
else:
    logging.info('no patches avaliable')
    AgentPlist="/Library/LaunchDaemons/com.patching.uex.plist"
    if (os.path.exists(AgentPlist)):
        subprocess.call(["launchctl remove com.patching.uex"], shell=True)
        time.sleep(2)
        os.remove(AgentPlist)
    exit(0)


if (triggers or checks) and not (os.path.exists(PlistPath)):
    logging.warn('failed to create plist')
    exit(1)
else:
    if flag1 and not selfservice :
        subprocess.call(["jamf policy -event UEXAgent &"], shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

#clean end and start for log
file_object = open('/Library/UEX/UEX_Logs/uex_scoping.log', 'a')
file_object.write('\n')
file_object.close()

exit(0)
