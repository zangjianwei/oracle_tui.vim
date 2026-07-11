################################################################################
#                          获取表结构说明                                      #
#作者:臧建伟                                                                   #
################################################################################
if [ $# -ne 1 -a $# -ne 3 ];then
	echo "Usage:`basename $0` tabname [username] [password]"
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

old_tabname=$1
tabname=$1
echo $tabname|grep "\." > /dev/null 2>&1
if [ $? -eq 0 ];then
	username=`echo $tabname|awk -F. '{print toupper($1)}'`
	tabname=`echo $tabname|awk -F. '{print toupper($2)}'`
else
	username=`echo $DBUSER|awk -F@ '{print toupper($1)}'`
	tabname=`echo $tabname|awk '{print toupper($1)}'`
fi

browfile=~/.dbtmp/tab_$$.txt

nExec()
{
	sql=$1
	sqlplus -s $DBUSER/$DBPASS<<EOF > /dev/null
  	set echo off;
  	set feedback off;
  	set pagesize 100;
  	set linesize 5000;
  	set numwidth 17;
  	set termout off;
  	set trimout on;
  	set trimspool on;
	spool $browfile;
  	$sql;
	spool off;
  	exit
EOF
	return 0
}

sql="select cast(a.COLUMN_NAME as char(25)) column_name, \
	cast(DATA_TYPE as char(10)) as data_type, \
	cast(case when DATA_TYPE = 'NUMBER' and DATA_PRECISION > 0 and (DATA_SCALE is null or DATA_SCALE = 0) then to_char(DATA_PRECISION) \
     when DATA_TYPE = 'NUMBER' and (DATA_PRECISION is null or DATA_PRECISION = 0) and (DATA_SCALE is null or DATA_SCALE = 0) then to_char(DATA_LENGTH) \
	 when DATA_TYPE = 'NUMBER' and DATA_PRECISION > 0 and DATA_SCALE > 0 then to_char(DATA_PRECISION)||','||to_char(DATA_SCALE) \
	 else to_char(DATA_LENGTH) \
	 end as char(6))  leng, \
	cast(NULLABLE as char(8)) nullable,cast(comments as char(50)) comments \
from all_tab_columns a \
left outer join all_col_comments b \
on a.column_name = b.column_name \
where a.TABLE_NAME = '$tabname'  \
and a.OWNER = '$username' \
and b.TABLE_NAME = '$tabname' \
and b.OWNER = '$username' \
order by a.column_id "

nExec "$sql"

if [ ! -s $browfile ];then
	echo "没有表[$old_tabname]"
	rm -f $browfile
	exit 1
else
	cat $browfile
	rm -f $browfile
fi

exit 0
