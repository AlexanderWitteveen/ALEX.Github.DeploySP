PSMAXBYTES=327680

function PSGetToken()
{
    local AZURE_TENANT_ID=$1
    local AZURE_CLIENT_ID=$2
    local AZURE_CLIENT_SECRET=$3

    local URL="https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/v2.0/token"
    local RESPONSE=$(echo -n '[' && curl -X POST --data-urlencode "grant_type=client_credentials" --data-urlencode "client_id=$AZURE_CLIENT_ID" --data-urlencode "client_secret=$AZURE_CLIENT_SECRET" --data-urlencode "scope=https://graph.microsoft.com/.default" -w ',%{json}]' -s "$URL")
    local TOKEN_TYPE=$(echo $RESPONSE | jq -r '.[0].token_type')
    local TOKEN=$(echo $RESPONSE | jq -r '.[0].access_token')
    local AUTHENTICATION_HEADER="Authorization: $TOKEN_TYPE $TOKEN"
    echo $AUTHENTICATION_HEADER
}

function PSGetSiteID()
{
    local AUTHENTICATION_HEADER=$1
    local SHAREPOINT_HOST=$2
    local SHAREPOINT_SITE=$3

    local URL="https://graph.microsoft.com/v1.0/sites/$SHAREPOINT_HOST:$SHAREPOINT_SITE"
    local RESPONSE=$(echo -n '[' && curl -X GET -H "$AUTHENTICATION_HEADER" -w ',%{json}]' -s "$URL")
    local SITE_ID=$(echo $RESPONSE | jq -r '.[0].id')
    echo $SITE_ID
}

function PSGetDriveID()
{
    local AUTHENTICATION_HEADER=$1
    local SITE_ID=$2
    local SHAREPOINT_DRIVE=$3

    local URL="https://graph.microsoft.com/v1.0/sites/$SITE_ID/drives"
    local RESPONSE=$(echo -n '[' && curl -X GET -H "$AUTHENTICATION_HEADER" -w ',%{json}]' -s "$URL")
    local DRIVE_ID=$(echo $RESPONSE | jq -r '.[0].value[] | select(.name == "'"$SHAREPOINT_DRIVE"'") | .id')
    echo $DRIVE_ID
}

function PSGetDriveItemID()
{
    local AUTHENTICATION_HEADER=$1
    local DRIVE_ID=$2
    local SHAREPOINT_PATH=$3

    local URL="https://graph.microsoft.com/v1.0/drives/$DRIVE_ID/root:/$SHAREPOINT_PATH"
    local RESPONSE=$(echo -n '[' && curl -X GET -H "$AUTHENTICATION_HEADER" -w ',%{json}]' -s "$URL")
    local ITEM_ID=$(echo $RESPONSE | jq -r '.[0].id')
    echo $ITEM_ID
}

function PSGetDriveItemMeta()
{
    local AUTHENTICATION_HEADER=$1
    local DRIVE_ID=$2
    local ITEM_ID=$3

    local URL="https://graph.microsoft.com/v1.0/drives/$DRIVE_ID/items/$ITEM_ID"
    local RESPONSE=$(echo -n '[' && curl -X GET -H "$AUTHENTICATION_HEADER" -w ',%{json}]' -s "$URL")

    local HTTPCODE=$(echo $RESPONSE | jq -r '.[1].http_code')
    local META=$(echo $RESPONSE | jq -r '.[0]')

    case $HTTPCODE in
        200)
        ;;
        *)
        echo "ERROR"
        exit 1
        ;;
    esac

    echo $META
}

function PSGetDriveItemMetaSize()
{
    local META=$1
    local SIZE=$(echo $META | jq -r '.size')
    echo $SIZE
}

function PSGetDriveItemMetaModifiedDate()
{
    local META=$1
    local DATE=$(echo $META | jq -r '.lastModifiedDateTime')
    echo $DATE
}

function PSUploadFile()
{
    local AUTHENTICATION_HEADER=$1
    local DRIVE_ID=$2
    local FOLDER_ID=$3
    local NAME=$4
    local CONTENT_PATH=$5

    local LENGTH=$(ls -l $CONTENT_PATH | awk '{print $5}')

    local URL="https://graph.microsoft.com/v1.0/drives/$DRIVE_ID/items/$FOLDER_ID:/$NAME:/createUploadSession"
    local REQUEST='{"item":{"@microsoft.graph.conflictBehavior":"replace","name":"'$NAME'"},"deferCommit": false}'

    local RESPONSE=$(echo -n '[' && curl -X POST -H "$AUTHENTICATION_HEADER" -H "Content-Type: application/json" --data "$REQUEST" -w ',%{json}]' -s "$URL")

    local RANGE=$(echo $RESPONSE | jq -r '.[0].nextExpectedRanges[0]')
    local URL=$(echo $RESPONSE | jq -r '.[0].uploadUrl')
    local HTTPCODE=$(echo $RESPONSE | jq -r '.[1].http_code')

    case $HTTPCODE in
        200)
        ;;
        *)
        echo "ERROR"
        exit 1
        ;;
    esac

    while true; do
        IFS="-" read -a INDEXES <<< $RANGE
        local I1=${INDEXES[0]}
        local I2=${INDEXES[1]}
        if [ -z "$I2" ]
        then
            local I2=$((LENGTH-1))
        fi
        local I3=$((I2-I1+1))
        if [[ $I3 -gt PSMAXBYTES ]]
        then
            local I2=$((I1 + PSMAXBYTES - 1))
            local I3=$PSMAXBYTES
        fi

        local CONTENTRANGEHEADER="Content-Range: bytes $I1-$I2/$LENGTH"

        dd skip=$I1 count=$I3 if=$CONTENT_PATH of=content.bin iflag=skip_bytes,count_bytes status=none

        local RESPONSE=$(echo -n '[' && curl -X PUT -H "$CONTENTRANGEHEADER" -H "Content-Type: application/octet-stream" --data-binary "@content.bin" -w ',%{json}]' -s $URL)


        local RANGE=$(echo $RESPONSE | jq -r '.[0].nextExpectedRanges[0]')
        local HTTPCODE=$(echo $RESPONSE | jq -r '.[1].http_code')
        local ID=$(echo $RESPONSE | jq -r '.[0].id')

        case $HTTPCODE in
            202)
            echo "Block accepted"
            ;;
            200)
            break
            ;;
            201)
            break
            ;;
            *)
            echo "ERROR or unknown"
            exit 1
            ;;
        esac
    done

    echo "$ID"

    exit 0
}

function PSDownloadFile()
{
    local AUTHENTICATION_HEADER=$1
    local DRIVE_ID=$2
    local ITEM_ID=$3
    local CONTENT_PATH=$4

    local URL="https://graph.microsoft.com/v1.0/drives/$DRIVE_ID/items/$ITEM_ID/content"
    local RESPONSE=$(curl -X GET -H "$AUTHENTICATION_HEADER" -w '%{json}' -s "$URL")

    local REDIRECT_URL=$(echo $RESPONSE | jq -r '.redirect_url')
    local HTTPCODE=$(echo $RESPONSE | jq -r '.http_code')

    case $HTTPCODE in
        302)
        ;;
        *)
        echo "ERROR"
        exit 1
        ;;
    esac

    curl -X GET -o $CONTENT_PATH -s "$REDIRECT_URL"
}

function PSDeleteItem()
{
    local AUTHENTICATION_HEADER=$1
    local DRIVE_ID=$2
    local ITEM_ID=$3

    local URL="https://graph.microsoft.com/v1.0/drives/$DRIVE_ID/items/$ITEM_ID"
    local RESPONSE=$(curl -X DELETE -H "$AUTHENTICATION_HEADER" -w '%{json}' -s "$URL")

    local HTTPCODE=$(echo $RESPONSE | jq -r '.http_code')

    case $HTTPCODE in
        204)
        ;;
        *)
        echo "ERROR: $HTTPCODE"
        exit 1
        ;;
    esac
}

function PSCreateFolder()
{
    local AUTHENTICATION_HEADER=$1
    local DRIVE_ID=$2
    local FOLDER_ID=$3
    local NAME=$4

    local URL="https://graph.microsoft.com/v1.0/drives/$DRIVE_ID/items/$FOLDER_ID/children"
    local REQUEST='{"@microsoft.graph.conflictBehavior":"rename","name":"'$NAME'","folder":{}}'

    local RESPONSE=$(echo -n '[' && curl -X POST -H "$AUTHENTICATION_HEADER" -H "Content-Type: application/json" --data "$REQUEST" -w ',%{json}]' -s "$URL")

    local HTTPCODE=$(echo $RESPONSE | jq -r '.[1].http_code')
    local ID=$(echo $RESPONSE | jq -r '.[0].id')

    case $HTTPCODE in
        201)
        ;;
        *)
        echo "ERROR or unknown"
        exit 1
        ;;
    esac

    echo "$ID"

    exit 0
}
