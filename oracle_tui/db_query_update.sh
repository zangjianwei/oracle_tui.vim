################################################################################
#                     用于修改数据的数据库查询工具(通过管道)                   #
# 返回值说明:                                                                  #
# 0 成功                                                                       #
# 1 更新失败                                                                   #
# 2 LOADTOTABLE模式下不支持含有BLOB字段的修改                                  #
# 3 没有修改                                                                   #
# 4 数据库连接中断                                                             #
# 5 LC_CTYPE不为UTF-8                                                          #
# 6 LOADTOTABLE模式下处理文件出错                                              #
# 7 拷贝表出错                                                                 #
# 8 生成ctrl文件出错                                                           #
# 9 装载数据出错                                                               #
# 10 生成更新sql时awk语法错误                                                  #
# 11 生成更新sql错误                                                           #
# 12 sql语法错误                                                               #
# 13 操作被中断                                                                #
# 14 生成的pl/sql执行错误                                                      #
# 15 命令行参数错误                                                            #
#                                                                              #
# 不能用 DBMS_OUTPUT.PUT_LINE(v_chunk||''); 有的环境会丢掉             #
# 作者:臧建伟                                                                  #
################################################################################
set -o noglob

if [ $# -ne 1 ];then
	echo "Usage:`basename $0` vimpid"
	exit 15
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

#如果一行长度超过这个长度，对于lob字段写文件
#LOB_WRITEFILE_MAXLEN=100000
if [ "$LOB_WRITEFILE_MAXLEN" = "" ];then
	LOB_WRITEFILE_MAXLEN=-1
fi

vimpid=$1
dir=$HOME/.dbtmp
sqlfile=~/.dbtmp/$vimpid.txt.sql
pipe_in=~/.dbtmp/.pipe_in.$vimpid
pipe_out=~/.dbtmp/.pipe_out.$vimpid
sqlplus_pid_file=~/.dbtmp/.sqlplus_pid.$vimpid
#setfile=~/.dbtmp/set_$vimpid.sql
col_file=~/.dbtmp/${vimpid}_col.txt
procfile=$HOME/.dbtmp/${vimpid}_proc.sql
#spooltmpfile=$HOME/.dbtmp/${vimpid}_tmp.spool

cur_pid=$$
#SQL_BEGIN=SQL_BEGIN_$cur_pid
SQL_END=SQL_END_$cur_pid

#read_begin_flag=0
ReadPipe()
{
	while read -r line
	do
		#if [[ "$line" = "$SQL_BEGIN" ]];then
		#	read_begin_flag=1
		#	continue
		#fi

		#if [[ "$read_begin_flag" != "1" ]];then
		#	continue
		#fi

		if [[ "$line" = "$SQL_END" ]];then
			#read_begin_flag=0
			break
		fi
	done < $pipe_out 
}

sqlstr=`awk '{
	gsub(/--.*/,"",$0)

	if (NR > 1)
		printf("%s ", prev_line)
	prev_line = $0
	}
	END{
		gsub(/;[ \t]*$/, "", prev_line)
		printf("%s ", prev_line)
	}' $sqlfile`

tabname=`echo "$sqlstr"|awk '{print tolower($0)}'|sed 's/where.*//'|sed 's/.*from[ 	][ 	]*\(.*\)[ 	]*/\1/'|awk '{print $1}'`
tabname=`echo "$tabname"|sed "s/[ 	]*$//g"`
up_tabname=`echo $tabname|awk '{a=toupper($1);print a}'`

if [ ! -d ~/.dbtmp ];then
	mkdir -p ~/.dbtmp
fi

errfile=~/.dbtmp/p_${tabname}-$vimpid.txt.err
tmpfile=~/.dbtmp/p_${tabname}-$vimpid.txt.tmp
oldfile=~/.dbtmp/p_${tabname}-$vimpid.txt.old
newfile=~/.dbtmp/p_${tabname}-$vimpid.txt.new
#filename_tmp=~/.dbtmp/${tabname}-$vimpid.txt..dbtmp

if [ ! -p $pipe_in ];then
	rm -f $sqlfile
	exit 4
fi

sqlplus_pid=`cat $sqlplus_pid_file|awk '{print $1}'`
#pid2=`ps -ef|awk -v pid=$sqlplus_pid '{if ($2 == pid) print $2}'`
#if [ "$pid2" != "$sqlplus_pid" ];then
if ! kill -0 $sqlplus_pid 2>/dev/null; then
	rm -f $sqlfile
	exit 4
fi

FGF=""

ChgSql()
{
	sql2="$1"
	outfile2=$2
	echo "$sql2"|awk '{
		if (tolower($1) != "select")
		{
			print "没有select" >> "/dev/stderr"
			exit
		}
		colname = $2

		if (tolower($3)  !~ /from/)
		{
			print "没有from" >> "/dev/stderr"
			exit
		}

		#去掉前三列
		gsub(/^[ \t]*[^ \t]*[ \t][ \t]*[^ \t]*[ \t][ \t]*[^ \t]*[ \t][ \t]*/, "")

		line = $0
		i = gsub(/[ \t][ \t]*[Ff][Oo][Rr][ \t][ \t]*[Uu][Pp][Dd][Aa][Tt][Ee][ \t]*$/,"",line)
		if (i == 0)
		{
			print "没有for update" >> "/dev/stderr"
			exit
		}
		

		where_str = line
		if (where_str ~ /[ \t][ \t]*[Ww][Hh][Ee][Rr][Ee]/)
		{
			gsub(/.*[ \t][ \t]*[Ww][Hh][Ee][Rr][Ee]/,"where",where_str)

			gsub(/[ \t]*[Ww][Hh][Ee][Rr][Ee].*/,"",line)
		}
		else
		{
			if (where_str ~ /[ \t][ \t]*[Oo][Rr][Dd][Ee][Rr][ \t][ \t]*[Bb][Yy][ \t]/)
			{
				gsub(/.*[ \t][ \t]*[Oo][Rr][Dd][Ee][Rr][ \t][ \t]*[Bb][Yy]/,"order by ",where_str)
				gsub(/[ \t][ \t]*[Oo][Rr][Dd][Ee][Rr][ \t][ \t]*[Bb][Yy].*/,"",line)
			}
			else
			{
				where_str = ""
			}
		}
		#printf("where=[%s]\n", where_str)

		tabname = line

		#printf("tabname=[%s]\n", tabname);
		if (tabname ~/,/)
		{
			print "只能查询单个表" >> "/dev/stderr"
			exit
		}
		j = split(tabname, arr, " ")
		if (j > 2)
		{
			printf("查询表名错误[%s]\n", tabname)  >> "/dev/stderr"
			exit
		}

		tabname = arr[1]
		alias = arr[2]
		#printf("tab=[%s],alias=[%s]\n", tabname, alias)
		if (alias == "")
		{
			if (colname != "*")
			{
				printf("查询列表只能为*\n", alias) >> "/dev/stderr"
				exit
			}
			alias = "a"
		}
		else
		{
			if (colname != alias".*")
			{
				printf("查询列表只能为%s.*\n", alias) >> "/dev/stderr"
				exit
			}
		}
		colname = "*"
	
		selstr = sprintf("select rowid,%s.%s from %s %s %s for update", alias, colname, tabname, alias, where_str)
		print selstr
	}' 2>$outfile2

	if [ -s $outfile2 ];then
		return 1
	else
		return 0
	fi
}

newsql=`ChgSql "$sqlstr" $oldfile`
if [ $? -ne 0 ];then
	vim -c "set nonu" $oldfile
	rm -f $oldfile
	exit 12
fi

nExec()
{
	sql=`echo "$1"|sed "s/'/''/g"`
	sql="'$sql'"
	> $procfile
	cat <<EOF > $procfile
	set serveroutput on format wrapped; 
	DECLARE 
		type arr_len_type is table of int index by binary_integer;
		arr_len arr_len_type;
	    c NUMBER; 
	    d NUMBER; 
	    c2 NUMBER; 
	    d2 NUMBER; 
	    char_len NUMBER; 
		col_len NUMBER; 
		line_len NUMBER; 
	    col_cnt INTEGER; 
		all_space_flag INTEGER;
	    rec_tab DBMS_SQL.DESC_TAB; 
	    col_num NUMBER; 
	    dig_len INTEGER; 
	    rowid_len INTEGER; 
		l_ret NUMBER;
		n_value NUMBER;
		c_value VARCHAR2(32767);
		clob_value CLOB;
		blob_value BLOB;
		clob_str CLOB;
    	rowid_value    ROWID;
		line_str VARCHAR2(32767);
		value VARCHAR2(32767);
		value2 VARCHAR2(32767);
		dig_str VARCHAR2(200);
		sql_str1 VARCHAR2(500);
		v_length NUMBER;
		v_length2 NUMBER;
		v_start_pos NUMBER := 1;
		v_start_pos2 NUMBER := 1;
  		v_chunk_count NUMBER := 0;
  		v_chunk VARCHAR2(32767);
  		v_raw_chunk VARCHAR2(32767);
		lob_flag char(1);
		over_32767_flag char(1);
		cont_len NUMBER;
		max_line_len NUMBER;
		--不能定义成v_last_char VARCHAR2(1),否则会报错
		--v_last_char := SUBSTR(c_value, LENGTH(c_value), 1)
		--ORA-06502: PL/SQL: 数字或值错误 :  字符串缓冲区太小
		v_last_char VARCHAR2(1 CHAR);
	BEGIN 
		rowid_len := 18;
		max_line_len := 0;

		sql_str1 := $sql;

	    c := DBMS_SQL.OPEN_CURSOR; 
	    DBMS_SQL.PARSE(c, sql_str1, DBMS_SQL.NATIVE);
	    d := DBMS_SQL.EXECUTE(c); 
	    DBMS_SQL.DESCRIBE_COLUMNS(c, col_cnt, rec_tab); 
	 
		line_str := '';
		lob_flag := '0';
		line_len := 0;
	    FOR col_num IN 1..col_cnt LOOP 
			IF rec_tab(col_num).col_type = 2 THEN
				--number
				DBMS_SQL.DEFINE_COLUMN(c, col_num, n_value);

				IF rec_tab(col_num).col_precision > 0 AND rec_tab(col_num).col_scale > 0 THEN
					col_len := rec_tab(col_num).col_precision;
				ELSE
					col_len := 22;
				END IF;
			ELSIF rec_tab(col_num).col_type = 11 THEN
				--rowid
				DBMS_SQL.DEFINE_COLUMN_ROWID(c, col_num, rowid_value);
				col_len := rowid_len;
			ELSIF rec_tab(col_num).col_type = 23 THEN
				--raw
				DBMS_SQL.DEFINE_COLUMN(c, col_num, c_value,32767);

				col_len := rec_tab(col_num).col_max_len*2;
				arr_len(col_num) := col_len;
			ELSIF rec_tab(col_num).col_type = 112  THEN
				--clob
				DBMS_SQL.DEFINE_COLUMN(c, col_num, clob_value);
				lob_flag := '1';
				--arr_len(col_num) := length(clob_value);
				col_len := 0;
			ELSIF rec_tab(col_num).col_type = 8 THEN
				--long
				--DBMS_OUTPUT.PUT_LINE('不支持含有long字段类型的修改['||rec_tab(col_num).col_name||']');
				RAISE_APPLICATION_ERROR(-20999, '不支持含有long字段类型的修改['||rec_tab(col_num).col_name||']');
				return;
			ELSIF rec_tab(col_num).col_type = 113 THEN
				--blob
				DBMS_SQL.DEFINE_COLUMN(c, col_num, blob_value);
				lob_flag := '1';
				col_len := 0;
			ELSIF rec_tab(col_num).col_type = 24 THEN
				--long raw
				--DBMS_OUTPUT.PUT_LINE('不支持含有long raw字段类型的修改['||rec_tab(col_num).col_name||']');
				RAISE_APPLICATION_ERROR(-20999, '不支持含有long raw字段类型的修改['||rec_tab(col_num).col_name||']');
				return;
			ELSIF rec_tab(col_num).col_type = 114 THEN
				--BFILE 用于存储指向存储在数据库外部操作系统的二进制数据的定位器
				--DBMS_OUTPUT.PUT_LINE('不支持含有BFILE字段类型的修改['||rec_tab(col_num).col_name||']');
				RAISE_APPLICATION_ERROR(-20999, '不支持含有BFILE字段类型的修改['||rec_tab(col_num).col_name||']'); 
				return;
			ELSE
				IF rec_tab(col_num).col_type = 100 THEN 
					col_len := 30;
				ELSIF rec_tab(col_num).col_type = 101 THEN
					col_len := 30;
				ELSIF rec_tab(col_num).col_type = 182 THEN
					col_len := 20;
				ELSIF rec_tab(col_num).col_type = 183 THEN
					col_len := 30;
				ELSIF rec_tab(col_num).col_type = 12 THEN
					col_len := 19;
				ELSIF rec_tab(col_num).col_type = 208 THEN
					col_len := 30;
				ELSIF rec_tab(col_num).col_type = 180 THEN
					col_len := 75;
				ELSIF rec_tab(col_num).col_type = 181 THEN
					col_len := 75;
				ELSIF rec_tab(col_num).col_type = 231 THEN
					col_len := 75;
				ELSIF rec_tab(col_num).col_type = 1 THEN
					--varchar2/nvarchar2
					IF rec_tab(col_num).col_charsetform = 2 THEN
						col_len := rec_tab(col_num).col_max_len*2;
					ELSE
						col_len := rec_tab(col_num).col_max_len;
					END IF;
				ELSIF rec_tab(col_num).col_type = 96 THEN
					--char/nchar
					IF rec_tab(col_num).col_charsetform = 2 THEN
						col_len := rec_tab(col_num).col_max_len*2;
					ELSE
						col_len := rec_tab(col_num).col_max_len;
					END IF;
				ELSE
					RAISE_APPLICATION_ERROR(-20999, '不支持的字段类型:'||rec_tab(col_num).col_type); 
					return;
				END IF;

				--char/varchar/nchar/nvarchar2/date
				DBMS_SQL.DEFINE_COLUMN(c, col_num, c_value, 32767);
			END IF;
			line_len := line_len + greatest(lengthb(rec_tab(col_num).col_name), col_len);
	    END LOOP; 

		IF line_len > 32767 THEN
			over_32767_flag := '1';
		ELSE
			over_32767_flag := '0';
		END IF;

		IF lob_flag = '1' THEN
			DBMS_OUTPUT.PUT_LINE('LOB_FLAG=1');
		ELSIF over_32767_flag = '1' THEN
			DBMS_OUTPUT.PUT_LINE('OVER_32767_FLAG=1');
		END IF;

		IF lob_flag = '1' OR over_32767_flag = '1' THEN
			DBMS_LOB.CREATETEMPORARY(clob_str, TRUE);
		END IF;

	    FOR col_num IN 1..col_cnt LOOP 
			IF rec_tab(col_num).col_type = 2 THEN
				--number/float
				IF rec_tab(col_num).col_precision > 0 AND rec_tab(col_num).col_scale > 0 THEN
					dig_len := rec_tab(col_num).col_precision;
				ELSE
					dig_len := 22;
				END IF;

				IF lengthb(rec_tab(col_num).col_name)  >= dig_len + 2 THEN
					value := lpad(rec_tab(col_num).col_name, lengthb(rec_tab(col_num).col_name), ' ');
				ELSE
					value := lpad(rec_tab(col_num).col_name, dig_len + 2, ' ');
				END IF;
				DBMS_OUTPUT.PUT_LINE('DATATYPE:'||rec_tab(col_num).col_name||' '||rec_tab(col_num).col_type||' '||to_char(dig_len + 2)||' '||to_char(lengthb(rec_tab(col_num).col_name))||' '||rec_tab(col_num).col_charsetform);
			ELSIF rec_tab(col_num).col_type = 100 THEN
				--binary_float
				IF lengthb(rec_tab(col_num).col_name)  >= 30 THEN
					value := lpad(rec_tab(col_num).col_name, lengthb(rec_tab(col_num).col_name), ' ');
				ELSE
					value := lpad(rec_tab(col_num).col_name, 30, ' ');
				END IF;
				DBMS_OUTPUT.PUT_LINE('DATATYPE:'||rec_tab(col_num).col_name||' '||rec_tab(col_num).col_type||' '||'30'||' '||to_char(lengthb(rec_tab(col_num).col_name))||' '||rec_tab(col_num).col_charsetform);
			ELSIF rec_tab(col_num).col_type = 101 THEN
				--binary_double
				IF lengthb(rec_tab(col_num).col_name)  >= 30 THEN
					value := lpad(rec_tab(col_num).col_name, lengthb(rec_tab(col_num).col_name), ' ');
				ELSE
					value := lpad(rec_tab(col_num).col_name, 30, ' ');
				END IF;
				DBMS_OUTPUT.PUT_LINE('DATATYPE:'||rec_tab(col_num).col_name||' '||rec_tab(col_num).col_type||' '||'30'||' '||to_char(lengthb(rec_tab(col_num).col_name))||' '||rec_tab(col_num).col_charsetform);
			ELSIF rec_tab(col_num).col_type = 182 THEN
				--interval year to month
				IF lengthb(rec_tab(col_num).col_name) > 20 THEN
					value := rpad(rec_tab(col_num).col_name, lengthb(rec_tab(col_num).col_name), ' ');
				ELSE
					value := rpad(rec_tab(col_num).col_name, 20, ' ');
				END IF;
				DBMS_OUTPUT.PUT_LINE('DATATYPE:'||rec_tab(col_num).col_name||' '||rec_tab(col_num).col_type||' '||'20'||' '||to_char(lengthb(rec_tab(col_num).col_name))||' '||rec_tab(col_num).col_charsetform);
			ELSIF rec_tab(col_num).col_type = 183 THEN
				--interval day to second
				IF lengthb(rec_tab(col_num).col_name) > 30 THEN
					value := rpad(rec_tab(col_num).col_name, lengthb(rec_tab(col_num).col_name), ' ');
				ELSE
					value := rpad(rec_tab(col_num).col_name, 30, ' ');
				END IF;
				DBMS_OUTPUT.PUT_LINE('DATATYPE:'||rec_tab(col_num).col_name||' '||rec_tab(col_num).col_type||' '||'30'||' '||to_char(lengthb(rec_tab(col_num).col_name))||' '||rec_tab(col_num).col_charsetform);
			ELSIF rec_tab(col_num).col_type = 12 THEN
				--date
				IF lengthb(rec_tab(col_num).col_name) > 19 THEN
					value := rpad(rec_tab(col_num).col_name, lengthb(rec_tab(col_num).col_name), ' ');
				ELSE
					value := rpad(rec_tab(col_num).col_name, 19, ' ');
				END IF;
				DBMS_OUTPUT.PUT_LINE('DATATYPE:'||rec_tab(col_num).col_name||' '||rec_tab(col_num).col_type||' '||'19'||' '||to_char(lengthb(rec_tab(col_num).col_name))||' '||rec_tab(col_num).col_charsetform);
			ELSIF rec_tab(col_num).col_type = 208 THEN
				--urowid
				IF lengthb(rec_tab(col_num).col_name) > 30 THEN
					value := rpad(rec_tab(col_num).col_name, lengthb(rec_tab(col_num).col_name), ' ');
				ELSE
					value := rpad(rec_tab(col_num).col_name, 30, ' ');
				END IF;
				DBMS_OUTPUT.PUT_LINE('DATATYPE:'||rec_tab(col_num).col_name||' '||rec_tab(col_num).col_type||' '||'30'||' '||to_char(lengthb(rec_tab(col_num).col_name))||' '||rec_tab(col_num).col_charsetform);
			ELSIF rec_tab(col_num).col_type = 180 OR rec_tab(col_num).col_type = 181 OR rec_tab(col_num).col_type = 231 THEN
				--timestamp
				value := rpad(rec_tab(col_num).col_name, 75, ' ');
				DBMS_OUTPUT.PUT_LINE('DATATYPE:'||rec_tab(col_num).col_name||' '||rec_tab(col_num).col_type||' '||'75'||' '||to_char(lengthb(rec_tab(col_num).col_name))||' '||rec_tab(col_num).col_charsetform);
			ELSIF rec_tab(col_num).col_type = 23 THEN
				--raw
				IF lengthb(rec_tab(col_num).col_name) > arr_len(col_num) THEN
					value := rpad(rec_tab(col_num).col_name, length(rec_tab(col_num).col_name), ' ');
				ELSE
					value := rpad(rec_tab(col_num).col_name, arr_len(col_num), ' ');
				END IF;
				DBMS_OUTPUT.PUT_LINE('DATATYPE:'||rec_tab(col_num).col_name||' '||rec_tab(col_num).col_type||' '||to_char(arr_len(col_num))||' '||to_char(lengthb(rec_tab(col_num).col_name))||' '||rec_tab(col_num).col_charsetform);
			ELSIF rec_tab(col_num).col_type = 112 THEN
				--clob
				value := rpad(rec_tab(col_num).col_name, 40, ' ');
				DBMS_OUTPUT.PUT_LINE('DATATYPE:'||rec_tab(col_num).col_name||' '||rec_tab(col_num).col_type||' '||'0'||' '||to_char(lengthb(rec_tab(col_num).col_name))||' '||rec_tab(col_num).col_charsetform);
			ELSIF rec_tab(col_num).col_type = 8 THEN
				--long
				value := rpad(rec_tab(col_num).col_name, 40, ' ');
				DBMS_OUTPUT.PUT_LINE('DATATYPE:'||rec_tab(col_num).col_name||' '||rec_tab(col_num).col_type||' '||'0'||' '||to_char(lengthb(rec_tab(col_num).col_name))||' '||rec_tab(col_num).col_charsetform);
			ELSIF rec_tab(col_num).col_type = 113 THEN
				--blob
				value := rpad(rec_tab(col_num).col_name, 40, ' ');
				DBMS_OUTPUT.PUT_LINE('DATATYPE:'||rec_tab(col_num).col_name||' '||rec_tab(col_num).col_type||' '||'0'||' '||to_char(lengthb(rec_tab(col_num).col_name))||' '||rec_tab(col_num).col_charsetform);
			ELSIF rec_tab(col_num).col_type = 24 THEN
				--long raw
				value := rpad(rec_tab(col_num).col_name, 40, ' ');
				DBMS_OUTPUT.PUT_LINE('DATATYPE:'||rec_tab(col_num).col_name||' '||rec_tab(col_num).col_type||' '||'0'||' '||to_char(lengthb(rec_tab(col_num).col_name))||' '||rec_tab(col_num).col_charsetform);
			ELSIF rec_tab(col_num).col_type = 1 AND rec_tab(col_num).col_charsetform = 2 OR rec_tab(col_num).col_type = 96 AND rec_tab(col_num).col_charsetform = 2 THEN
				--nchar/nvarchar2
				char_len := rec_tab(col_num).col_max_len*2;
				IF lengthb(rec_tab(col_num).col_name) > char_len THEN
					value := rpad(rec_tab(col_num).col_name, lengthb(rec_tab(col_num).col_name), ' ');
				ELSE
					value := rpad(rec_tab(col_num).col_name, char_len, ' ');
				END IF;
				DBMS_OUTPUT.PUT_LINE('DATATYPE:'||rec_tab(col_num).col_name||' '||rec_tab(col_num).col_type||' '||to_char(char_len)||' '||to_char(lengthb(rec_tab(col_num).col_name))||' '||rec_tab(col_num).col_charsetform);
			ELSIF rec_tab(col_num).col_type = 11 THEN
				--rowid
				IF lengthb(rec_tab(col_num).col_name) > rowid_len THEN
					value := rpad(rec_tab(col_num).col_name, lengthb(rec_tab(col_num).col_name), ' ');
				ELSE
					value := rpad(rec_tab(col_num).col_name, rowid_len, ' ');
				END IF;
				DBMS_OUTPUT.PUT_LINE('DATATYPE:'||rec_tab(col_num).col_name||' '||rec_tab(col_num).col_type||' '||to_char(rowid_len)||' '||to_char(lengthb(rec_tab(col_num).col_name))||' '||rec_tab(col_num).col_charsetform);
			ELSE
				--char/varchar2
				IF lengthb(rec_tab(col_num).col_name) > rec_tab(col_num).col_max_len THEN
					value := rpad(rec_tab(col_num).col_name, lengthb(rec_tab(col_num).col_name), ' ');
				ELSE
					value := rpad(rec_tab(col_num).col_name, rec_tab(col_num).col_max_len, ' ');
				END IF;
				DBMS_OUTPUT.PUT_LINE('DATATYPE:'||rec_tab(col_num).col_name||' '||rec_tab(col_num).col_type||' '||to_char(rec_tab(col_num).col_max_len)||' '||to_char(lengthb(rec_tab(col_num).col_name))||' '||rec_tab(col_num).col_charsetform);
			END IF;

			IF lob_flag != '1' AND over_32767_flag != '1' THEN
				IF col_num = 1 THEN
            	    line_str := value;
            	ELSE
            	    line_str := line_str || '' || value;
            	END IF;
			ELSE
				IF col_num = 1 THEN
					IF value is not null THEN
						DBMS_LOB.WRITEAPPEND(clob_str, length(value), value);
					END IF;
				ELSE
					DBMS_LOB.WRITEAPPEND(clob_str, 1, '');
					IF value is not null THEN
						DBMS_LOB.WRITEAPPEND(clob_str, length(value), value);
					END IF;
				END IF;
			END IF;
	    END LOOP; 

		IF lob_flag != '1' AND over_32767_flag != '1' THEN
			--最后加行尾结束符,否则sqlplus的set trimspool on
			--会去掉尾部空格,造成字段空格丢失
			--在后面的文本处理时再把结束符去掉
        	DBMS_OUTPUT.PUT_LINE(line_str||CHR(2));
		ELSE
    		v_length := DBMS_LOB.GETLENGTH(clob_str);

			v_start_pos := 1;
			cont_len := 0;
        	WHILE v_start_pos <= v_length LOOP
        	    -- 从 CLOB 中读取指定长度的内容
        	    v_chunk := DBMS_LOB.SUBSTR(clob_str, 1000, v_start_pos);

        	    v_start_pos := v_start_pos + 1000;

				IF v_start_pos > v_length THEN
					--最后加行尾结束符,否则sqlplus的set trimspool on
					--会去掉尾部空格,造成字段空格丢失
					--在后面的文本处理时再把结束符去掉
        	    	DBMS_OUTPUT.PUT_LINE(v_chunk||CHR(2));
				ELSE
					--CHR(3)||CHR(25)||CHR(3) 是行尾连接符，代表一行未完
					--在文本处理时要连成一行
        	    	DBMS_OUTPUT.PUT_LINE(v_chunk||CHR(3)||CHR(25)||CHR(3));
				END IF;
				cont_len := cont_len + lengthb(v_chunk);
        	END LOOP;
			DBMS_LOB.FREETEMPORARY(clob_str);
		END IF;
	
		l_ret := DBMS_SQL.EXECUTE(c);
	
		WHILE DBMS_SQL.FETCH_ROWS(c) > 0 LOOP
			IF lob_flag = '1' OR over_32767_flag = '1' THEN
				DBMS_LOB.CREATETEMPORARY(clob_str, TRUE);
			END IF;

			line_str := '';
			FOR col_num IN 1..col_cnt LOOP
				all_space_flag := 0;

				IF rec_tab(col_num).col_type = 2 THEN
					--number
					DBMS_SQL.COLUMN_VALUE(c, col_num, n_value);
					IF rec_tab(col_num).col_precision > 0 AND rec_tab(col_num).col_scale > 0 THEN
						dig_str := rpad('9',rec_tab(col_num).col_precision - rec_tab(col_num).col_scale - 1,'9')||'0.'||rpad('9',rec_tab(col_num).col_scale,'9');

						value := to_char(n_value, dig_str);
						dig_len := rec_tab(col_num).col_precision;
					ELSE
						value := to_char(n_value);
						dig_len := 22;
					END IF;

					IF value is null THEN
						value := ' ';
					END IF;

				    IF lengthb(rec_tab(col_num).col_name) >= dig_len+2 THEN
				    	value := lpad(value, lengthb(rec_tab(col_num).col_name), ' ');
				    ELSE
				    	value := lpad(value, dig_len+2, ' ');
				    END IF;
				ELSIF rec_tab(col_num).col_type = 12 THEN
					--date type
					DBMS_SQL.COLUMN_VALUE(c, col_num, c_value);
					if c_value is null then
						c_value := ' ';
					end if;
                
					value := c_value;
                
					IF lengthb(rec_tab(col_num).col_name) > 19 THEN
						value := rpad(value, lengthb(rec_tab(col_num).col_name), ' ');
					ELSE
						value := rpad(value, 19, ' ');
					END IF;
				ELSIF rec_tab(col_num).col_type = 208 THEN
					--urowid type
					DBMS_SQL.COLUMN_VALUE(c, col_num, c_value);
					if c_value is null then
						c_value := ' ';
					end if;
                
					value := c_value;
                
					IF lengthb(rec_tab(col_num).col_name) > 30 THEN
						value := rpad(value, lengthb(rec_tab(col_num).col_name), ' ');
					ELSE
						value := rpad(value, 30, ' ');
					END IF;
				ELSIF rec_tab(col_num).col_type = 182 THEN
					--interval year to month
					DBMS_SQL.COLUMN_VALUE(c, col_num, c_value);
					if c_value is null then
						c_value := ' ';
					end if;
                
					value := c_value;
                
					IF lengthb(rec_tab(col_num).col_name) > 20 THEN
						value := rpad(value, lengthb(rec_tab(col_num).col_name), ' ');
					ELSE
						value := rpad(value, 20, ' ');
					END IF;
				ELSIF rec_tab(col_num).col_type = 183 THEN
					--interval day to second
					DBMS_SQL.COLUMN_VALUE(c, col_num, c_value);
					if c_value is null then
						c_value := ' ';
					end if;
                
					value := c_value;
                
					IF lengthb(rec_tab(col_num).col_name) > 30 THEN
						value := rpad(value, lengthb(rec_tab(col_num).col_name), ' ');
					ELSE
						value := rpad(value, 30, ' ');
					END IF;
				ELSIF rec_tab(col_num).col_type = 180 OR rec_tab(col_num).col_type = 181 OR rec_tab(col_num).col_type = 231 THEN
					--timestamp type
					DBMS_SQL.COLUMN_VALUE(c, col_num, c_value);
					if c_value is null  then
						c_value := ' ';
					end if;
                
					value := c_value;
                
					value := rpad(value, 75, ' ');
				ELSIF rec_tab(col_num).col_type = 100 OR rec_tab(col_num).col_type = 101 THEN
					--binary_float,binary_double
					DBMS_SQL.COLUMN_VALUE(c, col_num, c_value);
					if rtrim(c_value) is null then
						c_value := ' ';
					end if;

					value := c_value;

					IF lengthb(rec_tab(col_num).col_name) > 30 THEN
						value := lpad(value, lengthb(rec_tab(col_num).col_name) , ' ');
					ELSE
						value := lpad(value, 30, ' ');
					END IF;
				ELSIF rec_tab(col_num).col_type = 23 THEN
					--raw
					DBMS_SQL.COLUMN_VALUE(c, col_num, c_value);
					if c_value is null then
						c_value := ' ';
					end if;

					value := c_value;

					IF lengthb(rec_tab(col_num).col_name) > arr_len(col_num) THEN
						value := rpad(value, lengthb(rec_tab(col_num).col_name), ' ');
					ELSE
						value := rpad(value, arr_len(col_num), ' ');
					END IF;
				ELSIF rec_tab(col_num).col_type = 112 THEN
					--clob
					DBMS_SQL.COLUMN_VALUE(c, col_num, clob_value);
					clob_value := replace(clob_value, chr(10), '');
				ELSIF rec_tab(col_num).col_type = 8 THEN
					--long
					DBMS_SQL.COLUMN_VALUE(c, col_num, clob_value);
					clob_value := replace(clob_value, chr(10), '');
				ELSIF rec_tab(col_num).col_type = 113 THEN
					--blob
					DBMS_SQL.COLUMN_VALUE(c, col_num, blob_value);
				ELSIF rec_tab(col_num).col_type = 24 THEN
					--long raw
					DBMS_SQL.COLUMN_VALUE(c, col_num, blob_value);
				ELSIF rec_tab(col_num).col_type = 96 THEN
					--char/nchar
					DBMS_SQL.COLUMN_VALUE(c, col_num, c_value);
					if c_value is null then
						c_value := chr(1);
					else
						if trim(c_value) is null then
							--都是空格,保留一个空格
							c_value := ' ';
							all_space_flag := 1;
						else
							--去掉后面空格
							c_value := rtrim(c_value);
							IF INSTR(c_value, '') > 0 THEN
								--DBMS_OUTPUT.PUT_LINE('字段值:'||c_value||'含有字符,不能修改!');
								RAISE_APPLICATION_ERROR(-20999,  '字段值:'||c_value||'含有字符,不能修改!'); 
								return;
							END IF;

							v_last_char := SUBSTR(c_value, -1);
							IF v_last_char = chr(1) THEN
								RAISE_APPLICATION_ERROR(-20999,  '字段值:'||c_value||'最后一位ascii码是1,不能修改!'); 
								return;
							END IF;
							IF v_last_char = UNISTR('\00A0') THEN
								RAISE_APPLICATION_ERROR(-20999,  '字段值:'||c_value||'最后一位是NBSP,不能修改!'); 
								return;
							END IF;
						end if;
					end if;

					--替换回车符
					value := replace(c_value, chr(10), '');

					if rec_tab(col_num).col_charsetform = 2 then
						char_len := rec_tab(col_num).col_max_len * 2;
					else
						char_len := rec_tab(col_num).col_max_len;
					end if;

					IF all_space_flag != 1 THEN
						--用空字符填充右面字符
						IF lengthb(rec_tab(col_num).col_name) > char_len THEN
							value := rpad(value, lengthb(rec_tab(col_num).col_name), chr(1));
						ELSE
							value := rpad(value, char_len, chr(1));
						END IF;
					ELSE
						--用空格填充右面字符
						IF lengthb(rec_tab(col_num).col_name) > char_len THEN
							value := rpad(value, lengthb(rec_tab(col_num).col_name), ' ');
						ELSE
							value := rpad(value, char_len, ' ');
						END IF;
					END IF;
				ELSIF rec_tab(col_num).col_type = 1 THEN
					--varchar2/nvarchar2
					DBMS_SQL.COLUMN_VALUE(c, col_num, c_value);

					IF INSTR(c_value, '') > 0 THEN
						--DBMS_OUTPUT.PUT_LINE(rowid_value||'$FGF'||c_value||'含有字符,不能修改!');
						RAISE_APPLICATION_ERROR(-20999,  '字段值:'||c_value||'含有字符,不能修改!'); 
						return;
					END IF;

					v_last_char := SUBSTR(c_value, -1);
					IF v_last_char = chr(1) THEN
						RAISE_APPLICATION_ERROR(-20999,  '字段值:'||c_value||'最后一位ascii码是1,不能修改!'); 
						return;
					END IF;
					IF v_last_char = UNISTR('\00A0') THEN
						RAISE_APPLICATION_ERROR(-20999,  '字段值:'||c_value||'最后一位是NBSP,不能修改!'); 
						return;
					END IF;

					if c_value is null then
						--空值用ascii=1字符代替
						c_value := chr(1);
					end if;

					--替换回车符
					value := replace(c_value, chr(10), '');

					if rec_tab(col_num).col_charsetform = 2 then
						char_len := rec_tab(col_num).col_max_len * 2;
					else
						char_len := rec_tab(col_num).col_max_len;
					end if;

					--用ascii=1字符填充右面字符
					--在文本处理时再把ascii=1字符替换成NBSP字符
					IF lengthb(rec_tab(col_num).col_name) > char_len THEN
						value := rpad(value, lengthb(rec_tab(col_num).col_name), chr(1));
					ELSE
						value := rpad(value, char_len, chr(1));
					END IF;
				ELSIF rec_tab(col_num).col_type = 11 THEN
					--rowid
					DBMS_SQL.COLUMN_VALUE(c, col_num, rowid_value);

					--替换回车符
					value := rowid_value;

					char_len := rowid_len;

					--用空格填充右面字符
					IF lengthb(rec_tab(col_num).col_name) > char_len THEN
						value := rpad(value, lengthb(rec_tab(col_num).col_name), ' ');
					ELSE
						value := rpad(value, char_len, ' ');
					END IF;
				ELSE
					--value := '不支持的数据类型:'||rec_tab(col_num).col_type;
					RAISE_APPLICATION_ERROR(-20999, '不支持的字段类型:'||rec_tab(col_num).col_type); 
					return;
				END IF;
				
				IF lob_flag != '1' AND over_32767_flag != '1' THEN
					IF col_num = 1 THEN
                	    line_str := value;
                	ELSE
                	    line_str := line_str || '$FGF' || value;
                	END IF;
				ELSE
					IF col_num = 1 THEN
						IF rec_tab(col_num).col_type = 112 OR rec_tab(col_num).col_type = 8 THEN --clob long
    						v_length2 := DBMS_LOB.GETLENGTH(clob_value);


							v_start_pos2 := 1;
        					WHILE v_start_pos2 <= v_length2 LOOP
        					    v_chunk := DBMS_LOB.SUBSTR(clob_value, 10000, v_start_pos2);

								IF INSTR(v_chunk, '') > 0 THEN
									RAISE_APPLICATION_ERROR(-20999,  '字段:'||rec_tab(col_num).col_name||'含有字符,不能修改!'); 
									return;
								END IF;

								DBMS_LOB.WRITEAPPEND(clob_str, length(v_chunk), v_chunk);

        					    v_start_pos2 := v_start_pos2 + 10000;
        					END LOOP;

							v_last_char := SUBSTR(v_chunk, -1);
							IF v_last_char = chr(1) THEN
								RAISE_APPLICATION_ERROR(-20999,  '字段:'||rec_tab(col_num).col_name||'最后一位ascii码是1,不能修改!'); 
								return;
							END IF;

							IF v_last_char = UNISTR('\00A0') THEN
								RAISE_APPLICATION_ERROR(-20999,  '字段:'||rec_tab(col_num).col_name||'最后一位是NBSP,不能修改!'); 
								return;
							END IF;
						ELSIF rec_tab(col_num).col_type = 113 THEN --blob
    						v_length2 := DBMS_LOB.GETLENGTH(blob_value);


							v_start_pos2 := 1;
        					WHILE v_start_pos2 <= v_length2 LOOP
        					    v_raw_chunk := DBMS_LOB.SUBSTR(blob_value, 10000, v_start_pos2);
								v_chunk := RAWTOHEX(v_raw_chunk);
								DBMS_LOB.WRITEAPPEND(clob_str, length(v_chunk), v_chunk);

        					    v_start_pos2 := v_start_pos2 + 10000;
        					END LOOP;
						ELSIF rec_tab(col_num).col_type = 24 THEN --long raw
    						v_length2 := DBMS_LOB.GETLENGTH(blob_value);


							v_start_pos2 := 1;
        					WHILE v_start_pos2 <= v_length2 LOOP
        					    v_raw_chunk := DBMS_LOB.SUBSTR(blob_value, 10000, v_start_pos2);
								v_chunk := RAWTOHEX(v_raw_chunk);
								DBMS_LOB.WRITEAPPEND(clob_str, length(v_chunk), v_chunk);

        					    v_start_pos2 := v_start_pos2 + 10000;
        					END LOOP;
						ELSE
							IF value is not null THEN
								DBMS_LOB.WRITEAPPEND(clob_str, length(value), value);
							END IF;
						END IF;
					ELSE
						IF rec_tab(col_num).col_type = 112 OR rec_tab(col_num).col_type = 8 THEN --clob long
							DBMS_LOB.WRITEAPPEND(clob_str, 1, '$FGF');

    						v_length2 := DBMS_LOB.GETLENGTH(clob_value);


							v_start_pos2 := 1;
        					WHILE v_start_pos2 <= v_length2 LOOP
        					    v_chunk := DBMS_LOB.SUBSTR(clob_value, 10000, v_start_pos2);
								IF INSTR(v_chunk, '') > 0 THEN
									RAISE_APPLICATION_ERROR(-20999,  '字段:'||rec_tab(col_num).col_name||'含有字符,不能修改!'); 
									return;
								END IF;

								DBMS_LOB.WRITEAPPEND(clob_str, length(v_chunk), v_chunk);

        					    v_start_pos2 := v_start_pos2 + 10000;
        					END LOOP;
							v_last_char := SUBSTR(v_chunk, -1);
							IF v_last_char = chr(1) THEN
								RAISE_APPLICATION_ERROR(-20999,  '字段:'||rec_tab(col_num).col_name||'最后一位ascii码是1,不能修改!'); 
								return;
							END IF;

							IF v_last_char = UNISTR('\00A0') THEN
								RAISE_APPLICATION_ERROR(-20999,  '字段:'||rec_tab(col_num).col_name||'最后一位是NBSP,不能修改!'); 
								return;
							END IF;
						ELSIF rec_tab(col_num).col_type = 113 THEN --blob
							DBMS_LOB.WRITEAPPEND(clob_str, 1, '$FGF');

    						v_length2 := DBMS_LOB.GETLENGTH(blob_value);


							v_start_pos2 := 1;
        					WHILE v_start_pos2 <= v_length2 LOOP
        					    v_raw_chunk := DBMS_LOB.SUBSTR(blob_value, 10000, v_start_pos2);
								v_chunk := RAWTOHEX(v_raw_chunk);
								DBMS_LOB.WRITEAPPEND(clob_str, length(v_chunk), v_chunk);

        					    v_start_pos2 := v_start_pos2 + 10000;
        					END LOOP;
						ELSIF rec_tab(col_num).col_type = 24 THEN --long raw
							DBMS_LOB.WRITEAPPEND(clob_str, 1, '$FGF');

    						v_length2 := DBMS_LOB.GETLENGTH(blob_value);


							v_start_pos2 := 1;
        					WHILE v_start_pos2 <= v_length2 LOOP
        					    v_raw_chunk := DBMS_LOB.SUBSTR(blob_value, 10000, v_start_pos2);
								v_chunk := RAWTOHEX(v_raw_chunk);
								DBMS_LOB.WRITEAPPEND(clob_str, length(v_chunk), v_chunk);

        					    v_start_pos2 := v_start_pos2 + 10000;
        					END LOOP;
						ELSE
							DBMS_LOB.WRITEAPPEND(clob_str, 1, '$FGF');
							IF value is not null THEN
								DBMS_LOB.WRITEAPPEND(clob_str, length(value), value);
							END IF;
						END IF;
					END IF;
				END IF;
			END LOOP;

			IF lob_flag != '1' AND over_32767_flag != '1' THEN
				--最后加行尾结束符,否则sqlplus的set trimspool on
				--会去掉尾部空格,造成字段空格丢失
				--在后面的文本处理时再把结束符去掉
        		DBMS_OUTPUT.PUT_LINE(line_str||CHR(2));
			ELSE
    			v_length := DBMS_LOB.GETLENGTH(clob_str);

				v_start_pos := 1;
				cont_len := 0;
        		WHILE v_start_pos <= v_length LOOP
        		    -- 从 CLOB 中读取指定长度的内容
        		    v_chunk := DBMS_LOB.SUBSTR(clob_str, 1000, v_start_pos);

        		    v_start_pos := v_start_pos + 1000;

					IF v_start_pos > v_length THEN
						--最后加行尾结束符,否则sqlplus的set trimspool on
						--会去掉尾部空格,造成字段空格丢失
						--在后面的文本处理时再把结束符去掉
        		    	DBMS_OUTPUT.PUT_LINE(v_chunk||CHR(2));
					ELSE
						--CHR(3)||CHR(25)||CHR(3) 是行尾连接符，代表一行未完
						--在文本处理时要连成一行
        		    	DBMS_OUTPUT.PUT_LINE(v_chunk||CHR(3)||CHR(25)||CHR(3));
					END IF;
					cont_len := cont_len + lengthb(v_chunk);
        		END LOOP;
				DBMS_LOB.FREETEMPORARY(clob_str);

				IF cont_len > max_line_len THEN
					max_line_len := cont_len;
				END IF;
			END IF;
		END LOOP;

		IF lob_flag = '1' OR over_32767_flag = '1' THEN
        	DBMS_OUTPUT.PUT_LINE('MAX_LINE_LEN='||max_line_len);
		END IF;
	 
	    DBMS_SQL.CLOSE_CURSOR(c); 
	END; 
	/ 
EOF
	
	ReadPipe&
	read_pid=$!
	(
		#强制刷新输出,否则像输入seect from tabname 则没有输出,输入set heading off也不会有输出
		#echo "store set $setfile"
		echo "SQL_START"
		#echo "prompt $SQL_BEGIN;"
		echo "set echo off;"
		echo "set timing off;"
		echo "set feedback off;"
		echo "set heading off;"
		echo "set pagesize 0;"
		echo "set linesize 32767;"
		#echo "set numwidth 20;"
		echo "set termout off;"
		echo "set trimout on;"
		echo "set trimspool on;"
		#echo "set long 90000"
		#echo "spool off;"
		#echo "exec dbms_output.put_line('SQL_START');" 
		echo "spool $2;"
		echo "@$procfile;"
		echo "spool off;"
		#echo "@$setfile;"
		echo "prompt $SQL_END;"
	) > $pipe_in

	#下面中断判断没用
	#if [ $int_flag -eq 1 ];then
	#	echo "用户中断了请求2" > $oldfile
	#	#vim -u ~/user/zjw/bin/.vimrc.db $oldfile
	#	vim -c "set nonu" $oldfile
	#	rm -f $oldfile
	#	rm -f $setfile
	#	rm -f $procfile
	#	exit 3
	#fi

	#while read -r line
	#do
	#	if [[ "$line" = "$SQL_END" ]];then
	#		break
	#	fi
	#done < $pipe_out 

	wait $read_pid

	if [ $int_flag -eq 1 ];then
		kill -9 $read_pid > /dev/null 2>&1
	else
		kill -9 $bg_pid   > /dev/null 2>&1
	fi

	#rm -f $procfile

    if [ -s $2 ]; then
		#grep "^第.*行出现错误:" $2 > /dev/null 2>&1
		grep -E "^ORA-|^SP2-" $2 > /dev/null 2>&1
		if [ $? -eq 0 ];then
			retcode=1
		else
			retcode=0
		fi
	else
		retcode=1
    fi

    return $retcode
}

kill_waitpid()
{
	#echo "pid $bg_pid is killed!"
	kill -9 $bg_pid 

	#中断当前正在运行的sql
	kill -INT $sqlplus_pid

	#必须加下面内容清空缓冲区，否则下次查询时如果查询结果用spool file输出
	#到文件，则会把本次残留的缓冲区也输出到文件
	#只有匿名块中调用DBMS_OUTPUT.PUT_LINE会存在问题，调用sql则不会有问题
	(
		echo "SQL_START" 
		echo "BEGIN " 
		echo "DBMS_OUTPUT.DISABLE;" 
		echo "DBMS_OUTPUT.ENABLE;"
		echo "END;"
		echo "/" 
	) > $pipe_in

	int_flag=1
}      

kill_waitpid_file()
{
	#echo "pid $file_bg_pid is killed!"
	#不需要下面这行，会提示进程不存在
	kill -9 $file_bg_pid > /dev/null 2>&1

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
	    #echo -e "\033[12;10H $prompt_str...${str[$n]}"
	    printf "\033[12;10H $prompt_str...${str[$n]} \n"
		n=`echo $n|awk '{print ($0+1)%5}'`
	    if [ $n -eq 0 ]; then
	         n=1
	    fi
	    sleep 1
	done 
}

prompt_str="Executing SQL,You can press Ctrl+c to interrupt"
rotate &   
bg_pid=$!
#从作业表中移除,否则会显示:31477 Killed                  rotate
if  command -v disown > /dev/null 2>&1 ;then
	disown $bg_pid
fi

nExec "$newsql" "$tmpfile"
suc_flag=$?
#rm -f $setfile

#下面这段必须要，否则要冲断两次才能退出 
if [ $int_flag -eq 1 ];then
	#echo "用户中断了请求" > $oldfile
	#echo " Request be interupted" > $oldfile
	#echo "  请求被中断" > $oldfile
	#vim -u ~/user/zjw/bin/.vimrc.db $oldfile
	#vim -c "set nonu" $oldfile
	#rm -f $setfile
	rm -f $oldfile
	rm -f $procfile
	rm -f $sqlfile
	rm -f $tmpfile
	exit 13
fi

if [ $suc_flag -ne 0 ];then
	#去掉for update可能就不报错,比如没有修改权限问题
	##获取真正的报错信息
	#sqlplus -S $DBUSER/$DBPASS<<EOF >/dev/null
	#set echo off;
	#set feedback off;
	#set heading off;
	#set pagesize 0;
	#set linesize 20000;
	#--set numwidth 20;
	#set termout off;
	#set trimout on;
	#set trimspool on;
	#--set long 90000
	#spool $oldfile;
	#$newsql;
	#spool off;
	#exit
	#EOF
	#vim -u ~/user/zjw/bin/.vimrc.db $oldfile
	#if [ -s $oldfile ];then
	#	vim -c "set nonu" $oldfile
	#else
	#	vim -c "set nonu" $tmpfile
	#fi
	#rm -f $setfile
	#grep -E "^ORA-|^SP2-" $tmpfile > $errfile
	#if [ -s $errfile ];then
	#	vim -c "set nonu" $errfile
	#else
	#	vim -c "set nonu" $tmpfile
	#fi

	vim -c "set nonu" $tmpfile
	rm -f $errfile
	rm -f $oldfile
	rm -f $procfile
	rm -f $sqlfile
	rm -f $tmpfile
	exit 14
fi

line=`sed -n '1p' $tmpfile`
#echo "$line"|grep -E "^不支持|^字段值:.*不能修改" > /dev/null 2>&1
#grep -E "^不支持|^字段值:.*不能修改" $tmpfile > $errfile
#if [ -s $errfile ];then
#	vim -c "set nonu" $errfile
#	rm -f $tmpfile
#	rm -f $errfile
#	rm -f $sqlfile
#	rm -f $oldfile
#	exit 3
#else
#	rm -f $errfile
#fi

#如果一行长度超过100000,vim编辑器按l,h移动光标会变得很慢
grep "^DATATYPE:" $tmpfile|sed 's/^DATATYPE://g' > $col_file

grep -v "^DATATYPE:" $tmpfile |grep -v -E "^LOB_FLAG=1|^OVER_32767_FLAG=1|^MAX_LINE_LEN=" > $oldfile
cp $oldfile $newfile

if [ "$line" = "LOB_FLAG=1" ];then
	data_len=`sed -n '$p' $tmpfile|grep "^MAX_LINE_LEN="|awk -F"=" '{print $2}'`
	if [ "$data_len" = "" ];then
		data_len=0
	fi
fi

if [ "$line" = "LOB_FLAG=1" ];then
	#如果是有clob字段并且数据装在方式不为ONLY_SQL时，文件名称开头为p_c_
	result_oldfile=~/.dbtmp/p_c_${tabname}-$vimpid.txt.old
	result_newfile=~/.dbtmp/p_c_${tabname}-$vimpid.txt.new
	shortfile="p_c_${tabname}-$vimpid"
else
	result_oldfile=$oldfile
	result_newfile=$newfile
	shortfile="p_${tabname}-$vimpid"
fi

if [ "$line" = "LOB_FLAG=1" -o "$line" = "OVER_32767_FLAG=1" ];then
	trap "kill_waitpid_file" 2 3  
	prompt_str="Data is being processed,You can press Ctrl+c to interrupt"
	rotate &   
	file_bg_pid=$!
	#从作业表中移除,否则会显示:31477 Killed                  rotate
	#disown $file_bg_pid
	if  command -v disown > /dev/null 2>&1 ;then
		disown $file_bg_pid
	fi

	oldfile2=~/.dbtmp/p_c_${tabname}-$vimpid.txt.old
	newfile2=~/.dbtmp/p_c_${tabname}-$vimpid.txt.new

	>$oldfile.tmp
	>$col_file.tmp
	awk -v fgf=$FGF -v col_file=$col_file -v outfile=$oldfile.tmp \
	    -v dir=$dir \
		-v vimpid=$vimpid \
	    -v model=$DBCLI_UPDATE_MODEL 'function AlignStr(leng,in_str,type,flag)
	{
		str = sprintf("%*s", leng-length(in_str), "");

		if (flag == "l")
			outstr = sprintf("%s%s", str, in_str);
		else
			outstr = sprintf("%s%s", in_str, str);

		return outstr
	}
	BEGIN{
		line = ""
		linenum = 0

		i = 0;
		while (getline < col_file)
		{
			i++

			arr_name[i] = $1
			arr_type[i] = $2
			arr_cont_len[i] = $3
			arr_name_len[i] = $4
			arr_charset[i] = $5

			if ($2 == 2 || $2 == 100 || $2 == 101)
				arr_align[i] = "l"
			else
				arr_align[i] = "r"

		}
    	FS=OFS=fgf
	}
	{
		#去掉行尾结束符
		gsub(/$/,"",$0)

		#将有行尾连接符的行连成一行
		if ($0 ~ /$/)
		{
			gsub(/$/,"",$0)
			line = sprintf("%s%s", line, $0)
		}
		else
		{
			line = sprintf("%s%s", line, $0)
			$0 = line
			line = ""
			linenum++

    		for (i=1;i<=NF;i++)
    		{
				#clob/blob字段要写入文件
				if (arr_type[i] == 112 \
					|| arr_type[i] == 8 \
					|| arr_type[i] == 113 \
					|| arr_type[i] == 24)
				{
					if (linenum > 1)
					{
						if (length($i) > 0)
						{
							lob_file_name_withdir = sprintf("%s/lob_%s_%d_%d.txt.old", dir, vimpid, linenum-1, i-1)
							lob_file_name = sprintf("<lob_%s_%d_%d.txt.old>", vimpid, linenum-1, i-1)
							content = gsub(//, "\n", $i)
							printf("%s", $i) > lob_file_name_withdir
							#$i = sprintf("%-40s", lob_file_name);
							$i = AlignStr(40, lob_file_name, arr_type[i], "r")
							#$i = lob_file_name
						}
						else
						{
							$i = "                                        "
						}
					}
				}

    		    arr[linenum,i] = $i
    		}

    		num=NF
		}
	}
	END{
    	for (n=1;n<=num;n++)
    	{
			if (arr_type[n] != 112 \
				&& arr_type[n] != 8 \
				&& arr_type[n] != 113 \
				&& arr_type[n] != 24)
			{
				len[n] = arr_cont_len[n]
			}
			else
			{
				len[n] = 40
			}

    	    line_str = sprintf("%s %s %s %s %s",
				arr_name[n],
				arr_type[n],
				len[n],
				arr_name_len[n],
				arr_charset[n])
			print line_str >> col_file".tmp"
    	}

    	for (i=1;i<=linenum;i++)
    	{
			full_line_str = ""
    	    for (j=1;j<=num;j++)
    	    {
				unit_str = arr[i,j]
				#varchar 替换为NBSP
				if (arr_type[j] == 1 || arr_type[j] == 96)
				{
    	    		if(match(unit_str, /*$/)) 
					{
    	    		    str1 = substr(unit_str, 1, RSTART-1)
    	    		    str2 = substr(unit_str, RSTART)
    	    		    gsub(//, " ", str2)
    	    		    unit_str = str1 str2
					}
				}

				if (j == num)
    	        	full_line_str = sprintf("%s%s",full_line_str, unit_str);
				else
    	        	full_line_str = sprintf("%s%s%s",full_line_str, unit_str,fgf);
    	    }
    	    print full_line_str >> outfile
    	}
	}' $oldfile

	if [ $int_flag -eq 1 ];then
		#echo "用户中断了请求" > $oldfile
		#echo " Request be interupted" > $oldfile
		echo "  请求被中断" > $oldfile
		vim -c "set nonu" $oldfile
		rm -f $procfile
		rm -f $result_oldfile
		rm -f $result_newfile
		rm -f $oldfile
		rm -f $newfile
		#rm -f $setfile
		rm -f $tmpfile
		rm -f $col_file
		rm -f $sqlfile
		rm -f $col_file.tmp
		rm -f $oldfile.tmp
		set +o noglob
		rm -f $dir/lob_${vimpid}_*.txt.old
		rm -f $dir/lob_${vimpid}_*.txt.new
		exit 13
	fi

	if [ $int_flag -ne 1 ];then
		kill -9 $file_bg_pid   > /dev/null 2>&1
	fi

	cp $oldfile.tmp $result_oldfile
	cp $oldfile.tmp $result_newfile

	cp $col_file.tmp $col_file
else
	#将替换成NBSP
	awk -v outfile=$oldfile.tmp -v fgf=$FGF 'BEGIN{FS=OFS=fgf} {
		#去掉行尾结束符
		gsub(/$/,"",$0)
    	for(i=1;i<=NF;i++) {
    	    if(match($i, /*$/)) {
    	        str1 = substr($i, 1, RSTART-1)
    	        str2 = substr($i, RSTART)
    	        gsub(//, " ", str2)
    	        $i = str1 str2

    	    }
		}
		print 
	}' $oldfile > $oldfile.tmp
	
	cp $oldfile.tmp $result_oldfile
	cp $oldfile.tmp $result_newfile
	rm -f $oldfile.tmp
fi

#不接受中断信号
trap "" 2 3

rm -f $procfile
rm -f $sqlfile

line_num=`wc -l $result_newfile|awk '{print $1}'`
#vim 要加-u NONE(不加载默认配置),否则调用ShowUpdateTitle()时光标停在第5行，且不能向上移动
if [ $line_num -eq 1 ];then
	vim -u NONE -c "call oracle_tui#SetLocal()|call oracle_tui#SetMapUpdate()|call oracle_tui#SetAutocmdUpdate()" $result_newfile
else
	vim -u NONE -c "call oracle_tui#SetLocal()|call oracle_tui#SetMapUpdate()|call oracle_tui#SetAutocmdUpdate()|call oracle_tui#ShowUpdateTitle()|normal! gg" $result_newfile
fi
#vim -c "call oracle_tui#SetLocal()|call oracle_tui#SetMapUpdate()|call oracle_tui#SetAutocmdUpdate()|call oracle_tui#ShowDiff()" -c "call Hid()|redraw!" $newfile
# 恢复终端设置

rm -f $result_oldfile
rm -f $result_newfile
rm -f $oldfile
rm -f $newfile
#rm -f $setfile
rm -f $tmpfile
rm -f $col_file
rm -f $col_file.tmp
rm -f $oldfile.tmp
set +o noglob
rm -f $dir/lob_${vimpid}_*.txt.old
rm -f $dir/lob_${vimpid}_*.txt.new

ReturnByErrorCode() 
{
    for suffix in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
        if [ -f ~/.dbtmp/$shortfile.err.$suffix ]; then
            rm -f ~/.dbtmp/$shortfile.err.$suffix
            exit $suffix
        fi
    done

	#提交修改时调用db_update_data.sh,它只有在修改数据失败时
	#不会返回到db_query_update.sh(停留在数据编辑文件中提示:请
	#重新编辑), 其他情况都会直接返回到db_query_update.sh脚本中

	#db_update_data.sh修改数据失败后不会产生错误码指示文件,
	#用户要么选在重修修改数据后提交修改知道修改成功后
	#返回到本脚本，要么选择直接选择退出不再修改,选择退出时
	#不会有对应的错误码文件,100就代表修改失败后放弃修改
	exit 100
}

#根据错误码文件返回指定的返回值
ReturnByErrorCode
