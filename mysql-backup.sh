#!/bin/bash

# mysql-backup --- Backup mysql databases
# Copyright © 2014 Aiden Kim <aiden.kh.kim@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

ARCHIVE_PERIOD=15
BINLOG_PATH=/home/mysql/data
LOCAL_BACKUP_PATH=/home/backup/mysql
SYSTEM_NAME=$(echo $HOSTNAME | tr "[:lower:]" "[:upper:]")
S3_BACKUP_PATH=s3://s3_bucket_name/${SYSTEM_NAME}/mysql
STATUS_FILE_PATH=${LOCAL_BACKUP_PATH}/mysql-backup-status

## prepare path
if ! [ -d ${LOCAL_BACKUP_PATH} ]; then
	/bin/mkdir -p ${LOCAL_BACKUP_PATH}
fi

# full backup 
if [[ "$1" == "full" ]]; then

	echo "MySQL Full Backup started `date`..."

	# prepare directory
	TSTR=$(date +"%Y%m%d_%H%M%S")
	BACKUP_PATH=${LOCAL_BACKUP_PATH}/${TSTR}
	if ! [[ -d ${BACKUP_PATH} ]]; then
		/bin/mkdir -p ${BACKUP_PATH}
	fi
	/bin/rm -rf ${BACKUP_PATH}/*

	# get old full backup information
	if [[ -r ${STATUS_FILE_PATH} ]]; then
		OLD_BACKUP_PATH=`/bin/cat ${STATUS_FILE_PATH} | /bin/sed -n '1p'`
		OLD_START_BINLOG=`/bin/cat ${STATUS_FILE_PATH} | /bin/sed -n '2p'`
	fi

	# full backup
	/usr/bin/mysqldump --all-databases --routines --events --hex-blob --single-transaction --flush-logs --master-data=2 --include-master-host-port > ${BACKUP_PATH}/full_backup-${TSTR}.sql
	START_BINLOG=`/bin/sed -rn "1,50 s/^.+ MASTER_LOG_FILE\='(mysql-bin\.[0-9]+)'.+$/\1/p"  ${BACKUP_PATH}/full_backup-${TSTR}.sql | /bin/sed -n '1p'`
	echo "${BACKUP_PATH}" > ${STATUS_FILE_PATH}
	echo "${START_BINLOG}" >> ${STATUS_FILE_PATH}
	/bin/gzip ${BACKUP_PATH}/full_backup-${TSTR}.sql

	# finalize previous full backup data
	if [[ -n ${OLD_BACKUP_PATH} ]] && [[ -n ${OLD_START_BINLOG} ]] && [[ -d ${OLD_BACKUP_PATH} ]]; then
		for FILE in `ls ${BINLOG_PATH}/mysql-bin.?????? | sort -g`
		do
			if [[ "${FILE}" < "${BINLOG_PATH}/${START_BINLOG}" ]]; then
				if [[ "${FILE}" == "${BINLOG_PATH}/${OLD_START_BINLOG}" ]] || [[ "${FILE}" > "${BINLOG_PATH}/${OLD_START_BINLOG}" ]]; then
					/bin/cp -afpu ${FILE} ${OLD_BACKUP_PATH}/
				fi
			fi
		done
	fi

# incremental backup
else
	
	echo "MySQL Incremental Backup started..."

	# get previous full backup data
	if ! [[ -r ${STATUS_FILE_PATH} ]]; then
		echo "Could not find full backup status file."
		exit 1
	fi
	BACKUP_PATH=`/bin/cat ${STATUS_FILE_PATH} | /bin/sed -n '1p'`
	START_BINLOG=`/bin/cat ${STATUS_FILE_PATH} | /bin/sed -n '2p'`
	TSTR=`/bin/echo ${BACKUP_PATH} | sed -rn "s/^.+\/(20[0-9]{6}_[0-9]{6})$/\1/p"`
	if ! [[ -d ${BACKUP_PATH} ]]; then
		echo "Could not find last full backup path."
		exit 2
	fi
	if ! [[ -d ${BINLOG_PATH} ]]; then
		echo "Could not find mysql bin-log path."
		exit 2
	fi

	# flush log & copy bin-log
	/usr/bin/mysqladmin flush-logs
	BINLOG_CURR=`ls -d ${BINLOG_PATH}/mysql-bin.?????? | sed 's/^.*\.//' | sort -g | tail -n 1`
	for FILE in `ls ${BINLOG_PATH}/mysql-bin.?????? | sort -g`
	do
		if [[ "${BINLOG_PATH}/mysql-bin.${BINLOG_CURR}" != "${FILE}" ]]; then
			if [[ "${FILE}" == "${BINLOG_PATH}/${START_BINLOG}" ]] || [[ "${FILE}" > "${BINLOG_PATH}/${START_BINLOG}" ]]; then
				/bin/cp -afpu ${FILE} ${BACKUP_PATH}/
			fi
		fi
	done

fi

# sync to s3 bucket
/usr/bin/aws s3 sync ${BACKUP_PATH}/ ${S3_BACKUP_PATH}/${TSTR}/

# remove old backups
oldDirs=($(/bin/find ${LOCAL_BACKUP_PATH} -type d -mtime +${ARCHIVE_PERIOD}))
oldDirLen=${#oldDirs[@]}
for (( i=0; i<${oldDirLen}; i++ ));
do
	/bin/rm -rf ${oldDirs[$i]}
done

exit 0
