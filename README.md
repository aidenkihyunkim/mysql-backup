# mysql-backup
Shell script to back up a MySQL server. This implements the full backup and the incremental backup.

# Usage
```sh
mysql-backup.sh [full | incremental]
```

# Description
This script performs full backup and incremental backup of MySQL databases, and upload backups to AWS S3.
The backup stands on the basis of the full backup once a day, So the backup path uses the date string.

Features:
  - Full backup all database
  - Incremental Backup based on previous full backup
  - Compress backup files
  - Upload backup files to AWS S3
  - Purge old local backups

# Requirements
  - mysql
  - gzip
  - AWS cli
  - Preconfigurated ~/.my.cnf for mysqldump and mysqladmin
  - Preconfigurated ~/.aws/credentials and ~/.aws/config for AWS cli

# Cron example
```sh
00 04  * * *   root   /root/bin/backup-mysql.sh full > /dev/null 2>&1
30 */1 * * *   root   /root/bin/backup-mysql.sh incremental > /dev/null 2>&1
```

# History
## Version 1.0
2014-09-06:
  First release.
  Commit the first version what been using in my production environments.

# Copyright
Copyright © 2018 Aiden Kim <aiden.kh.kim@gmail.com>.
Released under MIT License.
