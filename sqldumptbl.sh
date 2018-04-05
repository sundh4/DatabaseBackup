#!/bin/bash

# Script for backup list of tables given for single database
# Author: Surya
# Make sure run this script using root

# Usage Function
usage() {
    echo "Usage: "
    echo "$0 --user= --pass= --serverName= --host= --port= --dbName= --table="
    echo ""
    echo "options:"
    echo "--user=<DB USER>                   specify db user name"
    echo "--pass=<DB PASS>                   specify db password"
    echo "--serverName=<SERVER NAME>         Server name"
    echo "--host=<HOSTNAME or IP ADDRESS>    Must use 'localhost' for Private Network"
    echo "--port=<PORT NUMBER>               port number for target mysql server"
    echo "--dbName=<DB NAME>                 database name to take backup"
    echo "--table=<TABLE NAME>               table name to take backup"
    exit 1
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
        "--dbName="* )
            DB_NAME="${1#*=}"
            a=$((a+1))
            shift ;;
        "--serverName="* )
            SERVER_NAME="${1#*=}"
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
        "--table="* )
            TBL_NAME="${1#*=}"
            a=$((a+1))
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

# Define DB parameters and path
BFL="/mnt/backup_drive/UNIXServerBackups/DatabaseBackups"
DB_PARAM="--single-transaction --no-create-db --no-create-info --skip-disable-keys \
--skip-set-charset --skip-triggers --skip-comments --skip-tz-utc --skip-add-locks --insert-ignore"
ACCT_PARAM="-h $HOST -u $DB_USER -p$DB_PASS -P $PORT"
TODAY="$(date +%F)"
PREV_DAY="$(date --date='yesterday' +%F)"

# Determine path where the script running
if [ -L $0 ] ; then
	SCRIPT_PATH=$(dirname $(readlink -f $0))
else
	SCRIPT_PATH=$(dirname $0)
fi

# Check backup drive mounted or not
$SCRIPT_PATH/checkBackupDrive.sh
if [ $? == 2 ]
then
    exit 2
fi

# Function to backup table
dump_table() {
    # Initialize all variable and path for each Database
    SERVER_DIR="$BFL/$SERVER_NAME"
    DB_DIR="$SERVER_DIR/$DB_NAME"
    FULL_TARGET_DIR="$DB_DIR/data"
    TMP_DIR="/Temp_Backup/$SERVER_NAME/$DB_NAME/data"
    # Main mysqldump table
    sqldumptbl() {
        mkdir -p $TMP_DIR
        mkdir -p $FULL_TARGET_DIR
        # Start backup
        echo "Starting to backup table $TBL_NAME from $DB_NAME...."
        mysqldump $ACCT_PARAM $DB_PARAM $DB_NAME $TBL_NAME |bzip2 > "$TMP_DIR/$TBL_NAME.sql.bz2"
        BCK_STATUS="${PIPESTATUS[0]}" BZIP_STATUS="${PIPESTATUS[1]}"
        # Checking dumping and Bzip status
        if [ "$BCK_STATUS" == '0' ]
        then
            DUMP_RESULT="SUCCESS"
            echo "Backup table $TBL_NAME $DUMP_RESULT"
            if [ "$BZIP_STATUS" == '0' ]
            then
                BZIP_RESULT="SUCCESS"
                echo "Compressing $BZIP_RESULT"
                # Create check hash
                CHK_SUM="$(shasum -a 256 $TMP_DIR/"$TBL_NAME.sql.bz2" |awk '{print $1}')"
                echo "$CHK_SUM" >"$TMP_DIR/$TBL_NAME.sql.bz2.sha256"
                echo "Hash: $CHK_SUM"
            else
                # Exit script if bzip failed
                BZIP_RESULT="FAILED"
                echo "$0: Compressing $BZIP_STATUS"
                exit 4
            fi
        else
            # Exit script if dumping failed
            DUMP_RESULT="FAILED"
            echo "$0: Backup table $DB_NAME.$TBL_NAME $DUMP_RESULT"
            exit 3
        fi
    }
    # Backup table
    sqldumptbl
    # Sync to backup_drive
    rsync -ahz --progress --log-file=$FULL_TARGET_DIR/rsync.log $TMP_DIR/ $FULL_TARGET_DIR/
    if [ "$?" == '0' ]
    then
        # Deleting temporary dir
        rm -r $TMP_DIR/
        echo "ALL Process Done!"
    else
        echo "$0: Rsync Failed!"
        exit 5
    fi
}

dump_table

# DONE
