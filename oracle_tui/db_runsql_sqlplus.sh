################################################################################
# 通过sqlplus执行sql(非管道模式)                                               #
################################################################################
if [ $# -ne 1 -a $# -ne 3 ];then
	echo "Usage:$0 sql [username] [password]"
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

set -o noglob
#~/user/zjw/bin/regsql $1
#echo "test:$1"

sqlstr="$1"
sqlstr_bak="$1"
sqlstr_bak=`echo $sqlstr_bak|sed 's/[ \t]*[Ff][Oo][Rr][ \t][ \t]*[Uu][Pp][Dd][Aa][Tt][Ee].*//g'`
#echo "sqlstr=[$sqlstr]"
echo "$sqlstr"|grep "/;[ \t]*$" > /dev/null 2>&1
if [ $? -ne 0 ];then
	sqlstr="$sqlstr;"
fi

echo "$sqlstr"|tr '' '\n' > ~/.dbtmp/$$.txt.sql   
sqlstr=`echo "$sqlstr"|tr '' '\n'`
sqlstr_bak=`echo "$sqlstr_bak"|tr '' '\n'`

echo "$1" |grep -i -E "^[ 	]*select|^[ 	]*with" >/dev/null 2>&1
if [ $? -eq 0 ];then
	sel_flag=1
else
	sel_flag=0
fi

#echo "$1" |grep -i -w -E "^[ \t]*drop|^[ \t]*insert|^[ \t]*update|^[ \t]*delete|^[ \t]*create|^[ \t]*alter|^[ \t]*declare|^[ \t]*set[ \t][ \t]*serveroutput[ \t][ \t]*on" >/dev/null 2>&1
#if [ $? -eq 0 ];then
#	sel_flag=0
#else
#	sel_flag=1
#fi

if [ $sel_flag -eq 1 ];then
	#如果有多条sql,sel_flag置为0
	more_flag=`echo "$sqlstr"|awk '{
		if (flag == 1 && $0 !~ /^[ \t]*$/)
		{
			#有多个sql
			print "1"
			exit
		}

		if ($0 ~ /;[ \t]*$/)
			flag = 1
		}'`

	if [ "$more_flag" = "1" ];then
		sel_flag=0
	fi
fi

vi_flag=1
#echo "$1" |grep -i -w -E "^[ \t]*drop|^[ \t]*insert|^[ \t]*update|^[ \t]*delete|^[ \t]*create|^[ \t]*alter" >/dev/null 2>&1
#if [ $? -eq 0 ];then
#	vi_flag=0
#else
#	vi_flag=1
#fi

kill_waitpid()
{
	echo "pid $! is killed!"
	#中断时会报进程不存在，可以不要下面这行
	kill -9 $! > /dev/null 2>&1
}      

trap "kill_waitpid" 2 3  

#echo "$sqlstr" > ~/.dbtmp/$$.txt.sql   

browfile=~/.dbtmp/$$.txt

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
if  command -v disown > /dev/null 2>&1 ;then
	disown $! 
fi


if [ $sel_flag -eq 1 ];then
	cat << EOF > $HOME/.dbtmp/$$.spl
	set serveroutput on; 
	DECLARE 
	    c NUMBER; 
	    d NUMBER; 
	    col_cnt INTEGER; 
	    rec_tab DBMS_SQL.DESC_TAB; 
	    col_num NUMBER; 
	BEGIN 
	    c := DBMS_SQL.OPEN_CURSOR; 
	    DBMS_SQL.PARSE(c, q'[$sqlstr_bak]', DBMS_SQL.NATIVE);
	    d := DBMS_SQL.EXECUTE(c); 
	    DBMS_SQL.DESCRIBE_COLUMNS(c, col_cnt, rec_tab); 
	 
	    FOR col_num IN 1..col_cnt LOOP 
	        DBMS_OUTPUT.PUT_LINE(rec_tab(col_num).col_name||'@'||rec_tab(col_num).col_type||'@'||rec_tab(col_num).col_max_len||'@'||rec_tab(col_num).col_precision||'@'||rec_tab(col_num).col_scale); 
	    END LOOP; 
	 
	    DBMS_SQL.CLOSE_CURSOR(c); 
	END; 
	/ 
EOF

	sqlplus -S $DBUSER/$DBPASS<<END >/dev/null
	set echo off;
	set linesize 300;
	set feedback off;
	set numwidth 20;
	set long 3000;
	set pagesize 200;
	set termout off;
	set trimout on;
	set heading on;
	set trimspool on;
	spool $HOME/.dbtmp/$$.desc
	@$HOME/.dbtmp/$$.spl
	spool off;
	exit
END
	file_len=$HOME/.dbtmp/$$.len
	set_col_file=$HOME/.dbtmp/${vimpid}_setcol.col
	cat $HOME/.dbtmp/$$.desc|awk -v file_len=$file_len \
	                             -v set_col_file=$set_col_file \
								 -F"@" '{ 
		if ($2 == 1 || $2 == 96) #char or varchar2/nchar or nvarchar2
		{
			arr_type[$1] = "C"

			if ($6 == 2)
			{
				#nchar/nvarchar2 长度要乘以2
				$3 = $3*2
			}

			if (length($1) < $3) 
				max_len=$3;
			else 
				max_len=length($1);

			arr_max[$1] = max_len 

			$3 = max_len
		}
		else if ($2 == 2) #number
		{
			if ($4 > 0 && $5 > 0)
			{
				arr_type[$1] = "N"

				if (length($1) < $4 + 1) 
					max_len=$4 + 1;
				else 
					max_len=length($1);

				if (length($1) > max_len) 
					max_len=length($1);

				arr_tot_len[$1] = max_len 

				arr_last_len[$1] = $5
			}
			else
			{
				if (length($1) > $3) 
					max_len=length($1);
				else
					max_len=$3
			}

			$3 = max_len 
		}
		else if ($2 == 12) #date
		{
			$3 = 30

			if (length($1) > $3) 
				$3=length($1);
		}
		else if ($2 == 208) #urowid
		{
			$3 = 30
			arr_type[$1] = "C"

			if (length($1) > $3) 
				max_len=length($1);

			$3 = max_len 

			arr_max[$1] = max_len
		}
		else if ($2 == 180) #timestamp
		{
			$3 = 150
		}
		else if ($2 == 181) #timestamp with time zone
		{
			$3 = 200
		}
		else if ($2 == 231) #timestamp with local time zone
		{
			$3 = 200
		}
		else if ($2 == 23) #raw
		{
			$3 = $3*2

			if (length($1) > $3) 
				$3=length($1);
		}
		else if ($2 == 100) #binary_float
		{
			$3 = 30

			if (length($1) > $3) 
				$3=length($1);
		}
		else if ($2 == 101) #binary_double
		{
			$3 = 30

			if (length($1) > $3) 
				$3=length($1);
		}
		else if ($2 == 182) #interval year to month
		{
			$3 = 80
		}
		else if ($2 == 183) #interval day to second
		{
			$3 = 80
		}
		else if ($2 == 8) #long 该类型$3为0
		{
			$3 = 1000
		}

		tot_len = tot_len + $3 + 2
	} 
	END { 
		for (colname in arr_type) 
		{
			if (arr_type[colname] == "C")
			{
				#set_str = ""
				set_str = sprintf("column %s format a%d", colname, arr_max[colname] )
			}
			else
			{
				set_str = sprintf("column %s format ", colname)

				for (i=1;i<arr_tot_len[colname] - arr_last_len[colname]; i++)
				{
					set_str = sprintf("%s%d", set_str, 9)
				}
				set_str = sprintf("%s%s", set_str ,"0.")
				for (i=1;i<=arr_last_len[colname]; i++)
				{
					set_str = sprintf("%s%d", set_str , 9)
				}
				#set_str = sprintf("%s%s", set_str , "\n")
			}
			print set_str >> set_col_file
		}
		#tot_len = tot_len + 100
		print tot_len > file_len
	}' 

	linesize=`cat $file_len`
	if [ $linesize -le 5000 ];then
		linesize=5000
	fi

	sqlplus -S $DBUSER/$DBPASS<<END >/dev/null
		@$set_col_file
		set timing on;
		set echo off;
		set linesize $linesize;
		set feedback on;
		set numwidth 20;
		set long 3000;
		set termout off;
		set trimout on;
		set heading on;
		set trimspool on;
		set pagesize 50000;
		spool $browfile;
		$sqlstr
		spool off;
		exit
END
	rm -f $HOME/.dbtmp/$$.spl
	rm -f $HOME/.dbtmp/$$.desc
	rm -f $set_col_file
	rm -f $HOME/.dbtmp/$$.len
else
	sqlplus -S $DBUSER/$DBPASS<<END  > /dev/null
		set timing on
		set echo on;
		set linesize 10000;
		set trimout on;
		set trimspool on;
		spool $browfile;
		@$HOME/.dbtmp/$$.txt.sql;
		spool off;
		exit
END
fi

kill -9 $!   > /dev/null 2>&1

if [ $vi_flag -eq 1 ]
then
	if [ $sel_flag -eq 1 ];then
		suc_flag=`sed -n '3p' $browfile|awk '{if ($0 ~ /^[- ][- ]*$/) print 1}'`
		if [ "$suc_flag" = "1" ];then
			vim -u NONE -c "call oracle_tui#SetLocal()|call oracle_tui#SetMapView()|call oracle_tui#ShowViewTitle()|call oracle_tui#SetAutocmdView()|set ve=all" $browfile
		else
			vim -u NONE -c "call oracle_tui#SetLocal()|call oracle_tui#SetMapView()|call oracle_tui#SetAutocmdView()|set ve=all" $browfile
		fi
	else
		vim -u NONE -c "call oracle_tui#SetLocal()|call oracle_tui#SetMapView()|call oracle_tui#SetAutocmdView()|set ve=all" $browfile
	fi
else
	cat $browfile
fi

rm -f $browfile
rm -f ~/.dbtmp/$$.txt.sql   

