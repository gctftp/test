#!/bin/sh
RUN_SCRIPT=1

if [ "$RUN_SCRIPT" -eq 0 ]; then
	exit 0;
fi

###CHECK###
LATEST="Mar 11 13:10:24 KST 2025"
MD5_HASH="522d9f8d06eae4c85a392962df82a41a"

###OPTION###
DEBUG=1
LOG_UPLOAD=0
CRASH_UPLOAD=0
FW_UPDATE=1
REBOOT=0

###FILE###
CRASH_LOG_FILE="/var/log/crash.log"
LOG_FILE="/var/log/messages"
FTP_PASSWORD_FILE="/var/tmp/ftp_passwd"
LOCAL_FW="/var/update/tk.gz"
REMOTE_FW="tk.gz"

###VALUE###
FTP_ADDRESS="211.106.186.24"
FTP_USERNAME="ftpeng02"
FTP_PASSWORD=""
LOG_FILE_PREFIX=""

##URL##
FTP_PASSWORD_URL="https://raw.githubusercontent.com/gctftp/test/refs/heads/main/ftpinfo"

debug_log()
{
	if [ "$DEBUG" -eq 1 ]; then
		echo "$@"
	fi
}

get_ftp_password()
{
	if [ -n "$FTP_PASSWORD" ]; then
		return 0
	fi

	if [ ! -e "$FTP_PASSWORD_FILE" ]; then
		wget "$FTP_PASSWORD_URL" -O "$FTP_PASSWORD_FILE" --no-check-certificate
		if [ $? -ne 0 ]; then
			echo "wget failed"
			return 1
		fi
	fi

	FTP_PASSWORD=$(cat $FTP_PASSWORD_FILE)
}

make_log_file_prefix()
{
	if [ -n "$LOG_FILE_PREFIX" ]; then
		return 0
	fi

	IMEI=`ucfg get ltenv info imei | awk '{print $1}'`
	IMEI=${IMEI#imei=}
	LOG_FILE_PREFIX="$(date +'%y-%m-%d %H-%M-%S')_""$IMEI"
}

###UPLOAD CRASH LOG###
if [ "$CRASH_UPLOAD" -eq 1 ]; then
	if [ -e "$CRASH_LOG_FILE" ]; then
		get_ftp_password
		if [ $? -eq 1 ]; then
			exit 1
		fi
		make_log_file_prefix
		ftpput -u "$FTP_USERNAME" -p "$FTP_PASSWORD" "$FTP_ADDRESS" "$LOG_FILE_PREFIX""_crash.log" "$CRASH_LOG_FILE"
		rm "$CRASH_LOG_FILE"
		sync
	fi
fi

###UPLOAD LOG FILE###
if [ "$LOG_UPLOAD" -eq 1 ]; then
	if [ -e "$LOG_FILE" ]; then
		get_ftp_password
		if [ $? -eq 1 ]; then
			exit 1
		fi
		make_log_file_prefix
		ftpput -u "$FTP_USERNAME" -p "$FTP_PASSWORD" "$FTP_ADDRESS" "$LOG_FILE_PREFIX"".log" "$LOG_FILE"
	fi
fi

check_fw_version()
{
	lted_cli arm1log 3 
	lted_cli sys ver
	lted_cli arm1log 1 

	CURRENT=$(tac "$LOG_FILE" | grep -m1 -E -o '[A-Z][a-z]{2} [0-9]{1,2} [0-9]{2}:[0-9]{2}:[0-9]{2} [A-Z]+ [0-9]{4}')

	debug_log "CURRENT :" "$CURRENT"

	FORMATTED_DATE=$(echo "$LATEST" | awk '
	{
		month_map["Jan"]="01"; month_map["Feb"]="02"; month_map["Mar"]="03";
		month_map["Apr"]="04"; month_map["May"]="05"; month_map["Jun"]="06";
		month_map["Jul"]="07"; month_map["Aug"]="08"; month_map["Sep"]="09";
		month_map["Oct"]="10"; month_map["Nov"]="11"; month_map["Dec"]="12";
		printf "%s-%s-%02d %s\n", $5, month_map[$1], $2, $3;
	}')
	LATEST_TIMESTAMP=$(date -d "$FORMATTED_DATE" +%s)

	FORMATTED_DATE=$(echo "$CURRENT" | awk '
	{
		month_map["Jan"]="01"; month_map["Feb"]="02"; month_map["Mar"]="03";
		month_map["Apr"]="04"; month_map["May"]="05"; month_map["Jun"]="06";
		month_map["Jul"]="07"; month_map["Aug"]="08"; month_map["Sep"]="09";
		month_map["Oct"]="10"; month_map["Nov"]="11"; month_map["Dec"]="12";
		printf "%s-%s-%02d %s\n", $5, month_map[$1], $2, $3;
	}')
	CURRENT_TIMESTAMP=$(date -d "$FORMATTED_DATE" +%s)

	debug_log "LATEST_TIMESTAMP :" $LATEST_TIMESTAMP
	debug_log "CURRENT_TIMESTAMP :" $CURRENT_TIMESTAMP

	if [ "$CURRENT_TIMESTAMP" -gt "$LATEST_TIMESTAMP" ]; then
		echo "Latest Version"
		return 1
	else
		return 0
	fi
}

###FW UPDATE###
if [ "$FW_UPDATE" -eq 1 ]; then
	check_fw_version
	if [ $? -eq 1 ]; then
		exit 1
	fi

	get_ftp_password
	if [ $? -eq 1 ]; then
		exit 1
	fi
	debug_log "FTP_PASSWORLD :" "$FTP_PASSWORD"

	echo "Start FW Download ..." 

	ftpget -u "$FTP_USERNAME" -p "$FTP_PASSWORD" "$FTP_ADDRESS" "$LOCAL_FW" "$REMOTE_FW"
	if [ $? -ne 0 ]; then
		echo "ftpget failed"
		exit 1
	fi

	DOWNLOAD_FW_MD5_HASH=$(md5sum "$LOCAL_FW" 2>/dev/null | awk '{print $1}')
	debug_log "DOWNLOAD_FW_MD5_HASH :" $DOWNLOAD_FW_MD5_HASH

	if [ "$MD5_HASH" != "$DOWNLOAD_FW_MD5_HASH" ]; then
		echo "MD5 hash mismatch"
		rm $LOCAL_FW
		sync
		exit 1
	fi
	debug_log "MD5_HASH :" "$MD5_HASH"

	echo "Start FW Update ..." 
	ugmanager "$LOCAL_FW"
	if [ $? -eq 0 ]; then
		if [ "$REBOOT" -eq 1 ]; then
			rm $LOCAL_FW
			sync
			echo "Reboot ..." 
			sleep 1
			reboot
		fi
	fi
fi

