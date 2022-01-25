#!/bin/zsh
###
# File: Get-UnusedScripts.sh
# File Created: 2022-01-24 14:58:32
# Usage : Used to extract unused scripts of a Jamf Pro server
# Author: Benoit-Pierre STUDER
# -----
# HISTORY:
# 2022-01-24	Benoit-Pierre STUDER	Creation of the script
###

###########
# Variables
###########

LOG="./Get-UnusedScripts.log"
# server connection information
URL=$(/usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf jss_url)
URL=${URL%%/}
JAMF_USER="${1}"
JAMF_PASSWORD="${2}"

###########
# Fonctions
###########


function LogVerbose () {
    case ${1} in
    ok)
        echo -e "\U2705 - ${2}" | tee -a "${LOG}"
        ;;
    warning)
        echo -e "\U26A0 - ${2}" | tee -a "${LOG}"
        ;;
    error)
        echo -e "\U274C - ${2}" | tee -a "${LOG}"
        ;;
    info)
        echo -e "\U2139 - ${2}" | tee -a "${LOG}"
        ;;
    *)
        echo -e "\U2753 - ${2}" | tee -a "${LOG}"
        ;;
    esac
}

###########
# Main code
###########

LogVerbose "info" "Connecting to $URL"
# created base64-encoded credentials
encodedCredentials=$( printf "${JAMF_USER}:${JAMF_PASSWORD}" | /usr/bin/iconv -t ISO-8859-1 | /usr/bin/base64 -i - )
# generate an auth token
authToken=$( /usr/bin/curl "$URL/api/auth/tokens" \
--silent \
--request POST \
--header "Authorization: Basic $encodedCredentials" \
--header "Content-Length: 0" \
-w "\n%{http_code}")

httpCode=$(tail -n1 <<< "${authToken}")
httpBody=$(sed '$ d' <<< "${authToken}") 

echo "Command HTTP result : ${httpCode}"
# echo "Response : ${httpBody}"

if [[ ${httpCode} == 200 ]]; then 
    LogVerbose "ok" "Token creation done"
else
    LogVerbose "error" "Unable to create token. Curl code received : ${httpCode}"
fi

# parse authToken for token, omit expiration
token=$( awk -F \" '{ print $4 }' <<< "$authToken" | xargs )

policiesQuery=$(curl "${URL}/JSSResource/policies" \
-sfkN \
--location \
-H "Accept: text/xml" \
-H "Authorization: Bearer ${token}" \
-w "\n%{http_code}")

policiesCode=$(tail -n1 <<< "${policiesQuery}")
policiesBody=$(sed '$ d' <<< "${policiesQuery}")
# echo $httpBody

policiesCount=$(echo $policiesBody | xmllint --xpath '//policies/size/text()' -)

LogVerbose "info" "Found $policiesCount policies"
scriptsUsed=()
for ((i=1; i<=policiesCount; i++)); do
        policyID=$(echo $policiesBody | xmllint --xpath "string(//policies/policy[$i]/id/text())" -)
        policyName=$(echo $policiesBody | xmllint --xpath "string(//policies/policy[$i]/name/text())" -)
        LogVerbose "info" "Checking ${policyID} > ${policyName}"
        policyDetails=$(curl --location \
                -H "Accept: text/xml" \
                -sfkN \
                -H "Authorization: Bearer ${token}" \
                "${URL}/JSSResource/policies/id/${policyID}")
        scriptCount=$(echo $policyDetails | xmllint --xpath "string(//policy/scripts/size/text())" -)
        LogVerbose "info" "Script count : $scriptCount"
        if [[ $scriptCount != 0 ]]; then
            scriptID=$(echo $policyDetails | xmllint --xpath "string(//policy/scripts/script/id/text())" -)
            scriptName=$(echo $policyDetails | xmllint --xpath "string(//policy/scripts/script/name/text())" -)
            # LogVerbose "info" "Script ID : $scriptID"
            LogVerbose "info" "Script Name : $scriptName"
            scriptsUsed+=$scriptID
        fi
done

LogVerbose "info" "Extracting used scripts in policies"
scriptsUsedIDs=($(echo "${scriptsUsed[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
LogVerbose "ok" "Done"

scriptQuery=$(curl "${URL}/JSSResource/scripts" \
-sfkN \
--location \
-H "Accept: text/xml" \
-H "Authorization: Bearer ${token}" \
-w "\n%{http_code}")

scriptCode=$(tail -n1 <<< "${scriptQuery}")
scriptBody=$(sed '$ d' <<< "${scriptQuery}")

scriptCount=$(echo $scriptBody | xmllint --xpath '//scripts/size/text()' -)

LogVerbose "info" "Found $scriptCount scripts"

declare -A scriptsExisting
for ((i=1; i<=scriptCount; i++)); do
        scriptID=$(echo $scriptBody | xmllint --xpath "string(//scripts/script[$i]/id/text())" -)
        scriptName=$(echo $scriptBody | xmllint --xpath "string(//scripts/script[$i]/name/text())" -)
        LogVerbose "info" "Checking script ${scriptID} > ${scriptName}"

        scriptsExisting[$scriptID]=$scriptName
done

LogVerbose "info" "Extracting unused scripts"
scriptsExistingIDs=($(echo "${(k)scriptsExisting[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
unusedScripts=($(echo ${scriptsExistingIDs[@]} ${scriptsUsedIDs[@]} | tr ' ' '\n' | sort | uniq -u))

for i in "${unusedScripts[@]}"; do
    LogVerbose "info" "$i -> $scriptsExisting[$i]"
done
LogVerbose "ok" "Done"

# expire the auth token
LogVerbose "info" "Expiring Token"
result=$(/usr/bin/curl "$URL/api/auth/invalidateToken" \
--silent \
--request POST \
--header "Authorization: Bearer $token" \
--header "Content-Length: 0" \
-w "\n%{http_code}")
httpCode=$(tail -n1 <<< "${result}")

if [[ ${httpCode} == 204 ]]; then 
    echo "Command HTTP result : ${httpCode}"
    LogVerbose "info" "Done"
else
    LogVerbose "error" "Unable to expire token. Curl code received : ${httpCode}"
fi