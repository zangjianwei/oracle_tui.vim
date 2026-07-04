################################################################################
#                     Export the SQL for creating database objects             #
#Author: Zang Jianwei                                                          #
################################################################################
if [ "$1" = "-h" ];then
	echo "Usage:`basename $0` <objname> [object_type] [username] [password]"
	exit 1
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

field_num=`echo $1|awk -F. '{print NF}'`
if [ $field_num -eq 2 ];then
	owner=`echo $1|awk -F. '{print toupper($1)}'`
	objname=`echo $1|awk -F. '{print toupper($2)}'`
else
	objname=`echo $1|awk '{print toupper($1)}'`
fi

if [ $# -eq 1 ];then
	:
elif [ $# -eq 2 ];then
	object_type=`echo "$2"|awk '{print toupper($0)}'`
elif [ $# -eq 3 ];then
	DBUSER=$2
	DBPASS=$3
elif [ $# -eq 4 ];then
	object_type=`echo "$2"|awk '{print toupper($0)}'`
	DBUSER=$3
	DBPASS=$4
else
	echo "Invalid parameter"
	exit 1
fi

IFS="
"

nExec()
{
	sql="$1"
    sqlplus -s $DBUSER/$DBPASS<<EOF
	set feedback off;
	set pagesize 0;
	$sql; 
EOF
}

nExecToFile()
{
	sql="$1"
	file=$2
	sqlplus -s $DBUSER/$DBPASS<<EOF >/dev/null
			set echo off;
			set feedback off;
			set heading off;
			set pagesize 0;
			set linesize 5000;
			set numwidth 17;
			set termout off;
			set trimout on;
			set trimspool on;
			spool $file;
			$sql;
			spool off;
			exit
EOF
}

nExecSql()
{
	sql="$1"
	outfile=$2
	sqlplus -S $DBUSER/$DBPASS<<END > /dev/null
	column aaa format a5000
	set echo off;
	set feedback off;
	set heading off;
	set pagesize 0;
	set long 900000;
	set linesize 30000;
	set numwidth 17;
	--set termout off;
	set trimout on;
	set trimspool on;
	spool $outfile;
	$sql;
	spool off;
	exit
END
}

nExecSqlFile()
{
	infile=$1
    outfile=$2
	sqlplus -s $DBUSER/$DBPASS<<END  > /dev/null
	column aaa format a5000
	set echo off;
	set feedback off;
	set heading off;
	set pagesize 0;
	set long 900000;
	set linesize 30000;
	set numwidth 17;
	--set termout off;
	set trimout on;
	set trimspool on;
	spool $outfile;
	@$infile;
	spool off;
	exit
END
}

kill_waitpid()
{
	echo "pid $! is killed!"
	kill -9 $!
}      

trap "kill_waitpid" 2 3  

#echo "$sqlstr" > ~/.dbtmp/$$.txt.sql   

browfile=~/.dbtmp/$$.txt

if [ "$object_type" = "" ];then
	if [ "$owner" = "" ];then
		sql="select OBJECT_TYPE from USER_OBJECTS where object_name = '$objname' and OBJECT_TYPE  != 'TABLE SUBPARTITION' and OBJECT_TYPE  != 'TABLE PARTITION'"
	else
		sql="select OBJECT_TYPE from ALL_OBJECTS where owner = '$owner' and object_name = '$objname' and OBJECT_TYPE  != 'TABLE SUBPARTITION' and OBJECT_TYPE  != 'TABLE PARTITION'"
	fi
	object_type=`nExec "$sql"|sed "s/[ 	]*$//g"`

	if [ "$object_type" = "" ];then
		echo "Database object not found[$objname]" > $browfile
		vim -c "call oracle_tui#SetEnv()" $browfile
		rm -f $browfile
		exit
	fi

	obj_nums=`echo "$object_type"|wc -l`

	if [ $obj_nums -gt 1 ];then
		echo "Multiple objects found in the database[$objname]" > $browfile
		
		vim -c "call oracle_tui#SetEnv()" $browfile
		rm -f $browfile
		exit
	fi

	if [ "$object_type" = "MATERIALIZED VIEW" ];then
		object_type="MATERIALIZED_VIEW"
	fi
fi

rotate()
{
	str[1]="-"
	str[2]="\\"
	str[3]="|"
	str[4]="/"
	clear     #clear screen
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
if  command -v disown > /dev/null 2>&1 ;then
	disown $!
fi

if [ "$object_type" = "TABLE" ];then
	idx_file=~/.dbtmp/$1_$$.idx
	
	if [ "$owner" = "" ];then
		nExecToFile "select INDEX_NAME from user_indexes where table_name='$objname'" $idx_file
	else
		nExecToFile "select INDEX_NAME from all_indexes where owner = '$owner' and table_name='$objname'" $idx_file
	fi
	
	sqlfile=$HOME/.dbtmp/$1_$$.sql
	if [ "$owner" = "" ];then
		echo "select dbms_metadata.get_ddl('TABLE','$objname')||';' aaa from dual;" > $sqlfile
	else
		echo "select dbms_metadata.get_ddl('TABLE','$objname', '$owner')||';' aaa from dual;" > $sqlfile
	fi
	for idx_name in `cat $idx_file`
	do
		if [ "$owner" = "" ];then
			echo "select dbms_metadata.get_ddl('INDEX','$idx_name')||';' aaa from dual;" >> $sqlfile
		else
			echo "select dbms_metadata.get_ddl('INDEX','$idx_name', '$owner')||';' aaa from dual;" >> $sqlfile
		fi
	done
	
	nExecSqlFile $sqlfile $browfile
	
	rm -f $idx_file
	rm -f $sqlfile
elif [ "$object_type" = "USER" ];then
	sqlfile=$HOME/.dbtmp/user_$$.sql
	cat << EOF > $sqlfile
	select '--Create the user' from dual 
	where exists (  
		select * FROM dba_users 
		WHERE username = UPPER('$objname')
		);
	
	SELECT 
	    'CREATE USER ' || username || ' IDENTIFIED BY ""' ||
	    ' DEFAULT TABLESPACE ' || default_tablespace ||
	    ' TEMPORARY TABLESPACE ' || temporary_tablespace ||
	    ' PROFILE ' || profile ||
	    ' ACCOUNT ' || DECODE(account_status, 'OPEN', 'UNLOCK', 'LOCK') ||
	    ';' AS create_user_sql
	FROM dba_users 
	WHERE username = UPPER('$objname');
	select '' from dual;
	
	select '--Grant/Revoke object privileges' from dual 
	where exists (  
		select * FROM dba_tab_privs
		WHERE grantee = UPPER('$objname')
		);
	
	SELECT 
	    'GRANT ' || privilege || ' ON ' || decode(type,'DIRECTORY','DIRECTORY','') 
		|| ' ' || owner || '.' || table_name || 
	    ' TO ' || grantee || 
	    DECODE(grantable, 'YES', ' WITH GRANT OPTION', '') || ';' AS grant_sql
	FROM dba_tab_privs
	WHERE grantee = UPPER('$objname')
	ORDER BY owner, table_name, privilege;
	select '' from dual;
	
	select '--Grant/Revoke role privileges' from dual 
	where exists (  
		select * FROM dba_role_privs
		WHERE grantee = UPPER('$objname')
		);
	
	SELECT 
	    'GRANT ' || granted_role || ' TO ' || grantee ||
	    DECODE(admin_option, 'YES', ' WITH ADMIN OPTION', '') || ';' AS grant_role_sql
	FROM dba_role_privs
	WHERE grantee = UPPER('$objname')
	ORDER BY granted_role;
	select '' from dual;
	
	select '--Grant/Revoke system privileges' from dual 
	where exists (  
		select * FROM dba_sys_privs
		WHERE grantee = UPPER('$objname')
		);
	
	SELECT 
	    'GRANT ' || privilege || ' TO ' || grantee ||
	    DECODE(admin_option, 'YES', ' WITH ADMIN OPTION', '') || ';' AS grant_sys_sql
	FROM dba_sys_privs
	WHERE grantee = UPPER('$objname')
	ORDER BY privilege;
	select '' from dual;
	
	select '--Grant/Revoke limits' from dual 
	where exists (   
		select * FROM dba_ts_quotas
		WHERE username = UPPER('$objname')
		);
	
	SELECT 
	    'ALTER USER ' || username || ' QUOTA ' ||
	    CASE 
	        WHEN max_bytes = -1 THEN 'UNLIMITED'
	        ELSE ROUND(max_bytes/1024/1024) || 'M'
	    END ||
	    ' ON ' || tablespace_name || ';' AS quota_sql
	FROM dba_ts_quotas
	WHERE username = UPPER('$objname')
	ORDER BY tablespace_name;
EOF
	nExecSqlFile $sqlfile $browfile
	rm -f $sqlfile
elif [ "$object_type" = "ROLE" ];then
	sqlfile=$HOME/.dbtmp/role_$$.sql
	cat << EOF > $sqlfile
	-- Create the role
	select '--Create role $objname' from dual;
	select 'create role $objname;' from dual;
	select '' from dual;
	
	-- Object privileges granted to the user.
	select '--Grant/Revoke object privileges' from dual 
	where exists (  
		select * FROM dba_tab_privs
		WHERE grantee = UPPER('$objname')
		);

	SELECT 
	    'GRANT ' || privilege || ' ON ' || decode(type,'DIRECTORY','DIRECTORY','') 
		|| ' ' || owner || '.' || table_name || 
	    ' TO ' || grantee || 
	    DECODE(grantable, 'YES', ' WITH GRANT OPTION', '') || ';' AS grant_sql
	FROM dba_tab_privs
	WHERE grantee = UPPER('$objname')
	ORDER BY owner, table_name, privilege;
	select '' from dual;
	
	-- Generate role grant statements.
	select '--Grant/Revoke role privileges' from dual 
	where exists (  
		select * FROM dba_role_privs
		WHERE grantee = UPPER('$objname')
		);
	SELECT 
	    'GRANT ' || granted_role || ' TO ' || grantee ||
	    DECODE(admin_option, 'YES', ' WITH ADMIN OPTION', '') || ';' AS grant_role_sql
	FROM dba_role_privs
	WHERE grantee = UPPER('$objname')
	ORDER BY granted_role;
	select '' from dual;
	
	-- Generate system privilege grant statements.
	select '--Grant/Revoke system privileges' from dual 
	where exists (  
		select * FROM dba_sys_privs
		WHERE grantee = UPPER('$objname')
		);

	SELECT 
	    'GRANT ' || privilege || ' TO ' || grantee ||
	    DECODE(admin_option, 'YES', ' WITH ADMIN OPTION', '') || ';' AS grant_sys_sql
	FROM dba_sys_privs
	WHERE grantee = UPPER('$objname')
	ORDER BY privilege;
EOF
	nExecSqlFile $sqlfile $browfile
	rm -f $sqlfile
elif [ "$object_type" = "DATABASE_LINK" ];then
	nExecSql "select 'create ' || case owner when 'PUBLIC ' then 'PUBLIC' else ' ' END || 'DATABASE LINK '|| db_link || ' CONNECT TO '|| username || ' IDENTIFIED BY ****** USING ''' || host || ''';' as create_sql from dba_db_links where db_link = '$objname' " $browfile
elif [ "$object_type" = "VIEW" -o \
       "$object_type" = "MATERIALIZED_VIEW" -o \
       "$object_type" = "PROCEDURE" -o \
       "$object_type" = "INDEX" -o \
       "$object_type" = "FUNCTION" -o \
       "$object_type" = "SEQUENCE" -o \
       "$object_type" = "SYNONYM" -o \
       "$object_type" = "TYPE" -o \
       "$object_type" = "TRIGGER" -o \
	   "$object_type" = "PROFILE" -o \
	   "$object_type" = "TABLESPACE" ];then
	nExecSql "SELECT DBMS_METADATA.GET_DDL('$object_type', '$objname')||';' as aaa FROM dual" $browfile
else
	echo "This database object is not supported[$object_type]" > $browfile
fi

kill -9 $!   > /dev/null 2>&1

#vim -u ~/user/zjw/bin/.vimrc.db $browfile
vim -u NONE -c "call oracle_tui#SetEnv()" $browfile
rm -f $browfile
exit
