################################################################################
#                            生成sql语句                                       #
#作者:臧建伟                                                                   #
################################################################################
set -o noglob

if [ $# -ne 1 -a $# -ne 3 ];then
	echo "Usage:`basename $0` file [username] [password]"
	exit
fi

file=$1
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

if [ ! -s $file ];then
	sqlfile=~/.dbtmp/.dbtmp-$$.sql
	echo "文件:${file}不存在" > $sqlfile
	vim -c "call oracle_tui#SetEnv()"  $sqlfile
	rm -f $sqlfile
	exit 
fi

sqlstr=`cat $1|tr '\n' ' '|sed 's/;[ 	]*$//'`

tabname=`echo "$sqlstr"|awk '{print tolower($0)}'|sed 's/where.*//'|sed 's/.*from[ 	][ 	]*\(.*\)/\1/'`
echo $tabname |grep ',' > /dev/null 2>&1
if [ $? -eq 0 ];then
	sqlfile=~/.dbtmp/.dbtmp-$$.sql
	echo "只能生成单个表的sql" > $sqlfile
	vim -c "call oracle_tui#SetEnv()" $sqlfile
	rm -f $sqlfile
	exit 
fi

tabname=`echo "$sqlstr"|awk '{print tolower($0)}'|sed 's/where.*//'|sed 's/.*from[ 	][ 	]*\(.*\)[ 	]*/\1/'|awk '{print $1}'`
tabname=`echo "$tabname"|sed "s/[ 	]*$//g"`

if [ ! -d ~/.dbtmp ];then
	mkdir -p ~/.dbtmp
fi

sqlfile=~/.dbtmp/${tabname}-$$.sql

nExec()
{
	suc_flag=1
	sql=$1
	> $HOME/.dbtmp/$$.spl
	cat <<EOF > $HOME/.dbtmp/$$.spl
	set serveroutput on; 
	DECLARE 
	    c NUMBER; 
	    d NUMBER; 
	    col_cnt INTEGER; 
	    rec_tab DBMS_SQL.DESC_TAB; 
	    col_num NUMBER; 
	    dig_len INTEGER; 
		l_ret NUMBER;
		n_value NUMBER;
		c_value VARCHAR2(30000);
		str VARCHAR2(30000);
		value VARCHAR2(30000);
		value2 VARCHAR2(30000);
		dig_str VARCHAR2(200);
	BEGIN 
	    c := DBMS_SQL.OPEN_CURSOR; 
	    DBMS_SQL.PARSE(c, q'[$sql]', DBMS_SQL.NATIVE);
	    d := DBMS_SQL.EXECUTE(c); 
	    DBMS_SQL.DESCRIBE_COLUMNS(c, col_cnt, rec_tab); 
	 
	    FOR col_num IN 1..col_cnt LOOP 
			IF rec_tab(col_num).col_type = 2 THEN
				DBMS_SQL.DEFINE_COLUMN(c, col_num, 0);
			ELSE
				DBMS_SQL.DEFINE_COLUMN(c, col_num, ' ', 4000);
			END IF;

	    END LOOP; 
	
		l_ret := DBMS_SQL.EXECUTE(c);
	
		WHILE DBMS_SQL.FETCH_ROWS(c) > 0 LOOP
			str := 'insert into $tabname values (';
			FOR col_num IN 1..col_cnt LOOP

				IF rec_tab(col_num).col_type = 2 THEN
					DBMS_SQL.COLUMN_VALUE(c, col_num, n_value);
					IF rec_tab(col_num).col_precision > 0 AND rec_tab(col_num).col_scale > 0 THEN
						dig_str := rpad('9',rec_tab(col_num).col_precision - rec_tab(col_num).col_scale - 1,'9')||'0.'||rpad('9',rec_tab(col_num).col_scale,'9');

						value := to_char(n_value, dig_str);
					ELSE
						value := to_char(n_value);
					END IF;

					value := trim(value);
					IF value is null THEN
						value := 'null';
					END IF;
				ELSE
					DBMS_SQL.COLUMN_VALUE(c, col_num, c_value);
					c_value := replace(c_value, '''', ''''||'''');
					IF rec_tab(col_num).col_type = 96 THEN
						if c_value is not null then
							c_value := rtrim(c_value);
							IF c_value is null THEN
								c_value := ' ';
							END IF;
						END IF;
					END IF;
					value := ''''||c_value||'''';
				END IF;
				IF col_num = 1 THEN
					str := str||value;
				ELSE
					str := str || ',' || value;
				END IF;
			END LOOP;
			str := str || ');';
			DBMS_OUTPUT.PUT_LINE(str);
		END LOOP;
	 
	    DBMS_SQL.CLOSE_CURSOR(c); 
	END; 
	/ 
EOF
	
	sqlplus -S $DBUSER/$DBPASS<<EOF >/dev/null
	set echo off;
	set feedback off;
	set heading off;
	set pagesize 0;
	set linesize 9000;
	set numwidth 17;
	set termout off;
	set trimout on;
	set trimspool on;
	set long 90000
	spool $2;
	@$HOME/.dbtmp/$$.spl
	spool off;
	exit
EOF
	rm -f $HOME/.dbtmp/$$.spl

	kill -9 $!   > /dev/null 2>&1
    if [ -s $2 ]; then
		grep "^ORA-" $2 > /dev/null 2>&1
		if [ $? -eq 0 ];then
    		#echo -e "Exe:$1 ... false!\n"
			#echo "================================================================================"
			#cat $2
			suc_flag=0
			return 1
		fi
    else
    	#echo -e "Exe:$1 ... no data!\n"
		#suc_flag=0
		#return 1
		echo "没有数据" > $sqlfile
		vim -c "call oracle_tui#SetEnv()" $sqlfile
		rm -f $sqlfile
		exit 
    fi

    return 0
}

kill_waitpid()
{
	echo "pid $! is killed!"
	kill -9 $! 
	int_flag=1
}      

int_flag=0
trap "kill_waitpid" 2 3  

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

nExec "$sqlstr" "$sqlfile"

if [ $suc_flag -ne 1 -a $int_flag -ne 1 ];then
	#获取真正的报错信息
	sqlplus -S $DBUSER/$DBPASS<<EOF >/dev/null
	set echo off;
	set feedback off;
	set heading off;
	set pagesize 0;
	set linesize 9000;
	set numwidth 17;
	set termout off;
	set trimout on;
	set trimspool on;
	set long 90000
	spool $sqlfile;
	$sqlstr;
	spool off;
	exit
EOF
	vim -c "call oracle_tui#SetEnv()" $sqlfile
	rm -f $sqlfile
	exit 
fi

if [ $int_flag -eq 1 ];then
	echo "请求被中断" > $sqlfile
	vim -c "call oracle_tui#SetEnv()" $sqlfile
	rm -f $sqlfile
	rm -f $HOME/.dbtmp/$$.spl
	exit 3
fi

vim -c "call oracle_tui#SetEnv()" $sqlfile
rm -f $sqlfile

exit 0
