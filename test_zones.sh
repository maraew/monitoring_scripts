#!/bin/bash

DIR_PATH=$(cd `dirname $0` && pwd)
if [[ -f $DIR_PATH/keystonercv3 ]] ; then
    source "$DIR_PATH/keystonercv3"
else
    echo "keystonercv3 does not exist. exiting..."
    exit 1
fi

TOKEN=$(curl -i -sS --noproxy "*" "$OS_AUTH_URL:5000/v3/auth/tokens" -H 'Content-Type: application/json' -d '{"auth": {"identity": {"methods": ["password"],"password": {"user": {"name": "'"$OS_PROJECT_NAME"'","password": "'"$OS_PASSWORD"'", "domain": {"name": "'"$OS_USER_DOMAIN_NAME"'"}}}},"scope": {"project": {"domain": {"id": "'"$OS_PROJECT_DOMAIN_NAME"'"},"name": "'"$OS_PROJECT_NAME"'"}}}}'  | grep "X-Subject-Token" | awk '{print $2}' | tr -d " " | tr -d "\r")

if [[ -z "$TOKEN" ]] ; then
    echo "TOKEN is empty. Please check the TOKEN. exiting..."
    exit 2
fi

ZONE_DIFF_SERIAL_NUM=0
ZONE_BIND_EMPTY=0

TOTAL_COUNT=$(curl -sS --noproxy "*" -H "X-Auth-Token: $TOKEN" -H "X-Auth-All-Projects: True" "$OS_AUTH_URL:9001/v2/zones?limit=1" | jq -r '.metadata[] ')
[[ -z "$TOTAL_COUNT" ]] && echo "TOTAL_COUNT of objects in metadata is 0."

TMPFILE=$(mktemp /tmp/temp_dsgnt.json.XXXX)

## A request to designate API
curl -sS --noproxy "*" -H "X-Auth-Token: $TOKEN" -H "X-Auth-All-Projects: True" "$OS_AUTH_URL:9001/v2/zones?limit=$TOTAL_COUNT" | jq . > $TMPFILE

#true_active="select(.status==\"ACTIVE\") |"
true_active=""
for i in $(cat $TMPFILE | jq -r ".zones[] | $true_active .name" | awk '{gsub(/ /, ""); print}'); do
  DESIGNATE_SERIAL_OUT=$(cat $TMPFILE | jq -c ".zones[] | $true_active select ( .name | startswith(\"$i\")) | .serial" | awk '{gsub(/ /, ""); print}')
  [[ -z "$DESIGNATE_SERIAL_OUT" ]] && echo "Serial for requested zone is not found."
    BIND_NAME_OUT=$(rndc zonestatus $i | grep "name" | awk -F': ' '{print $2}')
    if [[ "$BIND_NAME_OUT" != "" ]] && [[ "$BIND_NAME_OUT" != "null" ]] && [[ "$BIND_NAME_OUT" == "$i" ]]; then
      BIND_SERIAL_OUT=$(rndc zonestatus "$BIND_NAME_OUT" | grep "$DESIGNATE_SERIAL_OUT" | awk -F': ' '{print $2}')
      if [[ "$BIND_SERIAL_OUT" != "$DESIGNATE_SERIAL_OUT" ]]; then
        let ZONE_DIFF_SERIAL_NUM++
        #echo "zone $i has a difference in SERIALS"
        continue
          fi
      if [[ -z "$BIND_SERIAL_OUT" ]]; then
        let ZONE_BIND_EMPTY++
        #echo "zone $i has empty SERIAL"
        continue
      fi
   fi
done
rm -r "$TMPFILE" 2>/dev/null

## Obtain telegraf metrics
  echo "telegraf_zone_serial_odds num=${ZONE_DIFF_SERIAL_NUM}"
  echo "telegraf_zone_bind_empty num=${ZONE_BIND_EMPTY}"
