#!/bin/bash

# Part of pgsqlbackup v1.2
#
# Copyright 2018 Patrick Morgenstern (ariaci)
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#
# Script to create docker image to backup available postgres-docker-container
#

if [[ -z "$1" ]] ; then
   echo -e "Create docker-image: ERROR: invalid image-name"
   exit 1
fi

if [ ! -e "$2" ] ; then
   echo -e "Create docker-image: ERROR: configuration file not found"
   exit 1
fi

if [ ! -e "./tmp" ] ; then mkdir "./tmp" ; fi

cp ../pgsqlbackup.sh ./tmp/pgsqlbackup.sh
cp ../pgsqlbackup_getcfg.sh ./tmp/pgsqlbackup_getcfg.sh
cp "$2" ./tmp/pgsqlbackup.conf

echo "share=/var/lib/postgresql/backup" >>./tmp/pgsqlbackup.conf
echo "sharetype=filesystem" >>./tmp/pgsqlbackup.conf
echo "server=pgsql" >>./tmp/pgsqlbackup.conf
echo "searchfolders=/usr" >>./tmp/pgsqlbackup.conf

docker build --rm --force-rm -t "$1" .

rm -rf ./tmp
