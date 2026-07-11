################################################################################
#                        执行文件中的sql                                       #
#作者:臧建伟                                                                   #
################################################################################
if [ $# -ne 1 -a $# -ne 3 ];then
	echo "Usage:$0 file [username] [password]"
	exit
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

#browfile=result.txt
browfile=~/.dbtmp/$$.txt

#sqlplus不能加-s参数，否则不能显示执行的sql
#set echo on 设置显示执行文件中的sql
sqlplus $DBUSER/$DBPASS<<END  > /dev/null
set echo on;
set sqlprompt ""
set linesize 32767;
set long 1000000
set longchunksize 1000000
set SQLNUMBER OFF
set trimout on;
set trimspool on;
spool $browfile;
@$1;
spool off;
--exit
END

#sed -n '2,$p' $browfile|grep -v "SQL>.*spool off"|sed 's/SQL> //' > $browfile.tmp
#mv $browfile.tmp $browfile
vim -u NONE -c "call oracle_tui#SetEnv()" $browfile

rm $browfile
