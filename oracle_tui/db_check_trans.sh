################################################################################
#                       Check for uncommitted transactions.                    #
#Author: Zang Jianwei                                                          #
################################################################################
if [ $# -ne 1 -a $# -ne 3 ];then
	echo "Usage:`basename $0` vimpid [username] [password]"
	exit 1
fi

if [ $# -eq 3 ];then
	DBUSER=$2
	DBPASS=$3
fi

lc_all=`locale|grep LC_all|awk -F"=" '{gsub(/"/, "", $2);print $2}'`

lc_utf_flag=`locale|grep LC_CTYPE|sed 's/"//g'|awk -F"=" '{print $2}'|awk -F. '{
		if (tolower($2) ~/utf/)
			print 1
		else
			print 0
	}'`

if [ $lc_utf_flag -eq 0 ];then
	if [ "$lc_all" != "" ];then
		export LC_ALL="$TUI_LC_CTYPE"
	else
		export LC_CTYPE="$TUI_LC_CTYPE"
	fi
fi

nls_lang_utf_flag=`echo $NLS_LANG|awk -F. '{
		if (tolower($2) ~/utf/)
			print 1
		else
			print 0
	}'`

if [ $nls_lang_utf_flag -eq 0 ];then
	export NLS_LANG="$TUI_NLS_LANG"
fi

vimpid=$1

pipe_in=~/.dbtmp/.pipe_in.$vimpid
pipe_out=~/.dbtmp/.pipe_out.$vimpid
sqlplus_pid_file=~/.dbtmp/.sqlplus_pid.$vimpid

nExec()
{
    sqlplus -s $DBUSER/$DBPASS<<EOF
		set feedback off;
		set pagesize 0;
		$1;
EOF
}

if [ -s $sqlplus_pid_file ];then
	sqlplus_pid=`cat $sqlplus_pid_file|awk '{print $1}'`
	flag=`nExec "select case when count(*) > 0 then 'ok' else 'no' end as flag from v\\$transaction t, v\\$session s where t.ses_addr=s.saddr and process = '$sqlplus_pid'"`
	if [ "$flag" = "ok" ];then
		exit 1
	fi
fi

exit 0

#echo "ok"
