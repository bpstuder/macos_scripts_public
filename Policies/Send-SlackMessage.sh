#!/bin/zsh
###
# File: Send-SlackMessage.sh
# File Created: 2022-11-02 16:51:34
# Usage : Checks a Zero Touch enrollment status and then send a report on Slack
# Author: Benoit-Pierre STUDER
# -----
# HISTORY:
# 2022-11-03	Benoit-Pierre STUDER	Rework of policy check
###

########
### CONSTANTS
########

webhookURL="https://hooks.slack.com/services/XXX/XXX/XXX"
logoImage="https://resources.jamf.com/images/icons/jamf-og-image.jpg"
jamfProURL=$(/usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf jss_url)
jamfProURL=${jamfProURL%%/}

currentUser=$(stat -f%Su /dev/console)

stepFailed=""
jamfCategory="_Enrollment-Policies"

danger=0
statusFile="/Library/Managed Preferences/$currentUser/com.bpstuder.identity.plist"
hostSerialNumber=$(system_profiler SPHardwareDataType | grep "Serial Number" | awk -F ": " '{print $2}')

# API Account that has read access to Jamf Pro Server Objects > Computers

jamfProUser="$4"
jamfProPassEnc="$5"
jamfProSalt="$6"
jamfProPassPhrase="$7"
enrollmentVersion="${8}"

########
## FUNCTIONS
########

function CollectJamfData () {
    echo "Collecting Jamf Data"
    computerQuery=$(/usr/bin/curl "${jamfProURL}/JSSResource/computers/id/$computerID" \
        --request GET \
        --silent \
        --insecure \
        --header "Authorization: Bearer $token" \
        --header "Content-type: application/xml" \
        -w "httpcode:%{http_code}")

    httpCode=$(echo $computerQuery | tr -d '\n' | sed -e 's/.*httpcode://')
    computerResult=$(echo $computerQuery | sed -e 's/httpcode\:.*//g')

    if [[ ${httpCode} == 200 ]]; then
        echo ">> Done"
    else
        echo "[ERROR] Unable to get Jamf data. Curl code received : ${httpCode}"
    fi

    # return $httpBody
}

function CollectHardwareData () {
    echo "Collecting Hardware data"
    computerName=$(scutil --get ComputerName)
    computerModel=$(echo ${computerResult} | xmllint --xpath "//computer/hardware/model/text()" -)
}

function CheckFileVault () {
    echo "Checking FileVault status"
    primaryUser=$(echo ${computerResult} | xmllint --xpath "//computer/location/username/text()" -)
    primaryUser=$(echo $primaryUser | awk -F'@' '{print $1}')

    echo "Primary User : ${primaryUser}"
    if [[ -z "$primaryUser" ]]; then
        primaryUser="Unassigned"
    fi

    if [[ "$primaryUser" != "Unassigned" ]]; then
        primary_user_fv_enabled=$(fdesetup list | grep "$primaryUser")
        if [[ ! -z "$primary_user_fv_enabled" ]]; then
            fvEnabled="Yes"
        else
            fvEnabled="no"
            stepFailed="$stepFailed
- Failure on Filevault disabled"
            danger=1
        fi
    fi
}

########
## MAIN CODE
########
#### Decrypt variable ####

jamfProPass=$(echo "$jamfProPassEnc" | /usr/bin/openssl enc -aes256 -md md5 -d -a -A -S "$jamfProSalt" -k "$jamfProPassPhrase")

echo "Connecting to $jamfProURL"
# created base64-encoded credentials
encodedCredentials=$(printf "${jamfProUser}:${jamfProPass}" | /usr/bin/iconv -t ISO-8859-1 | /usr/bin/base64 -i -)
# generate an auth token
authToken=$(/usr/bin/curl "$jamfProURL/api/auth/tokens" \
    --silent \
    --request POST \
    --header "Authorization: Basic $encodedCredentials" \
    --header "Content-Length: 0" \
    -w "\n%{http_code}")

httpCode=$(tail -n1 <<<"${authToken}")
httpBody=$(sed '$ d' <<<"${authToken}")

echo "Command HTTP result : ${httpCode}"
# echo "Response : ${httpBody}"

if [[ ${httpCode} == 200 ]]; then
    echo "Token creation done"
else
    echo "[ERROR] Unable to create token. Curl code received : ${httpCode}"
    exit 1
fi

# parse authToken for token, omit expiration
token=$(awk -F \" '{ print $4 }' <<<"$authToken" | xargs)

#######

echo "Collecting policies to check"
categoryPoliciesResult=$(/usr/bin/curl "${jamfProURL}/JSSResource/policies/category/${jamfCategory}" \
  --silent \
  --insecure \
  --request GET \
  --header "Authorization: Bearer $token" \
  --header "Accept: application/xml" \
  -w "httpcode:%{http_code}")

httpCode=$(echo $categoryPoliciesResult | tr -d '\n' | sed -e 's/.*httpcode://')
httpBody=$(echo $categoryPoliciesResult | sed -e 's/httpcode\:.*//g')

if [[ ${httpCode} == 200 ]]; then
  echo "Policies for category $jamfCategory retrieved"
else
  echo "[ERROR] Unable to collect policies for category $jamfCategory. Curl code received : ${httpCode}"
  exit 1
fi

policiesCount=$(echo $httpBody | xmllint --xpath '//policies/size/text()' -)
echo "Found $policiesCount policies to proceed"
declare -A policiesToRun

for ((i = 1; i <= $policiesCount; i++)); do
  policyID="$(echo $httpBody | xmllint --xpath '//policies/policy['"$i"']/id/text()' -)"
  policyName="$(echo $httpBody | xmllint --xpath '//policies/policy['"$i"']/name/text()' -)"
  policiesToRun[$policyName]=$policyID
done

echo "${policiesCount} policies to check"

echo "Collecting policies on Computer ${hostSerialNumber}"
policiesOnComputer=$(/usr/bin/curl "${jamfProURL}/JSSResource/computerhistory/name/${hostSerialNumber}/subset/policy_logs" \
    --silent \
    --insecure \
    --request GET \
    --header "Authorization: Bearer $token" \
    --header "Accept: application/xml" \
    -w "httpcode:%{http_code}")
# httpCode=$(tail -n1 <<<"${policiesOnComputer}")
# httpBody=$(sed '$ d' <<<"${policiesOnComputer}")
httpCode=$(echo $policiesOnComputer | tr -d '\n' | sed -e 's/.*httpcode://')
httpBody=$(echo $policiesOnComputer | sed -e 's/httpcode\:.*//g')

if [[ ${httpCode} == 200 ]]; then
    echo "Policies logs retrieved"

    declare -A policiesOnComputerToCheck

    i=1
    policyID="$(echo $httpBody | xmllint --xpath '//computer_history/policy_logs/policy_log['"$i"']/policy_id/text()' -)"
    until [[ -z $policyID ]]; do 
    # for ((i = 1; i <= 14; i++)); do
        policyID="$(echo $httpBody | xmllint --xpath '//computer_history/policy_logs/policy_log['"$i"']/policy_id/text()' -)"
        policyName="$(echo $httpBody | xmllint --xpath '//computer_history/policy_logs/policy_log['"$i"']/status/text()' -)"

        # policiesOnComputerToCheck[$policyName]=$policyID
        if [[ ! -z $policyID ]]; then
            policiesOnComputerToCheck[$policyID]=$policyName
            ((i++))
        fi
    done

    echo "Checking policies status"
    for policyID in "${(kn)policiesOnComputerToCheck[@]}"; do
        policyStatus="${policiesOnComputerToCheck[$policyID]}"

        for policyName in "${(kn)policiesToRun[@]}"; do
            if [[ ${policiesToRun[$policyName]} -eq ${policyID} ]]; then
                echo "Policy $policyName Status : ${policyStatus}"
                if [[ "${policyStatus}" == "Failed" ]]; then
                    echo "Failure on $policyName"
                    stepFailed="$stepFailed
- Failure on $policyName"
                    danger=1
                fi
            fi
        done
    done
else
    echo "[ERROR] Unable to collect policies logs. Curl code received : ${httpCode}"
    stepFailed="$stepFailed
- Failure on collecting policies logs"
    danger=1
fi

try=0
totalTries=30
echo "Checking CP-Identity-Card presence"
until [[ -f ${statusFile} ]] || [[ "$try" -ge "$totalTries" ]]; do
    ((try++))
    echo "(Try : $try/$totalTries) Waiting for CP to apply..."
    sleep 10
    if [[ $try == $totalTries ]]; then
        echo "[ERROR] CP-Identity-Card is not present."
        stepFailed="$stepFailed
- Failure on CP-Identity-Card not present"
        danger=1
    fi
done

computerID=$(defaults read "${statusFile}" "jssid")

echo "Collecting Enrollment data"
osVersion=$(/usr/bin/sw_vers -productVersion)
enrollmentComplete=$(defaults read "${statusFile}" "status")
if [[ $enrollmentComplete == "false" ]]; then
    danger=1
fi

CollectJamfData

CollectHardwareData

CheckFileVault

siteNameLocal=$(defaults read "${statusFile}" "siteName")
siteNameJamf=$(echo ${computerResult} | xmllint --xpath "//computer/general/site/name/text()" -)
echo "Checking Site"
echo "Current site local : $siteNameLocal. Current site Jamf : $siteNameJamf"
try=0

until [[ "${siteNameLocal}" == "_Production" ]] || [[ "${siteNameJamf}" == "_Production" ]] || [[ "$try" -ge "20" ]]; do
    ((try++))
    sleep 5
    CollectJamfData
    siteNameLocal=$(defaults read "${statusFile}" "siteName")
    siteNameJamf=$(echo ${computerResult} | xmllint --xpath "//computer/general/site/name/text()" -)
    echo "(Try : $try/20) Current site local : $siteNameLocal. Current site Jamf : $siteNameJamf"
done

if [[ "$siteNameLocal" != "_Production" ]] && [[ "$siteNameJamf" != "_Production" ]]; then
    stepFailed="$stepFailed
- Failure on Wrong Site"
    danger=2
fi

# echo "Collecting WiFi informations"
# wifiSSID=$(networksetup -getairportnetwork en0 | awk -F " " '{print $4}')

#1 = Warning
#2 = Critical

if [[ $danger -eq 1 ]]; then
    title=":warning: Mac Enrollment Warning"
    color="warning"
elif [[ $danger -eq 2 ]]; then
    title=":bangbang: Mac Enrollment Failed"
    color="danger"
else
    title=":white_check_mark: Mac Enrollment Completed"
    color="good"
    stepFailed="N/A"
fi

reportText="*JAMF Site:* $siteNameJamf
*Enrollment version:* $enrollmentVersion
*Computer name:* $computerName
*Step failure:* $stepFailed
*Mac model:* $computerModel
*macOS version:* $osVersion
*Primary User:* $primaryUser
*FileVault Enabled:* $fvEnabled"
#*WiFi*: Connected to $wifiSSID"

escapedText=$(echo $reportText | sed 's/"/\"/g' | sed "s/'/\'/g")
slackJSON="{\"text\": \"$title\",\"attachments\":[{\"thumb_url\": \"$logoImage\",\"color\":\"$color\" , \"text\": \"$escapedText\"}]}"

echo "Sending Slack message"
slackQuery=$(/usr/bin/curl "$webhookURL" \
    --silent \
    -k \
    -d payload="$slackJSON" \
    -w "httpcode:%{http_code}")
# httpCode=$(tail -n1 <<<"${slackQuery}")
httpCode=$(echo $slackQuery | tr -d '\n' | sed -e 's/.*httpcode://')
httpBody=$(echo $slackQuery | sed -e 's/httpcode\:.*//g')

if [[ ${httpCode} == 200 ]]; then
    echo ">> Done"
else
    echo "[ERROR] Unable to send Slack message. Curl code received : ${httpCode}"
fi

# expire the auth token
echo "Expiring Token"
query=$(/usr/bin/curl "$jamfProURL/api/auth/invalidateToken" \
    --silent \
    --request POST \
    --header "Authorization: Bearer $token" \
    --header "Content-Length: 0" \
    -w "\n%{http_code}")
httpCode=$(tail -n1 <<<"${query}")

if [[ ${httpCode} == 204 ]]; then
    # echo "Command HTTP result : ${httpCode}"
    echo ">> Done"
else
    echo "[ERROR] Unable to expire token. Curl code received : ${httpCode}"
fi

exit 0
