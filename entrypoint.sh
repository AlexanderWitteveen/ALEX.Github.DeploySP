#!/bin/bash -l

path=$(pwd)

source /sharepoint.sh

echo "Get OAUTH Token"
TOKEN=$(PSGetToken "$INPUT_TENANT_ID" "$INPUT_CLIENT_ID" "$INPUT_CLIENT_SECRET")

echo "Get Site ID"
SITE_ID=$(PSGetSiteID "$TOKEN" "$INPUT_HOST" "$INPUT_SITE")

echo "Get Drive ID"
DRIVE_ID=$(PSGetDriveID "$TOKEN" "$SITE_ID" "$INPUT_DRIVE")

echo "Get Folder ID"
FOLDER_ID=$(PSGetDriveItemID "$TOKEN" "$DRIVE_ID" "$INPUT_FOLDER")

echo "Upload file"
TEST_FILE_ID=$(PSUploadFile "$TOKEN" "$DRIVE_ID" "$FOLDER_ID" "$INPUT_FILE_TARGET" "$INPUT_FILE_SOURCE")

echo $TOKEN
echo $SITE_ID
echo $DRIVE_ID
echo $FOLDER_ID
echo $TEST_FILE_ID

exit 0

