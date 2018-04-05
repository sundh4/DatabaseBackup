#!/bin/bash

# Function to check 'backup_drive' mounted or not
checkBackup_drive (){
    # Check if mounted or not first
    df -h |grep /mnt/backup_drive > /dev/null 2>&1
    if [ $? = '0' ];
    then
        DRIVE_STATUS="Backup Drive Mounted"
        echo $DRIVE_STATUS
    else
        # Try to mounting
        echo "Mounting Backup Drive....."
        mkdir -p /mnt/backup_drive/
        mount -t cifs -o rw,user="guest",pass="",uid=0,gid=0 //10.153.64.20/Volume_1/ /mnt/backup_drive/ >/dev/null 2>&1
        # Handler if mount success or failed with exit code
        EXIT_CODE="$?"
        if [ "$EXIT_CODE" == '32' ]
        then
            # Exit script if mounting failed
            DRIVE_STATUS="Mounting Error!"
            echo "$0: $DRIVE_STATUS"
            exit 2
        else
            DRIVE_STATUS="Mounting Successful"
            echo $DRIVE_STATUS
        fi
    fi
}
checkBackup_drive