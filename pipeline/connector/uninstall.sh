#!/bin/bash

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

rm -rf /opt/assetsonar-connector
rm -rf /var/lib/assetsonar-connector
crontab -l | grep -v '/opt/assetsonar-connector' | crontab -

#.