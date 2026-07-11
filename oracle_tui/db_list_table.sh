################################################################################
#                       列出所有的表名和表明注释                               #
#                            自动补全用                                        #
#作者:臧建伟                                                                   #
################################################################################
if [ $# -ne 1 -a $# -ne 3 ];then
	echo "Usage:`basename $0` vimpid [username] [password]"
	exit 1
fi

if [ $# -eq 3 ];then
	DBUSER=$1
	DBPASS=$2
fi

vimpid=$1

result_file=$HOME/.dbtmp/.dbobj.$vimpid

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

nExec()
{
	sql=$1
	sqlplus -s $DBUSER/$DBPASS<<EOF > /dev/null
  	set echo off;
  	set feedback off;
  	set heading off;
  	set pagesize 0;
  	set linesize 5000;
  	set numwidth 17;
  	set termout off;
  	set trimout on;
  	set trimspool on;
	spool $result_file;
  	$sql;
	spool off;
  	exit
EOF
	return 0
}

nExec "SELECT cast(lower(TABLE_NAME) as char(40)) || '|' || comments FROM user_tab_comments a, USER_OBJECTS b where b.OBJECT_TYPE = 'TABLE'  and a.table_name = b.object_name"

exit 0
