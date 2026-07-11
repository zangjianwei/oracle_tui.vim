################################################################################
#                             更新数据                                         #
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
# 15 命令行参数错误                                                            #
# 禁止中断，因为中断后数据回滚时间会很长                                       #
# 作者:臧建伟                                                                  #
################################################################################
if [ "$1" = "-h" -o $# -ne 1 -a $# -ne 3 ];then
    echo "Usage:`basename $0` shortfile"
	shortfile=`basename $1`
	>~/.dbtmp/$shortfile.err.15
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

set -o noglob

trap "" 2 3

dir=$HOME/.dbtmp
shortfile=`basename $1`
filename=`basename $1`
newfile=$filename.dif.new
newfile=`echo $newfile|sed 's/-/_/'`
oldfile=$filename.dif.old
oldfile=`echo $oldfile|sed 's/-/_/'`
vimpid=`echo $filename|awk -F- '{print $2}'|sed 's/\.txt.new//'`
col_len_file=~/.dbtmp/${vimpid}_col.txt
updatesql_file=$dir/${vimpid}_update.sql
crttab_file=$dir/${vimpid}_crttab.log
fgf=""
cur_pid=$$                  
SQL_END=SQL_END_$cur_pid    
browfile=$dir/${vimpid}_updres.txt

ReadPipe()
{
	while read -r line
	do
		if [[ "$line" = "$SQL_END" ]];then
			break
		fi
	done < $pipe_out 
}

CrtSql()
{
	#主文件
	main_file=$1  
	#辅文件
	aux_file=$2
	#输出文件
	outfile=$3
	table=$unit
	awk -v fgf=$fgf -v table=$table \
		-v install_file=$outfile \
		-v col_file=$col_len_file \
		-v aux_file=$aux_file \
		-v toolong_flag=$toolong_flag \
		-v lob_file_flag=$lob_file_flag \
		-v lob_file_dir="$HOME/.dbtmp" \
		-v errfile=$browfile \
		'function SetVarByValue(colname, coltype, value, install_file)
		{
			#sqlplus一行最大长度不能超过2499字节(最大2499/3=833个多字节字符)
			#block_len 必须时偶数,否则blob raw截取时有问题
			block_len = 750;
			
			len = length(value)
			if (len == 0)
			{
				if (coltype == "blob" || coltype == "long raw")
				{
					setvar = sprintf("var_%s := NULL;", colname);
				}
                else
				{
					setvar = sprintf("var_%s := \047\047;", colname);
				}
				printf("    %s\n", setvar) >> install_file
			}
			else
			{
				if (len <= block_len)
				{
					gsub("\047", "\047\047", value)
					if (coltype == "blob" || coltype == "long raw")
						setvar = sprintf("var_%s := HEXTORAW(\047%s\047);", colname, value);
					else
						setvar = sprintf("var_%s := \047%s\047;", colname, value);
					printf("    %s\n", setvar) >> install_file
				}
				else
				{
					if (coltype == "blob" || coltype == "long raw")
					{
						print "    v_blob := NULL;" >> install_file
						print "    DBMS_LOB.CREATETEMPORARY(v_blob, TRUE);" >> install_file

						for(m=1; m<=len; m+=block_len)
						{
							str = substr(value, m, block_len)

							printf("    v_blob_str := \047%s\047;\n", str) >> install_file
							print  "    v_blob_raw := HEXTORAW(v_blob_str);   " >> install_file
    						print  "    DBMS_LOB.WRITEAPPEND(v_blob, UTL_RAW.LENGTH(v_blob_raw), v_blob_raw); " >> install_file
							print  "" >> install_file
						}
						printf("    var_%s := v_blob;\n", colname) >> install_file
						print  "    DBMS_LOB.FREETEMPORARY(v_blob);" >> install_file
					}
					else
					{
						if (coltype == "clob" || coltype == "nclob")
						{
							print "    v_clob := NULL;" >> install_file
							print "    DBMS_LOB.CREATETEMPORARY(v_clob, TRUE);" >> install_file
						}

						for(m=1; m<=len; m+=block_len)
						{
							block_str = substr(value, m, block_len)
							#不再在每行后加一空格以防止半个字符
							#block_str = block_str" "
							gsub("\047", "\047\047", block_str)

							if (coltype == "clob" || coltype == "nclob")
							{
								printf("    v_chunk := \047%s\047;\n", block_str) >> install_file
    							print  "    DBMS_LOB.WRITEAPPEND(v_clob, length(v_chunk), v_chunk); " >> install_file
							}
							else
							{
								if (m == 1)
								{
									printf("    var_%s := \047%s\047 ||\n", colname, block_str) >> install_file
								}
								else
								{
									if (m + block_len <= len)
										printf("        \047%s\047 ||\n", block_str) >> install_file
									else
										printf("        \047%s\047;", block_str) >> install_file
								}
							}
						}

						if (coltype == "clob" || coltype == "nclob")
						{
							printf("    var_%s := v_clob;\n", colname) >> install_file
							print "    DBMS_LOB.FREETEMPORARY(v_clob);" >> install_file
						}
					}
				}
				if (coltype ~ /char/ || coltype ~/clob/)
				{
					printf("    var_%s := replace(var_%s, \047\047, chr(10));\n", colname, colname) >> install_file
				}
				print  "" >> install_file
			}
		}
		BEGIN{
			OFS = fgf

			if (toolong_flag == 1)
			{
				print "declare" >> install_file
  				print "    v_chunk VARCHAR2(3000);"   >> install_file
                print "    v_clob clob;"               >> install_file
				print "    v_blob blob; "              >> install_file
			}

			i = 0;
			while (getline < col_file)
			{
				i++
				arr_name[i] = tolower($1)
				arr_col_length[i] = tolower($3)

				if ($2 == 96)
				{
					if ($5 == 2)
						arr_col_type[i] = "nchar"
					else
						arr_col_type[i] = "char"
				}
				else if ($2 == 1)
				{
					if ($5 == 2)
						arr_col_type[i] = "nvarchar2"
					else
						arr_col_type[i] = "varchar2"
				}
				else if ($2 == 112)
				{
					if ($5 == 2)
						arr_col_type[i] = "nclob"
					else
						arr_col_type[i] = "clob"
				}
				else if ($2 == 2)
				{
					arr_col_type[i] = "number"
				}
				else if ($2 == 8)
				{
					arr_col_type[i] = "long"
				}
				else if ($2 == 11)
				{
					arr_col_type[i] = "rowid"
				}
				else if ($2 == 12)
				{
					arr_col_type[i] = "date"
				}
				else if ($2 == 23)
				{
					arr_col_type[i] = "raw"
				}
				else if ($2 == 24)
				{
					arr_col_type[i] = "long raw"
				}
				else if ($2 == 69)
				{
					arr_col_type[i] = "urowid"
				}
				else if ($2 == 100)
				{
					arr_col_type[i] = "binary_float"
				}
				else if ($2 == 101)
				{
					arr_col_type[i] = "binary_double"
				}
				else if ($2 == 180)
				{
					arr_col_type[i] = "timestamp"
				}
				else if ($2 == 181)
				{
					arr_col_type[i] = "timestamp with time zone"
				}
				else if ($2 == 231)
				{
					arr_col_type[i] = "timestamp with local time zone"
				}
				else if ($2 == 113)
				{
					arr_col_type[i] = "blob"
					has_blob_flag = 1
				}
				else if ($2 == 114)
				{
					arr_col_type[i] = "bfile"
				}
				else if ($2 == 208)
				{
					arr_col_type[i] = "urowid"
				}
				else if ($2 == 182)
				{
					arr_col_type[i] = "interval year to month"
				}
				else if ($2 == 183)
				{
					arr_col_type[i] = "interval day to second"
				}
				else
				{
					printf("非法数据类型[%d]\n", $2);
					exit
				}

				if (toolong_flag == 1)
				{
					if (arr_col_type[i] ~ /char/) 
					{
						printf("    var_%s %s(%d);\n", arr_name[i], arr_col_type[i], arr_col_length[i]) >> install_file
					}
					if (arr_col_type[i] ~ /clob/ || arr_col_type[i] ~ /blob/ || arr_col_type[i] ~ /long/) 
					{
						printf("    var_%s %s;\n", arr_name[i], arr_col_type[i]) >> install_file
					}
				}
			}
			num_col = i

			if (toolong_flag == 1)
			{
				if (has_blob_flag == 1)
				{
                	print "    v_blob_str VARCHAR2(5000);     " >> install_file
                	print "    v_blob_raw RAW(5000);          " >> install_file
				}
			}

			print "begin" >> install_file
			print "    SAVEPOINT start_point;" >> install_file

			FS = fgf

			while (getline < aux_file)
	    	{
				#去掉尾部NBSP
				gsub(/ *$/,"",$1)
				
				delete_str = sprintf("delete from %s where rowid = \047%s\047;", 
						table, $1);

	
				print "    "delete_str >> install_file
	    	}
	}
	{
		linebak = $0
		#处理new文件

		for(i = 2; i <= NF; i++)
		{
			#去掉尾部NBSP字符
			#将连续的NBSP字符替换为空依赖LC_CTYPE是否为UTF-8
			#如果不是UTF-8,则认为是多字节,只会替换最后一个NBSP字符
			gsub(/ *$/,"",$i)
			if (arr_col_type[i] ~ /char/ \
				|| arr_col_type[i] ~ /timestamp/ \
				|| arr_col_type[i] == "date" \
				|| arr_col_type[i] ~ /clob/ \
				|| arr_col_type[i] ~ /blob/ \
				|| arr_col_type[i] ~ /long/ \
				|| arr_col_type[i] == "raw" )
			{
				#将头部和中间NBSP字符替换成空格
				gsub(/ /," ",$i)

				#char去尾部空格
				#varchar2和clob不去尾部空格
				if (arr_col_type[i] == "char" || arr_col_type[i] == "nchar")
				{
					if (match($i,/^  *$/))
					{
						#如果都是空格，保留一个空格
						gsub(/  */," ",$i)
					}
					else
					{
						#去掉尾部空格
						gsub(/  *$/,"",$i)
					}
				}

				if (arr_col_type[i] ~ /timestamp/ || arr_col_type[i] == "date" || arr_col_type[i] == "raw")
				{
					#去掉尾部和头部空格
					gsub(/^ */,"",$i)
					gsub(/ *$/,"",$i)
				}
			}
			else if (arr_col_type[i] ~ /interval/ )
			{
				#INTERVAL YEAR TO MONTH/INTERVAL DAY TO SECOND
				#删除头部空格字符
				gsub(/^ */,"",$i)
				gsub(/^ */,"",$i)

				#去掉尾部空格
				gsub(/ *$/,"",$i)

				#将中间NBSP字符替换成空格
				gsub(/ /," ",$i)
			}
			else
			{
				#非字符
				#去掉NBSP和空格
				gsub(/ /,"",$i)
				gsub(/ /,"",$i)
			}
		}

		insert_str = sprintf("insert into %s values (", table)
		for(i = 2; i <= NF; i++)
		{
			#插入时将:where brcattr='1'中单引号替换成两个单引号:where brcattr=''1''
			value = $i
			gsub("\047", "\047\047", $i)

			colname = arr_name[i]
			#两边加双引号
			if (arr_col_type[i] ~ /char/ \
				|| arr_col_type[i] ~ /timestamp/ \
				|| arr_col_type[i] == "date" \
				|| arr_col_type[i] ~ /clob/ \
				|| arr_col_type[i] ~ /long/ \
				|| arr_col_type[i] ~ /blob/ \
				|| arr_col_type[i] ~ /long raw/ \
				|| arr_col_type[i] ~ /interval/ \
				|| arr_col_type[i] == "raw" \
				|| arr_col_type[i] == "urowid")
			{
				#如果字符串太长执行sql时会报错，要分段截取再拼接赋给一个变量，执行sql中用变量替换
				if ((arr_col_type[i] ~ /char/ \
					|| arr_col_type[i] ~ /clob/ \
					|| arr_col_type[i] ~ /blob/ \
					|| arr_col_type[i] ~ /long/) \
					&& toolong_flag == 1)
				{
					if ((arr_col_type[i] ~ /clob/ \
						|| arr_col_type[i] ~ /blob/ \
						|| arr_col_type[i] ~ /long/) \
						&& lob_file_flag == 1)
					{
						lob_file = value
						gsub(" ", "", value)
						gsub(" ", "", lob_file)
						#printf("lob_file=[%s]\n",lob_file)
						if (lob_file != "")
						{
							gsub("<", "", lob_file)
							gsub(">", "", lob_file)
							gsub(" *$", "", lob_file)
							lob_file = sprintf("%s/%s", lob_file_dir, lob_file)

							if ((getline lob_line < lob_file) < 0) 
							{
							    close(lob_file)
    						    printf("不能修改lob字段的文件名:[%s]!\n", lob_file) > errfile
								exit
							}
		                    else
							{
								lob_value = lob_line
								k = 1
								
								while ((getline lob_line < lob_file) > 0)
								{
								 	lob_value = lob_value "" lob_line
									k++
								}
								close(lob_file)
								SetVarByValue(colname, arr_col_type[i], lob_value, install_file)
							}
						}
						else
						{
							SetVarByValue(colname, arr_col_type[i], value, install_file)
						}
					}
					else
					{
						SetVarByValue(colname, arr_col_type[i], value, install_file)
					}
					$i = "var_"colname
				}
				else
				{
					$i = "\047"$i"\047"
				}
			}
			if ((arr_col_type[i] == "nchar" ||arr_col_type[i]  == "nvarchar2"||arr_col_type[i]  == "nclob") && toolong_flag != 1)
			{
				$i = "N"$i
			}
			else if (arr_col_type[i] ~ /interval.*year/)
			{
				if ($i == "\047\047")
					$i = "null"
				else
					$i = "INTERVAL "$i" YEAR TO MONTH"
			}
			else if (arr_col_type[i] ~ /interval.*day/)
			{
				if ($i == "\047\047")
					$i = "null"
				else
					$i = "INTERVAL "$i" DAY TO SECOND"
			}

			#如果是blob类型，赋值为空值 
			#if (arr_col_type[i] == "blob" || arr_col_type[i] == "long" || arr_col_type[i] == "long_raw" )
			#{
			#	 $i = "\047\047"
			#}


			if (i > 1)
				insert_str = sprintf("%s ", insert_str)
			if ($i == "")
			{
				insert_str = sprintf("%snull", insert_str)
			}
			else
			{
				insert_str = sprintf("%s%s", insert_str,$i)
			}
			if (i != NF)
				insert_str = sprintf("%s,", insert_str)
			else
				insert_str = sprintf("%s);", insert_str)
		}

		gsub(//, "\n" ,insert_str)
		print "    "insert_str >> install_file
	}
	END {
		print "" >> install_file 
		print "    EXCEPTION" >> install_file 
		print "        WHEN OTHERS THEN" >> install_file 
		print "            ROLLBACK TO start_point;" >> install_file 
		print "            DBMS_OUTPUT.PUT_LINE(SQLERRM);" >> install_file 
		print "end;" >> install_file
		print "/" >> install_file

	}' $main_file 

	if [ $? -ne 0 ];then
		kill -9 $bg_pid   > /dev/null 2>&1
		rm -f $updatesql_file   
		rm -f $dir/$newfile
		rm -f $dir/$oldfile
		>~/.dbtmp/$shortfile.err.10
		exit 10
	fi

	if [ -f $browfile ];then
	    return 1
	else
    	return 0
	fi

    return 0
}

DiffData()
{
	shortfile=$1
	newfile2=$shortfile.txt.new
	oldfile2=$shortfile.txt.old

	newfile2_tmp=$shortfile.txt.new.tmp
	oldfile2_tmp=$shortfile.txt.old.tmp

	sed -n '2,$ p' $dir/$newfile2 > $dir/$newfile2_tmp
	sed -n '2,$ p' $dir/$oldfile2 > $dir/$oldfile2_tmp
	
	diff ~/.dbtmp/$newfile2_tmp ~/.dbtmp/$oldfile2_tmp > ~/.dbtmp/$shortfile.dif
	result=$?
	rm -f $dir/$newfile2_tmp
	rm -f $dir/$oldfile2_tmp

	if [ $result -eq 0 ];then #两文件一致
		rm -f ~/.dbtmp/$shortfile.dif
		return 0
	else
		awk '/^< /' ~/.dbtmp/$shortfile.dif |sed 's/^< //'> ~/.dbtmp/$newfile
	
		awk '/^> /' ~/.dbtmp/$shortfile.dif |sed 's/^> //'> ~/.dbtmp/$oldfile
	
		rm -f ~/.dbtmp/$shortfile.dif
	
		return 1
	fi
}
DiffData $shortfile

if [ $? -eq 0 ];then
	#返回3 没有修改
	>~/.dbtmp/$shortfile.err.3
	exit 3
fi

IFS="
"

toolong_flag=`awk 'BEGIN{toolong_flag = 0}
	{ 
		#如果是varchar2类型并且长度大于2900,或者有clob类型，置toolong_flag标志
		if ($2 == 1 && $3 > 2900 || $2 == 112 || $2 == 8 || $2 == 113 || $2 == 24) 
		{
			toolong_flag = 1 
		}
		tot_len = tot_len + $3
	} 
	END{ 
		if (tot_len > 2800)
			toolong_flag = 1
		print toolong_flag 
	}' $col_len_file`

lob_file_flag=0

unit=`echo $filename|sed 's/^p_//'|awk -F- '{print $1}'`
echo $unit|grep "^c_" > /dev/null 2>&1
if [ $? -eq 0 ];then
	lob_file_flag=1
	unit=`echo $unit|sed 's/^c_//'`
fi

field_num=`echo $unit|awk -F. '{print NF}'`
if [ $field_num -eq 2 ];then
	owner=`echo $unit|awk -F. '{print toupper($1)}'`
	up_tabname=`echo $unit|awk -F. '{print toupper($2)}'`
else
	up_tabname=`echo $unit|awk '{print toupper($1)}'`
fi

#setfile=~/.dbtmp/${vimpid}_upd_set.sql  
pipe_in=$dir/.pipe_in.$vimpid
pipe_out=$dir/.pipe_out.$vimpid
sqlplus_pid_file=~/.dbtmp/.sqlplus_pid.$vimpid

if [ ! -p $pipe_in ];then
	>~/.dbtmp/$shortfile.err.4
	exit 4
fi

sqlplus_pid=`cat $sqlplus_pid_file|awk '{print $1}'`
#pid2=`ps -ef|awk -v pid=$sqlplus_pid '{if ($2 == pid) print $2}'`
#if [ "$pid2" != "$sqlplus_pid" ];then
if ! kill -0 $sqlplus_pid 2>/dev/null; then
	>~/.dbtmp/$shortfile.err.4
	exit 4
fi

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
	    printf "\033[12;30H $prompt_str...${str[$n]} \n"
		n=`echo $n|awk '{print ($0+1)%5}'`
	    if [ $n -eq 0 ]; then
	         n=1
	    fi
	    sleep 1
	done 
}

prompt_str="Prepare"

rotate &   
bg_pid=$!
#从作业表中移除,否则会显示:31477 Killed                  rotate
#disown $bg_pid
if  command -v disown > /dev/null 2>&1 ;then
	disown $bg_pid
fi

#cd $dir

fgf=""

if [ ! -f $dir/$newfile ];then
	> $dir/$newfile
fi

if [ ! -f $dir/$oldfile ];then
	> $dir/$oldfile
fi

>$updatesql_file
CrtSql $dir/$newfile $dir/$oldfile $updatesql_file
sucflag=$?

if [ $sucflag -ne 0 ];then
	kill -9 $bg_pid   > /dev/null 2>&1
	#rm -f $setfile
	rm -f $updatesql_file   
	rm -f $dir/$newfile
	rm -f $dir/$oldfile
	vim -c "set nonu" $browfile
	rm -f $browfile
	>~/.dbtmp/$shortfile.err.11
	exit 11
fi

kill -9 $bg_pid   > /dev/null 2>&1

#没有修改
if [ ! -s $updatesql_file ];then
	rm -f $updatesql_file   
	#rm -f $dir/col_*.txt
	rm -f $dir/$newfile
	rm -f $dir/$oldfile
	>~/.dbtmp/$shortfile.err.3
	exit 3
fi

#echo ""
#echo "生成完毕"

rm -f $dir/$newfile
rm -f $dir/$oldfile

prompt_str="Executing SQL"
rotate &   
bg_pid=$!
#从作业表中移除,否则会显示:31477 Killed                  rotate
#disown $bg_pid
if  command -v disown > /dev/null 2>&1 ;then
	disown $bg_pid
fi

ReadPipe&
read_pid=$!
(
	#强制刷新输出,否则像输入seect from tabname 则没有输出,输入set heading off也不会有输出
	#echo "set echo on;"
	#echo "set linesize 10000;"
	#echo "set trimout on;"
	#echo "set trimspool on;"
	#set feedback off 如果脚本执行成功browfile为空,如果有sql执行报错则错误信息会显示在browfile中
	#echo "store set $setfile"
	echo "SQL_START"
	echo "set timing off;"
	echo "set feedback off;"
	#echo "SAVEPOINT A;"
	#echo "spool off;"
	#echo "exec dbms_output.put_line('SQL_START');" 
	echo "spool $browfile;"
	echo "@$updatesql_file;"
	echo "spool off;"
	#echo "@$setfile;"
	echo "prompt $SQL_END;"
) > $pipe_in

wait $read_pid

kill -9 $bg_pid   > /dev/null 2>&1

if [ -s $browfile ];then
	#vim -u ~/user/zjw/bin/.vimrc.db $browfile
	vim -u NONE -c "call oracle_tui#SetLocal()|call oracle_tui#SetMapView()|call oracle_tui#SetAutocmdView()" $browfile
	grep "^ORA-" $browfile > /dev/null 2>&1
	if [ $? -eq 0 ];then
		retcode=1
	else
		grep "^SP2-" $browfile > /dev/null 2>&1
		if [ $? -eq 0 ];then
			retcode=1
		else
			retcode=0
		fi
	fi
	#retcode=1
else
	retcode=0
fi

rm -f $crttab_file
rm -f $browfile
#rm -f $setfile
rm -f $updatesql_file   

if [ "$retcode" = "0" ];then
    >~/.dbtmp/$shortfile.err.0
fi

exit $retcode
