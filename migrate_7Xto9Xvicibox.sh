#!/bin/bash

##### CONFIGURE FIRST BEFORE RUNNING

#############################################
# previous_full_backup
#
# Lagay mo dito yung path kung saan mo nilagay
# yung buong path ng dating SQL mo
#############################################
previous_full_backup="/root/full-backup-2019-12-17.sql"


##### OPTIONAL CONFIGURABLES


#############################################
# mysql_data_dir
#
# Default: /srv/mysql/data
#
# Sa vicibox, ito yung path kung saan nilalagay
# ni mysql yung data nya
#############################################
mysql_data_dir="/srv/mysql/data"


#############################################
# mysql_data_backup_dir
#
# Default: /tmp/mysql_databackup_dir
#
# Dito ko lalagay backups na kailangan ko para makagalaw
# dapat mas malaki ito mga X2 kesa sa contents ng
# mysql_data_dir mo (du -sh mo parehong directory)
# hindi ko na kasi to chinecheck sa script na to
#############################################
mysql_data_backup_dir="/tmp/mysql_databackup_dir"


##### END CONFIGURABLES

###################################################
# WALA NANG GAGALAWIN DITO KUNG MERON, SABIHAN MO #
# AKO                                             #
###################################################
echo '##################### MIGRATION START! ###############################'

RUNTIME_CONTROL="${mysql_data_backup_dir}/.runtime"
RUNTIME=$(date "+%Y%m%d%H%M%S")
PV=$(which pv)

echo "$*" | grep ' -f ' > /dev/null 2>&1
if [ "$?" = "0" ];then
    echo "RUNNING FORCED"
    rm -rf ${RUNTIME_CONTROL}
fi

mkdir -p ${mysql_data_backup_dir}

if [ ! -d "${mysql_data_backup_dir}" ];then
    echo "Directory ${mysql_data_backup_dir} is not a directory. Exiting";
    exit 1
fi

if [ -f "${RUNTIME_CONTROL}" ];then
    echo "${RUNTIME_CONTROL} still exists. Please remove manually if the script is not running. Then rerun.";
    exit 1
fi

echo "Starting Configuration!"
touch ${RUNTIME_CONTROL}


##### STOP MYSQL
echo -n "STARTING MYSQL..."
systemctl stop mysql
echo "done."
##### BACKUP THIS ONE
echo -n "Compressing..."
pushd ${mysql_data_dir}/..
tar cjpf ${mysql_data_backup_dir}/mysql_data_backup-${RUNTIME}.tar.bz2 data
echo "done."
##### RESTART
echo -n "STARTING MYSQL..."
systemctl start mysql
echo "done."
##### PUT OUR FULL BACKUP
echo -n "Restoring full backup..."

${PV} -V | grep 'Andrew Wood' > /dev/null 2>&1
if [ "$?" = "0" ];then
    ${PV} ${previous_full_backup} | mysql -u root asterisk
else
    mysql -u root asterisk < ${previous_full_backup}
fi
if [ "$?" != "0" ];then
    echo "Encountered invalid sql dump. Exiting"
    rm -rf ${RUNTIME_CONTROL}
    exit 1
fi
echo "done."
##### NOW EXTRACT
echo -n "Extracting data from full backup..."
echo "SET FOREIGN_KEY_CHECKS=0" > ${mysql_data_backup_dir}/asterisk_data_complete.sql
mysqldump -u root --complete-insert --no-create-info asterisk > ${mysql_data_backup_dir}/asterisk_data_complete.sql
echo "SET FOREIGN_KEY_CHECKS=1" >> ${mysql_data_backup_dir}/asterisk_data_complete.sql
cat ${mysql_data_backup_dir}/asterisk_data_complete.sql | sed 's/INSERT INTO/REPLACE INTO/g' > ${mysql_data_backup_dir}/asterisk_data_complete_replace.sql
echo "done."

##### NOW WE GO BACK
echo -n "Returning to previous state..."
systemctl stop mysql
tar cjpf ${mysql_data_backup_dir}/mysql_data_backup-previous-${RUNTIME}.tar.bz2
tar xvf ${mysql_data_backup_dir}/mysql_data_backup-${RUNTIME}.tar.bz2
systemctl start mysql
echo "done."

##### LAST WE import OLD data into NEW SCHEMA
echo -n "Import old data into new schema..."
mysql -u root asterisk < ${mysql_data_backup_dir}/asterisk_data_complete_replace.sql
if [ "$?" != "0" ];then
    echo "Encountered invalid sql dump. Exiting"
    rm -rf ${RUNTIME_CONTROL}
    exit 1
fi
echo "done."

rm -rf ${RUNTIME_CONTROL}

echo "##################### MIGRATION COMPLETE ###############################"
