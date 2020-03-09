#!/bin/bash
httpd
/etc/init.d/sas-viya-all-services start
jupyter lab --allow-root --no-browser
while true
do
        sleep 1
done
