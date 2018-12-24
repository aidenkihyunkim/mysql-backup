#!/bin/bash

# mysql-backup --- Backup mysql databases
# Copyright © 2018 Aiden Kim <aiden.kh.kim@gmail.com>

ARCHIVE_PERIOD=30
BINLOG_PATH=/var/lib/mysql
BINLOG_FILE=mysql-bin
LOCAL_BACKUP_PATH=/backup/mysql
SYSTEM_NAME=$(echo "${HOSTNAME}" | tr "[:lower:]" "[:upper:]")
S3_BACKUP_PATH=s3://s3_bucket_name/${SYSTEM_NAME}/mysql
STATUS_FILE_PATH=${LOCAL_BACKUP_PATH}/mysql-backup-status

## prepare path
if ! [ -d ${LOCAL_BACKUP_PATH} ]; then
	mkdir -p ${LOCAL_BACKUP_PATH}
fi

# full backup
if [[ "$1" == "full" ]]; then

	echo "MySQL Full Backup started $(date)..."

	# prepare directory
	TSTR=$(date +"%Y%m%d_%H%M%S")
	BACKUP_PATH=${LOCAL_BACKUP_PATH}/${TSTR}
	if ! [[ -d ${BACKUP_PATH} ]]; then
		mkdir -p "${BACKUP_PATH}"
	fi
	rm -rf "${BACKUP_PATH:?}/"*

	# get old full backup information
	if [[ -r ${STATUS_FILE_PATH} ]]; then
		OLD_BACKUP_PATH=$(sed -n '1p' ${STATUS_FILE_PATH})
		OLD_START_BINLOG=$(sed -n '2p' ${STATUS_FILE_PATH})
	fi

	# full backup
	mysqldump --all-databases --routines --events --hex-blob --single-transaction --flush-logs --master-data=2 --include-master-host-port > "${BACKUP_PATH}/full_backup-${TSTR}.sql"
	START_BINLOG=$(sed -rn "1,50 s/^.+ MASTER_LOG_FILE\='(${BINLOG_FILE}\.[0-9]+)'.+$/\1/p" "${BACKUP_PATH}/full_backup-${TSTR}.sql" | sed -n '1p')
	echo "${BACKUP_PATH}" > ${STATUS_FILE_PATH}
	echo "${START_BINLOG}" >> ${STATUS_FILE_PATH}
	gzip "${BACKUP_PATH}/full_backup-${TSTR}.sql"

	# finalize previous full backup data
	if [[ -n ${OLD_BACKUP_PATH} ]] && [[ -n ${OLD_START_BINLOG} ]] && [[ -d ${OLD_BACKUP_PATH} ]]; then
		for FILE in $(find ${BINLOG_PATH} -maxdepth 1 -type f -name "${BINLOG_FILE}.??????" | sort -g)
		do
			if [[ "${FILE}" < "${BINLOG_PATH}/${START_BINLOG}" ]]; then
				if [[ "${FILE}" == "${BINLOG_PATH}/${OLD_START_BINLOG}" ]] || [[ "${FILE}" > "${BINLOG_PATH}/${OLD_START_BINLOG}" ]]; then
					/bin/cp -afpu "${FILE}" "${OLD_BACKUP_PATH}/"
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
	BACKUP_PATH=$(sed -n '1p' ${STATUS_FILE_PATH})
	START_BINLOG=$(sed -n '2p' ${STATUS_FILE_PATH})
	TSTR=$(echo "${BACKUP_PATH}" | sed -rn "s/^.+\/(20[0-9]{6}_[0-9]{6})$/\1/p")
	if ! [[ -d ${BACKUP_PATH} ]]; then
		echo "Could not find last full backup path."
		exit 2
	fi
	if ! [[ -d ${BINLOG_PATH} ]]; then
		echo "Could not find mysql bin-log path."
		exit 2
	fi

	# flush log & copy bin-log
	mysqladmin flush-logs
	BINLOG_CURR=$(find ${BINLOG_PATH} -maxdepth 1 -type f -name "${BINLOG_FILE}.??????" | sed 's/^.*\.//' | sort -g | tail -n 1)
	for FILE in $(find ${BINLOG_PATH} -maxdepth 1 -type f -name "${BINLOG_FILE}.??????" | sort -g)
	do
		if [[ "${BINLOG_PATH}/${BINLOG_FILE}.${BINLOG_CURR}" != "${FILE}" ]]; then
			if [[ "${FILE}" == "${BINLOG_PATH}/${START_BINLOG}" ]] || [[ "${FILE}" > "${BINLOG_PATH}/${START_BINLOG}" ]]; then
				cp -afpu "${FILE}" "${BACKUP_PATH}/"
			fi
		fi
	done

fi

# sync to s3 bucket
aws s3 sync "${BACKUP_PATH}/" "${S3_BACKUP_PATH}/${TSTR}/"

# remove old backups
for DIR in $(find ${LOCAL_BACKUP_PATH} -maxdepth 1 -type d -mtime +${ARCHIVE_PERIOD} | sort -g)
do
    rm -rf "${DIR}"
done

exit 0
