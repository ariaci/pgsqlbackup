# pgsqlbackup v1.1
#
# Copyright 2017 Patrick Morgenstern (ariaci)
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
# Script to make automatic backups of all your PostgreSQL databases
# on QNAP devices based on mysqlbackup of Kenneth Friebert
#
# Thanks to Kenneth Fribert for mysqlbackup (https://forum.qnap.com/viewtopic.php?t=15628)
#

# Standard commands used in this script
rm_c="/bin/rm"
tar_c="/bin/tar"
awk_c="/bin/awk"
get_c="/sbin/getcfg"
ec_c="/bin/echo"
log_c="/sbin/write_log"
md_c="/bin/mkdir"
ls_c="/bin/ls"
date_c="/bin/date"

# Check config file to use
if [[ -z "$1" ]] ; then config="/etc/config/pgsqlbackup.conf" ; else config=$1 ; fi
if [ ! -e "$config" ] ; then
   $ec_c -e "PostgreSQL Backup: ERROR: configuration file not found"
   $log_c "PostgreSQL Backup: ERROR configuration file not found" 1
   exit 1
fi

# Read config file
day_ret=$(/sbin/getcfg pgsqlbackup day_retention -f "$config")
week_ret=$(/sbin/getcfg pgsqlbackup week_retention -f "$config")
month_ret=$(/sbin/getcfg pgsqlbackup month_retention -f "$config")
weekday_rot=$(/sbin/getcfg pgsqlbackup day_rotate -f "$config")
share=$(/sbin/getcfg pgsqlbackup share -f "$config")
sharetype=$(/sbin/getcfg pgsqlbackup sharetype -f "$config")
folder=$(/sbin/getcfg pgsqlbackup folder -f "$config")
user=$(/sbin/getcfg pgsqlbackup user -f "$config")
pw=$(/sbin/getcfg pgsqlbackup pw -f "$config")
level=$(/sbin/getcfg pgsqlbackup errorlvl -f "$config")
searchfolders=$(/sbin/getcfg pgsqlbackup searchfolders -f "$config")
server=$(/sbin/getcfg pgsqlbackup server -f "$config")
port=$(/sbin/getcfg pgsqlbackup port -f "$config")

# Internal variable setup
arc=$($date_c +%y%m%d).tar.gz
dest=
cur_month_day=$($date_c +"%d")
cur_week_day=$($date_c +"%u")
pgsqld_p=
pgsqld_c=
pgsqlc_p=
pgsqlc_c=
error=
databases=
bkup_p=

# Error and logging functions

function error ()
{ $ec_c -e "PostgreSQL Backup: ERROR: $1" ; if test "$level" -gt 0 ; then $log_c "PostgreSQL Backup: ERROR $1" 1 ; fi ; exit 1 ; }

function warn ()
{ $ec_c -e "PostgreSQL Backup: WARNING: $1" ; if test "$level" -gt 1 ; then $log_c "PostgreSQL Backup: WARNING $1" 2 ; fi ;  }

function info ()
{ $ec_c -e "PostgreSQL Backup: INFO: $1" ; if test "$level" -gt 2 ; then $log_c "PostgreSQL Backup: INFO $1" 4 ; fi ; } 

# Functions for handling PID file

function pidfilename() {
  myfile=$(basename "$0" .sh)
  whoiam=$(whoami)
  mypidfile=/tmp/$myfile.pid
  [[ "$whoiam" == 'root' ]] && mypidfile=/var/run/$myfile.pid
  echo $mypidfile
}

function cleanup () {
  trap - INT TERM EXIT
  [[ -f "$mypidfile" ]] && rm "$mypidfile"
  exit
}

function isrunning() {
  pidfile="$1"
  [[ ! -f "$pidfile" ]] && return 1
  procpid=$(<"$pidfile")
  [[ -z "$procpid" ]] && return 1
  [[ ! $(ps -p $procpid | grep $(basename $0)) == "" ]] && value=0 || value=1
  return $value
}

function createpidfile() {
  mypid=$1
  pidfile=$2
  $(exec 2>&-; set -o noclobber; echo "$mypid" > "$pidfile") 
  [[ ! -f "$pidfile" ]] && exit #Lock file creation failed
  procpid=$(<"$pidfile")
  [[ $mypid -ne $procpid ]] && {
    isrunning "$pidfile" || {
      rm "$pidfile"
      $0 $@ &
    }
    {
    echo "pgsqlbackup is already running, exiting"
    exit
    }
  }
}

# Start script
mypidfile=$(pidfilename)
createpidfile $$ "$mypidfile"
trap 'cleanup' INT TERM EXIT

# Checking if prerequisites are met
if [[ -z "$level" ]] ; then level="0" ; warnlater="Errorlevel not set in config, setting to 0 (nothing)" ; fi
$ec_c -e "\n"
info "PostgreSQL Backup STARTED"

# Checking variables from config file
if [[ -n "$warnlater" ]] ; then warn "$warnlater" ; fi 
if [[ -z "$day_ret" ]] ; then day_ret="6" ; warn "days to keep backup not set in config, setting to 6" ; fi
if [[ -z "$week_ret" ]] ; then week_ret="5" ; warn "weeks to keep backup not set in config, setting to 5" ; fi
if [[ -z "$month_ret" ]] ; then month_ret="3" ; warn "months to keep backup not set in config, setting to 3" ; fi
if [[ -z "$weekday_rot" ]] ; then weekday_rot="0" ; warn "weekly rotate day not set in config, setting to sunday" ; fi
if [[ -z "$share" ]] ; then share="Backup" ; warn "share for storing backup not set in config, setting to Backup" ; fi
if [[ -z "$sharetype" ]] ; then sharetype="smb:qnap" ; info "sharetype for storing backup not set in config, setting to smb:qnap" ; fi
if [[ -z "$user" ]] ; then user="User" ; warn "PostgreSQL user for backup not set in config, setting to User" ; fi
if [[ -z "$pw" ]] ; then pw="Password" ; warn "PostgreSQL password for backup not set in config, setting to Password" ; fi
if [[ -z "$searchfolders" ]] ; then searchfolders="/share/CACHEDEV1_DATA/.qpkg/PostgreSQL /share/CACHEDEV1_DATA/.qpkg/Optware" ; info "PostgreSQL searchfolders for backup not set in config, setting 
to default for Qnap" ; fi
if [[ -z "$server" ]] ; then server="127.0.0.1" ; info "PostgreSQL server for backup not set in config, setting to 127.0.0.1" ; fi
if [[ -z "$port" ]] ; then port="5432" ; info "PostgreSQL server port for backup not set in config, setting to 5432" ; fi

# Check for backup share using sharetype
case $(tr '[:upper:]' '[:lower:]' <<<"$sharetype") in
   "smb:qnap")
      bkup_p=$($get_c "$share" path -f /etc/config/smb.conf)
      if [ $? != 0 ] ; then error "the share $share is not found, remember that the destination has to be a share" ; else info "Backup smb share found" ; fi
      ;;
   "filesystem")
      bkup_p=$share
      if [ ! -d "$bkup_p" ] ; then error "the share $share is not found in filesystem" ; else info "Backup filesystem share found" ; fi
      ;;
   *)
      error "the sharetype $sharetype is unknown, supported types are smb:qnap or filesystem"
      ;;
esac

# Add subfolder to backup share
if [[ -z "$folder" ]] ; then
   info "No subfolder given";
   else
   {
   info "subfolder given in config";
   bkup_p="$bkup_p"/"$folder";
   # Check for subfolder under share
   $md_c -p "$bkup_p" ; if [ $? != 0 ] ; then error "the backup folder ($folder) under the share could not be created on the share $share" ; fi
   }
fi

# Check for backup folder on backup share
if ! [ -d "$bkup_p/pgsql" ] ; then info "pgsql folder missing under $bkup_p, it has been created" ; $md_c "$bkup_p/pgsql" ; if [ $? != 0 ] ; then error "the folder pgsql could not be created on the share $share" ; fi ; fi

# Check for day retention folder on backup share
if ! [ -d "$bkup_p/pgsql.daily" ] ; then info "pgsql.daily folder missing under the share $bkup_p, it has been created" ; $md_c "$bkup_p/pgsql.daily" ; if [ $? != 0 ] ; then error "the folder pgsql.daily could not be created on the share $share" ; fi ; fi

# Check for week retention folder on backup share
if ! [ -d "$bkup_p/pgsql.weekly" ] ; then info "pgsql.weekly folder missing under the share $bkup_p, it has been created" ; $md_c "$bkup_p/pgsql.weekly" ; if [ $? != 0 ] ; then error "the folder pgsql.weekly could not be created on the share $share" ; fi ; fi

# Check for month retention folder on backup share
if ! [ -d "$bkup_p/pgsql.monthly" ] ; then info "pgsql.monthly folder missing under the share $bkup_p, it has been created" ; $md_c "$bkup_p/pgsql.monthly" ; if [ $? != 0 ] ; then error "the folder pgsql.monthly could not be created on the share $share" ; fi ; fi

# Check for pg_dump command
for pgsqld_p in $searchfolders; do
  [ -f $pgsqld_p/bin/pg_dump ] && pgsqld_c="$pgsqld_p/bin/pg_dump"
done
if [ -z $pgsqld_c ] ; then error "pg_dump command not found."; else info "pg_dump command found" ; fi

# Check for psql command
for pgsqlc_p in $searchfolders; do
  [ -f $pgsqlc_p/bin/psql ] && pgsqlc_c="$pgsqlc_p/bin/psql"
done
if [ -z $pgsqlc_c ] ; then error "psql command not found.";  else info "psql command found" ; fi

# Listing all the databases individually, and dumping them
databases=$($pgsqlc_c --dbname="postgres://$user:$pw@$server:$port/$user" --tuples-only --command="SELECT datname FROM pg_database WHERE datallowconn=true;")
if [ $? != 0 ] ; then error "cannot list databases, is server, port, username and password correct?" ; fi

# Delete old daily backups
info "Cleaning out old backups. Keeping the last $day_ret daily backups"
full="$bkup_p/pgsql.daily"
for target in $(ls -t "$full" | tail -n +$(($day_ret + 1 ))) ; do rm -f "$full/$target"; done
if [ $? != 0 ] ; then error "erasing old daily backups" ; fi

# Delete old weekly backups
info "Cleaning out old backups. Keeping the last $week_ret week backups"
full="$bkup_p/pgsql.weekly"
for target in $(ls -t "$full" | tail -n +$(($week_ret + 1 ))) ; do rm -f "$full/$target"; done
if [ $? != 0 ] ; then error "erasing old weekly backups" ; fi

# Delete old monthly backups
info "Cleaning out old backups. Keeping the last $month_ret montly backups"
full="$bkup_p/pgsql.monthly"
for target in $(ls -t "$full" | tail -n +$(($month_ret + 1 ))) ; do rm -f "$full/$target"; done
if [ $? != 0 ] ; then error "erasing old monthly backups" ; fi

info "Backing up current databases to $bkup_p/pgsql"
while read line
do
  set $line
  $ec_c -e "Backing up database $line"
  $pgsqld_c --dbname="postgresql://$user:$pw@$server:$port/$line" --blobs --create --format=p --file="$bkup_p/pgsql/$line.sql"
  if [ $? != 0 ]; then error "creating new backup when trying to access the database $line" ; error=error ; fi
done<<<"$databases"

if [[ -z $error ]] ; then info "Backup Successfull" ; else error "Backup encountered errors, please investigate" ; fi
 
# Compress backup to an seleced archive

# On first month day do
if [ $cur_month_day == 01 ] ; then
  {
  dest=pgsql.monthly;
  info "Creating a monthly archive";
  }
else
  # On selected weekday do
  if [ $cur_week_day == $weekday_rot ] ; then
    {
    dest=pgsql.weekly;
    info "Creating a weekly archive";
    }
  else
    # On any regular day do
    {
    dest=pgsql.daily;
    info "Creating a daily archive";
    }
  fi
fi

info "Compressing backup to $bkup_p/$dest/$arc"
cd "$bkup_p/pgsql/" 
$tar_c 2> /dev/null -czvf "$bkup_p/$dest/$arc" * --remove-files &>/dev/null
if [ $? != 0 ] ; then error "compressing backup" ; else info "Done compressing backup" ; fi

info "Cleaning up after archiving"
$rm_c -f "$bkup_p/pgsql/*"

info "PostgreSQL Backup COMPLETED"
