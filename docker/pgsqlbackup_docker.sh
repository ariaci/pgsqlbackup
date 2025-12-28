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
# Script to initiate backup of postgres-databases using pgsqlbackup-docker image
#

docker run -t --network=db-net -v=$1:/var/lib/postgresql/backup:rw --rm $3
