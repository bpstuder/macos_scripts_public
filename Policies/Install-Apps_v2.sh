#!/bin/sh
###
# File: Install-Apps_v2.sh
# File Created: 2020-12-14 14:13:27
# Usage :
# Author: Benoit-Pierre Studer
# -----
# HISTORY:
###

function cleanup () {
    echo "Cleaning up"
    rm -rf "${TEMP_PATH}"
    echo ">> Done"
}

## Parameters definition

APP_FORMAT="$4"
APP_NAME="$5"
APP_PATH="$6"
APP_LINK="$7"

## Variables

TEMP_PATH="/tmp/apps"

## Preparation

if [[ -d "${TEMP_PATH}" ]]; then
    echo "Removing ${TEMP_PATH}"
    rm -rf ${TEMP_PATH}
fi
echo "Creating ${TEMP_PATH}"
mkdir ${TEMP_PATH}
echo "Moving to ${TEMP_PATH}"
cd ${TEMP_PATH}

## Enforcing Path
APP_FULL_PATH="/Applications/${APP_PATH}"
echo "App full path : ${APP_FULL_PATH}"

## Checking app presence
echo "Checking if ${APP_NAME} is present"
if [[ ! -d "${APP_FULL_PATH}" ]]; then
    echo "App is not installed"

else
    echo "${APP_NAME} is installed. Removing it."

    echo "Checking if ${APP_NAME} is running"
    if /usr/bin/pgrep "${APP_NAME}"; then
        # If yes, kill the process
        # if [[ $? = 0 ]]; then
        echo "Killing ${APP_NAME}"
        /usr/bin/pkill "${APP_NAME}"
    fi
    echo "Deleting ${APP_FULL_PATH}"
    rm -rf "${APP_FULL_PATH}"
    if [[ $? == 0 ]]; then
        echo "${APP_NAME} has been successfully removed"
    else
        echo "[ERROR] Unable to remove ${APP_NAME}. Exiting"
        exit 1
    fi
fi
## Downloading app
echo "Downloading ${APP_NAME}"
curl -s -L -o "${APP_NAME}.${APP_FORMAT}" ${APP_LINK}
CURL_RESULT=$?
if [[ "${CURL_RESULT}" != 0 ]]; then
    echo "[ERROR] Curl command failed with: ${CURL_RESULT}"
    echo "[ERROR] App not downloaded. Exiting."
    exit 1
else
    echo "Download OK"
    echo "Installing ${APP_NAME}"

    case ${APP_FORMAT} in
    dmg)
        echo "Mounting ${APP_NAME}.dmg"
        hdiutil mount -nobrowse "${APP_NAME}.dmg" -mountpoint "/Volumes/${APP_NAME}" >/dev/null
        if [[ $? == 0 ]]; then
            echo "Copying files"
            ditto "/Volumes/${APP_NAME}/${APP_PATH}" "${APP_FULL_PATH}"
            if [[ $? == 0 ]]; then
                echo ">> Done"
                echo "Unmounting ${APP_NAME}.dmg"
                hdiutil unmount "/Volumes/${APP_NAME}" >/dev/null
                echo ">> Done"
            else
                echo "[ERROR] Unable to copy files"
                cleanup
                exit 1
            fi
        else
            echo "[ERROR] Unable to mount ${APP_NAME}.dmg"
            cleanup
            exit 1
        fi
        echo "App has been installed successfully"
        ;;
    zip)
        #Perform operations quietly.  The more q (as in -qq) the quieter.
        echo "Unzipping ${APP_NAME}.zip"
        unzip -qq "${APP_NAME}.zip"
        if [[ $? == 0 ]]; then
            echo "Copying files"
            ditto "${APP_PATH}" "${APP_FULL_PATH}"
            if [[ $? == 0 ]]; then
                echo ">> Done"
            else
                echo "[ERROR] Unable to copy files"
                cleanup
                exit 1
            fi
        else
            echo "[ERROR] Unable to unzip ${APP_NAME}.zip"
            cleanup
            exit 1
        fi
        echo "App has been installed successfully"
        ;;
    pkg)
        echo "Installing ${APP_NAME}.pkg"
        /usr/sbin/installer -pkg "${APP_NAME}.pkg" -target /
        if [[ $? == 0 ]]; then
            echo ">> Done"
        else
            echo "[ERROR] Unable to install app"
            cleanup
            exit 1
        fi
        echo "App has been installed successfully"
        ;;
    *)
        echo "[ERROR] Unrecognized format : ${APP_FORMAT}"
        exit 1
        ;;
    esac
fi

cleanup
# "/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper" -windowType utility -title "Installation done" -description "${APP_NAME} has been installed successfully" -icon "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertNoteIcon.icns" -button1 OK
exit 0
