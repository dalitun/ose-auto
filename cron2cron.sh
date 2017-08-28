#!/bin/sh
#0 2 * * 0 /usr/bin/wget -O /dev/null "http://www.schoenen.nu/XMLparsing/ds1/generateXML.php?shop=shoesforfashionwomen"
CRONTAB=$1
IMAGE=${2:-www}

while read LINE; do
        echo "$LINE" |egrep "^(MAILTO|#)" >/dev/null && continue
        SCHEDULE=`echo "$LINE" |cut -d' ' -f 1-5`
        COMMAND=` echo "$LINE" |cut -d' ' -f 6- `
        oc run job-${IMAGE}-$((++i))  \
           --image=$IMAGE         \
           --schedule="$SCHEDULE" \
           --restart=OnFailure    \
           --command -- $COMMAND
done < $CRONTAB
