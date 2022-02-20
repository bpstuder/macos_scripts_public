#!/bin/sh
###
# File: Move_Inactive_policies.sh
# File Created: 2021-07-27 10:47:10
# Usage : Move the non active policies into a specific category
# Author: Benoit-Pierre Studer
# -----
# HISTORY:
###

jamfProURL=$(/usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf jss_url)
#### Decrypt variable ####

# SALT_STRING="" 
# CRYPT_STRING=""
# PASS_PHRASE_STRING="" # Passphrase for decrypt
# DECRYPT_STRING=$(echo "${CRYPT_STRING}" | /usr/bin/openssl enc -aes256 -d -a -A -S "${SALT_STRING}" -k "${PASS_PHRASE_STRING}")

read -p 'Username: ' username
read -sp 'Password: ' password
# created base64-encoded credentials
encodedCredentials=$( printf "$username:$password" | /usr/bin/iconv -t ISO-8859-1 | /usr/bin/base64 -i - )

# generate an auth token
authToken=$( /usr/bin/curl "$jamfProURL/api/auth/tokens" \
                --silent \
                --request POST \
                --header "Authorization: Basic $encodedCredentials" )

# parse authToken for token, omit expiration
token=$( /usr/bin/awk -F \" '{ print $4 }' <<< "$authToken" | /usr/bin/xargs )

targetCategoryID="19" #Jamf
targetCategoryName="Z_Archives" #Jamf
echo
payload="<?xml version='1.0' encoding='UTF-8'?>
<policy>
        <general>
                <category>
                        <id>${targetCategoryID}</id>
                        <name>${targetCategoryName}</name>
                </category>
	</general>
</policy>"

# echo $payload

echo "Getting policies"

policies=$(curl "${jamfProURL}/JSSResource/policies" \
                --location \
                --header "Accept: text/xml" \
                --header "Authorization: Bearer ${token}" \
                -sfkN )

policiesCount=$(echo $policies | xmllint --xpath '//policies/size/text()' -)

echo "Found $policiesCount policies"
count=0
for ((i=1; i<=policiesCount; i++)); do
        policyID=$(echo $policies | xmllint --xpath "string(//policies/policy[$i]/id/text())" -)
        policyName=$(echo $policies | xmllint --xpath "string(//policies/policy[$i]/name/text())" -)
        echo "Checking ${policyID} > ${policyName}"
        policy=$(curl "${jamfProURL}/JSSResource/policies/id/${policyID}" \
                --location \
                --header "Accept: text/xml" \
                --header "Authorization: Bearer ${token}" \
                -sfkN )
        isEnabled=$(echo $policy | xmllint --xpath "string(//policy/general/enabled/text())" -)
        echo "Policy is enabled : $isEnabled"
        
        if [[ $isEnabled == "false" ]]; then
                echo "Moving policy to ${targetCategoryName}"
                moveResult=$(curl "${jamfProURL}/JSSResource/policies/id/${policyID}" \
                        --location \
                        --request PUT  \
                        --header 'Accept: application/xml' \
                        --header 'Content-Type: text/plain' \
                        --header "Authorization: Bearer ${token}" \
                        --data-raw "${payload}" \
                        -w "\n%{http_code}" -skfN)

                HTTP_CODE=$(tail -n1 <<< "${moveResult}")
                HTTP_BODY=$(sed '$ d' <<< "${moveResult}") 

                echo "Command HTTP result : ${HTTP_CODE}"
                echo "Response : ${HTTP_BODY}"
                ((count++))
        fi
done 
echo "Moved $count policies to $targetCategoryName"

#invalidate the Token
authToken=$(/usr/bin/curl "${jamfProURL}/api/v1/auth/invalidate-token" \
                --silent \
                --header "Authorization: Bearer ${token}" \
                --request POST)
token=""