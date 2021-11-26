#!/bin/bash
DIR_PATH=$(cd `dirname $0` && pwd)
[[ -f $DIR_PATH/keystonercv3 ]] && source $DIR_PATH/keystonercv3 || echo "keystonercv3 does not exist."

TOKEN=`curl -i -sS --noproxy "*"  $OS_AUTH_URL:5000/v3/auth/tokens -H 'Content-Type: application/json' -d '{"auth": {"identity": {"methods": ["password"],"password": {"user": {"name": "'"$OS_PROJECT_NAME"'","password": "'"$OS_PASSWORD"'", "domain": {"name": "'"$OS_USER_DOMAIN_NAME"'"}}}},"scope": {"project": {"domain": {"id": "'"$OS_PROJECT_DOMAIN_NAME"'"},"name": "'"$OS_PROJECT_NAME"'"}}}}'  | grep "X-Subject-Token" | awk '{print $2}' | tr -d " " | tr -d "\r"`

[[ -z $TOKEN ]] && echo "TOKEN is empty. Please check the TOKEN."

ZONE_DIFF_SERIAL_NUM=0
ZONE_BIND_EMPTY=0

TOTAL_COUNT=`curl -sS --noproxy "*" -H "X-Auth-Token: $TOKEN" -H "X-Auth-All-Projects: True" $OS_AUTH_URL:9001/v2/zones?limit=1 | jq -r '.metadata[] '`
[[ -z "$TOTAL_COUNT" ]] && echo "TOTAL_COUNT of objects in metadata is 0."

TMPFILE=$(mktemp /tmp/temp_dsgnt.json.XXXX)

## A request to designate API
curl -sS --noproxy "*" -H "X-Auth-Token: $TOKEN" -H "X-Auth-All-Projects: True" $OS_AUTH_URL:9001/v2/zones?limit=$TOTAL_COUNT | jq . > $TMPFILE
for i in $(cat $TMPFILE | jq -r '.zones[] | select(.status=="ACTIVE") | .name' | awk '{gsub(/ /, ""); print}'); do
      DESIGNATE_SERIAL_OUT=`cat $TMPFILE | jq -c ".zones[] | select(.status==\"ACTIVE\") | select ( .name | startswith(\"$i\")) | .serial" | awk '{gsub(/ /, ""); print}'`
      [[ -z "$DESIGNATE_SERIAL_OUT" ]] && echo "Serial for requested zone is not found."
      BIND_NAME_OUT="`rndc zonestatus $i | grep "name" | awk -F': ' '{print $2}'`"
       if [[ -n $BIND_NAME_OUT ]] && [[ $BIND_NAME_OUT!="null" ]] && [[ $BIND_NAME_OUT == $i ]]; then
          BIND_SERIAL_OUT="`rndc zonestatus $BIND_NAME_OUT | grep "$DESIGNATE_SERIAL_OUT" | awk -F': ' '{print $2}'`"
          if [[ -n $BIND_SERIAL_OUT ]] && [[ $BIND_SERIAL_OUT != $DESIGNATE_SERIAL_OUT ]]; then
            let ZONE_DIFF_SERIAL_NUM++
            continue
          fi
          if [[ -z $BIND_SERIAL_OUT ]]; then
             echo $i
             let ZONE_BIND_EMPTY++
            continue
          fi
       fi
   done
rm -r "$TMPFILE" 2>/dev/null

## Obtain telegraf metrics
  echo "telegraf_zone_serial_odds num=${ZONE_DIFF_SERIAL_NUM}"
  echo "telegraf_zone_bind_empty num=${ZONE_BIND_EMPTY}"
