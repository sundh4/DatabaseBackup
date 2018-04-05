#!/bin/bash

# Driver Script for backup databases and their structure
# Author: Surya

# Determine path where the script running
if [ -L $0 ] ; then
	SCRIPT_PATH=$(dirname $(readlink -f $0))
else
	SCRIPT_PATH=$(dirname $0)
fi
export SCRIPT_PATH

# Function to list exit code to *_error.log
exitCodelog(){
    case $EXIT_CODE in
        '1' )
            ERR_STRING='(ERROR): Check valid arguments';;
        '2' )
            ERR_STRING='(ERROR): Backup drive failed to mount!';;
        '3' )
            ERR_STRING='(ERROR): Dumping FAILED!';;
        '4' )
            ERR_STRING='(ERROR): Compressing FAILED!';;
        '5' )
            ERR_STRING='(ERROR): Rsync FAILED!';;
    esac
}

# Usage Function
usage() {
    EXIT_CODE="1"
    exitCodelog
    echo "$ERR_STRING"
    echo "Usage:"
    echo "$0 --user= --pass= --serverName= --host= --port= --dbList= --keep="
    echo ""
    echo "options:"
    echo "--user=<DB USER>                   specify db user name"
    echo "--pass=<DB PASS>                   specify db password"
    echo "--serverName=<SERVER NAME>         Server name"
    echo "--host=<HOSTNAME or IP ADDRESS>    Must use 'localhost' for Private Network"
    echo "--port=<PORT NUMBER>               port number for target mysql server"
    echo "--dbList=<DB LIST>                 'all' or given list of databases name to take backup separate with comma ','"
    echo "--keep=<NUMBER>                    number of backup will be keep"
    exit $EXIT_CODE
}

# Define Args
a=0
while [[ "$1" != "" ]] && [[ ."$1" = .--* ]]; do
    case $1 in
        "--user="* )
            DB_USER="${1#*=}"
            a=$((a+1))
            shift ;;
        "--pass="* )
            DB_PASS="${1#*=}"
            a=$((a+1))
            shift ;;
        "--dbList="* )
            DB_LIST="${1#*=}"
            a=$((a+1))
            shift ;;
        "--host="* )
            HOST="${1#*=}"
            a=$((a+1))
            shift ;;
        "--port="* )
            PORT="${1#*=}"
            a=$((a+1))
            shift ;;
        "--serverName="* )
            SERVER_NAME="${1#*=}"
            a=$((a+1))
            shift ;;
        "--keep="* )
            KEEP_BACKUP="${1#*=}"
            if [ "$KEEP_BACKUP" -eq "$KEEP_BACKUP" ] 2>/dev/null
            then
                if [ "$KEEP_BACKUP" -ge 1 ]
                then
                    a=$((a+1))
                else
                    echo "ERROR!! --keep=<NUMBER> should more than '1'"
                    exit 1
                fi
            else
                echo "ERROR!! --keep=<NUMBER> should be integer"
                exit 1
            fi
            shift ;;
        * )
            usage ;;
    esac

done

# Checking parameters
if [ "$a" -ne 7 ]
then
    usage
fi

# Define common variables
TODAY="$(date +%F)"
TOTAL_KEEP="$(($KEEP_BACKUP-1))"
BFL="/mnt/backup_drive/UNIXServerBackups/DatabaseBackups"
SERVER_DIR="$BFL/$SERVER_NAME"
DATA_DIR="$SERVER_DIR/dumps/"
LOG_DIR="/mnt/public/IT/backuplogs"
LOGERR_DIR="$LOG_DIR/Logs/logsERR"
DAILY_LOG="$LOG_DIR/daily"
DAILY_ERRLOG_DIR="$DAILY_LOG/Errors"
LOGERRORSUMMARY="$DAILY_ERRLOG_DIR/$SERVER_NAME""_error.log"
ERRLOG="$LOGERR_DIR/$SERVER_NAME""_error.log"
LOGSUMMARYDAILY="$DAILY_LOG/$SERVER_NAME/file_Daily-Database_logSummary.txt"
# Initialize Logs
mkdir -p "$DAILY_ERRLOG_DIR" >/dev/null 2>&1
mkdir -p "$DAILY_LOG/$SERVER_NAME" >/dev/null 2>&1
mkdir -p "$LOGERR_DIR" >/dev/null 2>&1
{
echo "" > $LOGSUMMARYDAILY;
echo "" > $LOGERRORSUMMARY;
echo "" > $ERRLOG;
} >/dev/null 2>&1

# Database list condition
if [ "$DB_LIST" == 'all' ]
then
    EXCLUDE_LIST="'phpmyadmin','information_schema','performance_schema'"
    DB_LIST="$(mysql -u $DB_USER -p$DB_PASS information_schema -BNe \
    "SELECT schema_name FROM schemata where schema_name not in (${EXCLUDE_LIST})")"
else
    DB_LIST="$(echo "$DB_LIST" |sed "s/,/ /g")"
fi

# Exit code counting
X_CODE=0

# Main backup structure and data
for i in $DB_LIST
do
    # Assign database name
    DB_NAME="$i"
    # Dump Structure
    START_DATE="$(date +'%F %T')"
    { $SCRIPT_PATH/sqldumpstr.sh --user=$DB_USER --pass=$DB_PASS --serverName=$SERVER_NAME --host=$HOST --port=$PORT \
    --dbName=$DB_NAME 2>>$ERRLOG; } >/dev/null 2>&1
    EXIT_CODE="$?"
    EXIT_CODE_STR="$EXIT_CODE"
    if [ "$EXIT_CODE" == '0' ]
    then
        RESULT='SUCCESS'
        # Deleting old backup
        find $DATA_DIR/structure/ -maxdepth 1 -type d ! -name structure ! -name history -ctime +$TOTAL_KEEP |xargs rm -rf
    else
        RESULT='FAILED'
        exitCodelog
        { echo "sqldumpstr.sh $ERR_STRING" >>$LOGERRORSUMMARY; } >/dev/null 2>&1
    fi

    # Running backup database records
    { $SCRIPT_PATH/sqldumpdb.sh --user=$DB_USER --pass=$DB_PASS --serverName=$SERVER_NAME --host=$HOST --port=$PORT \
    --dbName=$DB_NAME 2>>$ERRLOG; } >/dev/null 2>&1
    EXIT_CODE="$?"
    EXIT_CODE_DBS="$EXIT_CODE"
    if [ "$EXIT_CODE" == '0' ]
    then
        RESULT='SUCCESS'
        # Deleting old backup
        find $DATA_DIR/data/ -maxdepth 1 -type d ! -name data ! -name history -ctime +$TOTAL_KEEP |xargs rm -rf
    else
        RESULT='FAILED'
        exitCodelog
        { echo "sqldumpdb.sh $ERR_STRING" >>$LOGERRORSUMMARY; } >/dev/null 2>&1
    fi
    END_DATE="$(date +'%F %T')"
    { echo -e "$DB_NAME;$RESULT;$START_DATE;$END_DATE;$EXIT_CODE_STR;$EXIT_CODE_DBS" >>"$LOGSUMMARYDAILY"; } >/dev/null 2>&1
    X_CODE="$((X_CODE+EXIT_CODE_STR+EXIT_CODE_DBS))"
done

# Last status at the end of backup
if [ "$X_CODE" == '0' ]
then
    echo "All Process Success"
else
    #echo "Some Backup FAILED!. See 'LOG' file for detail"
    EXIT_CODE=$X_CODE
    exitCodelog
    echo "$ERR_STRING"
    exit "$X_CODE"
fi
