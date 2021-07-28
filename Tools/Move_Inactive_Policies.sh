#!/bin/sh
###
# File: Move_Inactive_Policies.sh
# File Created: 2021-07-27 10:47:10
# Usage : Move the non active policies into a specific category
# Author: Benoit-Pierre Studer
# -----
# HISTORY:
###

URL_JAMF=""
#### Decrypt variable ####

SALT_STRING="" 
CRYPT_STRING=""
PASS_PHRASE_STRING="" # Passphrase for decrypt
DECRYPT_STRING=$(echo "${CRYPT_STRING}" | /usr/bin/openssl enc -aes256 -d -a -A -S "${SALT_STRING}" -k "${PASS_PHRASE_STRING}")

TARGET_CATEGORY_ID="42" #Jamf
TARGET_CATEGORY_NAME="Z_Archives" #Jamf

PAYLOAD="<?xml version='1.0' encoding='UTF-8'?>
<policy>
        <general>
                <category>
                        <id>${TARGET_CATEGORY_ID}</id>
                        <name>${TARGET_CATEGORY_NAME}</name>
                </category>
	</general>
</policy>"

echo $PAYLOAD

echo "Getting policies"

POLICIES=$(curl --location -H "Accept: text/xml" -sfkN -H "Authorization: Basic ${DECRYPT_STRING}" "${URL_JAMF}/JSSResource/policies")

POLICIES_COUNT=$(echo $POLICIES | xmllint --xpath '//policies/size/text()' -)

echo "Found $POLICIES_COUNT policies"
count=0
for ((i=1; i<=POLICIES_COUNT; i++)); do
        POLICY_ID=$(echo $POLICIES | xmllint --xpath "string(//policies/policy[$i]/id/text())" -)
        POLICY_NAME=$(echo $POLICIES | xmllint --xpath "string(//policies/policy[$i]/name/text())" -)
        echo "Checking ${POLICY_ID} > ${POLICY_NAME}"
        POLICY=$(curl --location \
                -H "Accept: text/xml" \
                -sfkN \
                -H "Authorization: Basic ${DECRYPT_STRING}" \
                "${URL_JAMF}/JSSResource/policies/id/${POLICY_ID}")
        IS_ENABLED=$(echo $POLICY | xmllint --xpath "string(//policy/general/enabled/text())" -)
        echo "Policy is enabled : $IS_ENABLED"
        
        if [[ $IS_ENABLED == "false" ]]; then
                echo "Moving policy to ${TARGET_CATEGORY_NAME}"
                RESULT=$(curl --location \
                        --request PUT "${URL_JAMF}/JSSResource/policies/id/${POLICY_ID}" \
                        --header 'Accept: application/xml' \
                        --header 'Content-Type: text/plain' \
                        --header "Authorization: Basic ${DECRYPT_STRING}" \
                        --data-raw "${PAYLOAD}" \
                        -w "\n%{http_code}" -skfN)

                HTTP_CODE=$(tail -n1 <<< "${RESULT}")
                HTTP_BODY=$(sed '$ d' <<< "${RESULT}") 

                echo "Command HTTP result : ${HTTP_CODE}"
                echo "Response : ${HTTP_BODY}"
                ((count++))
        fi
done 
echo "Moved $count policies to $TARGET_CATEGORY_NAME"