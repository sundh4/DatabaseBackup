#!/bin/bash

# Script for backup whole database server using percona Xtrabackup
# Author: Surya
# Make sure percona xtrabackup installed

# Check xtrabackup first
# Exit script if not installed
xtrabackup --version >/dev/null 2>&1
if [ "$?" != 0 ]
then
    echo "Please install Percona Xtrabackup first"
    exit 127
fi

# Usage Function
usage() {
    echo "Usage:"
    echo "$0 --user= --pass= --serverName="
    echo ""
    echo "options:"
    echo "--user=<DB USER>                      specify db user name"
    echo "--pass=<DB PASS>                      specify db password"
    echo "--serverName=<SERVER NAME>            Server name"
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
        "--serverName="* )
            SERVER_NAME="${1#*=}"
            a=$((a+1))
            shift ;;
        * )
            usage ;;
    esac
done

# Checking parameters
if [ "$a" -ne 3 ]
then
    usage
fi

# Define paths and variables
TODAY="$(date +%F)"
BFL="/mnt/backup_drive/UNIXServerBackups/DatabaseBackups"
SERVER_DIR="$BFL/$SERVER_NAME"
DATA_DIR="$SERVER_DIR/xtrabackups"
FULL_TARGET_DIR="$DATA_DIR/$TODAY"
LOG_DIR="$SERVER_DIR/log"
mkdir -p $FULL_TARGET_DIR
mkdir -p $LOG_DIR

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
    echo -e "$(date +"%F %T");XTRABACKUPS;$SERVER_NAME;FAILED;2; \n" >>"$LOG_DIR/xtrabackups.log"
    exit 2
fi

# Temporary dir condition
if [ "$SERVER_NAME" == 'IntradayServer' ]
then
    TEMP="/mnt/dataHDD/Temp_Backup/$SERVER_NAME/xtrabackups"
    TMP_DIR="$TEMP/$TODAY"
else
    TEMP="/Temp_Backup/$SERVER_NAME/xtrabackups"
    TMP_DIR="$TEMP/$TODAY"
fi

# Temporary directory initialisation
rm -rf $TEMP
mkdir -p $TMP_DIR

#Backup function
xtrabackup_server() {
    echo "Starting to backup $SERVER_NAME........"
    echo "$(date +"%F %T");XTRABACKUPS;$SERVER_NAME;START;" >>"$LOG_DIR/xtrabackups.log"
    innobackupex --no-timestamp --user=$DB_USER --password=$DB_PASS --stream=tar $TMP_DIR |bzip2 - > "$TMP_DIR/$SERVER_NAME.tar.bz2"
    BCK_STATUS="${PIPESTATUS[0]}" BZIP_STATUS="${PIPESTATUS[1]}"
    # Checking dumping and Bzip status
    if [ "$BCK_STATUS" == '0' ]
    then
        XTRA_RESULT="SUCCESS"
        echo "Xtrabackup for $SERVER_NAME $XTRA_RESULT"
        # Checking compress status
        if [ "$BZIP_STATUS" == '0' ]
        then
            BZIP_RESULT="SUCCESS"
            echo "Compressing $BZIP_RESULT"
            # Create check hash
            CHK_SUM="$(shasum -a 256 $TMP_DIR/"$SERVER_NAME.tar.bz2" |awk '{print $1}')"
            echo "$CHK_SUM" >"$TMP_DIR/$SERVER_NAME.tar.bz2.sha256"
            echo "Hash: $CHK_SUM"
        else
            # Exit script if bzip failed
            BZIP_RESULT="FAILED"
            echo "$0: Compressing $BZIP_STATUS"
            echo -e "$(date +"%F %T");XTRABACKUPS;$SERVER_NAME;$BZIP_RESULT;4; \n" >>"$LOG_DIR/xtrabackups.log"
            exit 4
        fi
    else
        # Exit script if dumping failed
        XTRA_RESULT="FAILED"
        echo "$0: Xtrabackup for $SERVER_NAME $XTRA_RESULT"
        echo -e "$(date +"%F %T");XTRABACKUPS;$SERVER_NAME;$XTRA_RESULT;3; \n" >>"$LOG_DIR/xtrabackups.log"
        exit 3
    fi

    # Sync to backup_drive

        # Sync to backup_drive function
    syncBackup() {
        # Set max retry
        MAX_RETRIES=10

        # Set the initial return value to failure
        i=0
        false

        while [ $? -ne 0 -a $i -lt $MAX_RETRIES ]
        do
            i=$(($i+1))
            rsync -ah --progress --partial --delete --log-file=$FULL_TARGET_DIR/rsync.log $TMP_DIR/ $FULL_TARGET_DIR/
        done

        if [ "$?" == '0' ]
        then
            # Delete and keeps only 1 days backup dirs after sync success
            find "$DATA_DIR/" -maxdepth 1 -type d ! -name xtrabackups ! -name $TODAY |xargs rm -rf
            rm -rf $TMP_DIR/
            echo "ALL Process Done!"
        else
            echo "$0: Rsync Failed!"
            echo -e "$(date +"%F %T");XTRABACKUPS;$SERVER_NAME;FAILED;5; \n" >>"$LOG_DIR/xtrabackups.log"
            exit 5
        fi
        echo -e "$(date +"%F %T");XTRABACKUPS;$SERVER_NAME;SUCCESS;0; \n" >>"$LOG_DIR/xtrabackups.log"
    }
    # Calling sync function
    syncBackup
}

xtrabackup_server
