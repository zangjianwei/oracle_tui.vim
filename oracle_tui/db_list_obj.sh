################################################################################
#                       列出所有的数据库对象                                   #
#作者:臧建伟                                                                   #
################################################################################
if [ $# -ne 1 -a $# -ne 3 ];then
	echo "Usage:`basename $0` <vimpid> [username] [password]"
	exit 1
fi

vimpid=$1
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

result_file=~/.dbtmp/.dblist_$vimpid.txt
nExec()
{
	sql=$1
	sqlplus -s $DBUSER/$DBPASS<<EOF>/dev/null 
  	set echo off;
  	set feedback off;
  	set heading off;
  	set pagesize 0;
  	set linesize 5000;
  	set numwidth 17;
  	set termout off;
  	set trimout on;
  	set trimspool on;
	set trimspool on;
	spool $result_file;
  	$sql;
	spool off;
  	exit
EOF
	return 0
}

rotate()
{
	str[1]="-"
	str[2]="\\"
	str[3]="|"
	str[4]="/"
	clear     #清屏
	n=1
	while true
	do
	    #echo -e "\033[12;30H Waiting...${str[$n]}"
	    printf "\033[12;30H Waiting...${str[$n]} \n"
		n=`echo $n|awk '{print ($0+1)%5}'`
	    if [ $n -eq 0 ]; then
	         n=1
	    fi
	    sleep 1
	done 
}
rotate &
#从作业表中移除,否则会显示:31477 Killed                  rotate
#disown $! 
if  command -v disown > /dev/null 2>&1 ;then
	disown $!
fi

kill_waitpid()
{
	echo "pid $! is killed!"
	kill -9 $!
	rm -f $result_file
}      

trap "kill_waitpid" 2 3  

nExec "select lower(name) from
(
	select 1 id1,1 id2,'[Table]' name from dual
	union
	SELECT 1 id1,2 id2,'	'||object_name name FROM USER_OBJECTS u where U.OBJECT_TYPE = 'TABLE' 
	union
	select 2 id1,1 id2,'[View]' name from dual
	union
	SELECT 2 id1,2 id2,'	'||object_name name FROM USER_OBJECTS u where U.OBJECT_TYPE = 'VIEW' 
	union
	select 3 id1,1 id2,'[Materialized_view]' name from dual
	union
	SELECT 3 id1,2 id2,'	'||object_name name FROM USER_OBJECTS u where U.OBJECT_TYPE = 'MATERIALIZED VIEW' 
	union
	select 4 id1,1 id2,'[Procedure]' name from dual
	union
	SELECT 4 id1,2 id2,'	'||object_name name FROM USER_OBJECTS u where U.OBJECT_TYPE = 'PROCEDURE' 
	union
	select 5 id1,1 id2,'[Index]' name from dual
	union
	SELECT 5 id1,2 id2,'	'||object_name name FROM USER_OBJECTS u where U.OBJECT_TYPE = 'INDEX' 
	union
	select 6 id1,1 id2,'[Function]' name from dual
	union
	SELECT 6 id1,2 id2,'	'||object_name name FROM USER_OBJECTS u where U.OBJECT_TYPE = 'FUNCTION' 
	union
	select 7 id1,1 id2,'[Sequence]' name from dual
	union
	SELECT 7 id1,2 id2,'	'||object_name name FROM USER_OBJECTS u where U.OBJECT_TYPE = 'SEQUENCE' 
	union
	select 8 id1,1 id2,'[Synonym]' name from dual
	union
	SELECT 8 id1,2 id2,'	'||object_name name FROM USER_OBJECTS u where U.OBJECT_TYPE = 'SYNONYM' 
	union
	select 9 id1,1 id2,'[Type]' name from dual
	union
	SELECT 9 id1,2 id2,'	'||object_name name FROM USER_OBJECTS u where U.OBJECT_TYPE = 'TYPE' 
	union
	select 10 id1,1 id2,'[Trigger]' name from dual
	union
	SELECT 10 id1,2 id2,'	'||object_name name FROM USER_OBJECTS u where U.OBJECT_TYPE = 'TRIGGER' 
	union
	select 11 id1,1 id2,'[Tablespace]' name from dual
	union
	SELECT 11 id1,2 id2,'	'||tablespace_name name FROM user_tablespaces
	union
	select 12 id1,1 id2,'[User]' name from dual
	union
	SELECT 12 id1,2 id2,'	'||username name FROM dba_users
	union
	select 13 id1,1 id2,'[Role]' name from dual
	union
	SELECT 13 id1,2 id2,'	'||role name FROM dba_roles
	union
	select 14 id1,1 id2,'[Database_link]' name from dual
	union
	SELECT 14 id1,2 id2,'	'||db_link name FROM dba_db_links
	union
	select 15 id1,1 id2,'[Profile]' name from dual
	union
	SELECT 15 id1,2 id2,'	'||profile name FROM dba_profiles
)
order by id1,id2,name"

kill -9 $!   > /dev/null 2>&1

exit 0
