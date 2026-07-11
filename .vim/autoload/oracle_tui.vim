"==============================================================================
" oracle_tui.vim - A native Vim-based Oracle client for UNIX/Linux
"==============================================================================
"
" Description:  A lightweight Oracle database client inside Vim that rivals
"               GUI tools. Provides spreadsheet-like data editing via SQL*Plus,
"               with transaction enforcement, LOB support, smart autocompletion,
"               and sticky headers. Perfect for SSH/terminal environments.
"
" Maintainer:   zangjianwei <zangjianwei35@gmail.com>
" Repository:   https://github.com/zangjianwei/oracle_tui.vim
" License:      MIT (See LICENSE file for details)
" Version:      1.01
" Last Change:  2026-07-10
"
" Supported Vim: 7.4+ (Vim 8.2 or above is recommended)
" Supported OS:   UNIX/Linux
" Copyright:    Copyright (C) 1999-2005 Charles E. Campbell, Jr. {{{1
"               Permission is hereby granted to use and distribute this code,
"               with or without modifications, provided that this copyright
"               notice is copied with it. Like anything else that's free,
"               Align.vim is provided *as is* and comes with no warranty
"               of any kind, either expressed or implied. By using this
"               plugin, you agree that in no event will the copyright
"               holder be liable for any damages resulting from the use
"               of this software.
"
" Usage:
"   :Connect              - Connect to Oracle using DBUSER/DBPASS env vars
"   :Connect -u           - Force manual username/password prompt
"   F8                    - Execute SQL (selection or current line)
"   F12                   - Commit data changes in modification window
"   See documentation for full keybindings.
"
"==============================================================================
let s:save_cpo = &cpo
set cpo&vim

"下面这行是为了加载自己的crtdb.txt用，正式提供时要删除
if getfsize($HOME."/oracle_tui/crtdb.txt") > 0
	let s:mydblist=1
else
	let s:mydblist=0
endif

func! oracle_tui#SetUsername(value)
    let s:username = a:value
endfun

func! oracle_tui#SetPassword(value)
    let s:password = a:value
endfun

function! oracle_tui#ExeSql(mode) range
	if a:mode == 'v'
		let reg_bak = @a
		let @a = ""
		
		sil normal! gv"ay
		let buffers=@a
		let @a = reg_bak
	else
		let lines = getline(a:firstline, a:lastline)
		let buffers=join(lines,"\n")
	endif

	let pid=getpid()
	let sql_file=$HOME."/.dbtmp/".pid.".txt.sql"

	let str = ""
	let sql = ""
	let j = 0
	let upd_flag = 0

	let sql_list = []
	let sql_list2 = []
	let onesql_list = []
	let select_flag = 0
	let more_line_flag = 0
	let with_flag = 0
	let sql_num = 0
	let k = 0
	let proc_flag = 0
	let prev_line = ';'
	for line in split(buffers, '\n')
		"如果空行则跳过(存储过程中的空行不跳过)
		if (line =~ "^[ \t]*$" || line =~ "^[ \t]*--") && proc_flag == 0
			continue
		endif
		let k = k +1

		call add(onesql_list, line)

		if line !~ "^[ \t]*--" && line !~ "^[ \t]*$"
			let j = j +1
		endif

		"where col like '--%' 这种情况要剔除
		if line !~ "'.*--.*'" && line =~ '--'
			let line = substitute(line, '--.*', "", "g")
		endif

		if j == 1
			if line =~? '^[ \t]*select'
				let select_flag = 1
			else
				if line =~? '^[ \t]*with[ \t]' || '^[ \t]*with[ \t]*$'
					let with_flag = 1
				endif
			endif
		endif

		if sql_num == 0 && with_flag == 1
			if line =~? ')[ \t]*select'  
				let select_flag = 1
			else
				if line =~? '^[ \t]*select' && prev_line =~ ')[ \t]*$' 
					let select_flag = 1
				endif
			endif
		endif

		if line =~? '^[ \t]*declare' ||
		    \ line =~? '^[ \t]*begin' ||
		    \ line =~? '^[ \t]*create.*procedure' ||
		    \ line =~? '^[ \t]*create.*trigger' ||
		    \ line =~? '^[ \t]*create.*function'
			let proc_flag = 1
		endif

		if line =~ ';[ \t]*$' 
			\ && proc_flag != 1 || line =~ '^[ \t]*/[ \t]*$'
			let sql_num = sql_num + 1

			if sql_num == 1
    			for h in range(len(onesql_list))
					call add(sql_list2, onesql_list[h])
				endfor
			else
				let more_line_flag = 1
				call add(sql_list, printf("prompt %s\\", ' '))
			endif

			if k == 1
				call add(sql_list, printf("prompt %s\\", onesql_list[0]))
			else
    			for h in range(len(onesql_list))
					call add(sql_list, printf("prompt %d %s\\", h+1, onesql_list[h]))
				endfor
			endif

    		for h in range(len(onesql_list))
				call add(sql_list, onesql_list[h])
			endfor

			let k = 0

			if line =~ '^[ \t]*/[ \t]*$'
				let proc_flag = 0
			endif

			let onesql_list = []
		endif

		if line !~ "^[ \t]*--" && line !~ "^[ \t]*$"
			let prev_line = line
		endif
	endfor

	if j == 0
		redraw!
		call oracle_tui#ShowErr("没有sql要执行!")
		return
	endif

	if len(onesql_list) > 0
		if sql_num == 0
    		for h in range(len(onesql_list))
				call add(sql_list2, onesql_list[h])
			endfor
			let sql_num = 1
		else
			call add(sql_list, printf("prompt %s\\", ' '))
			if k == 1
				call add(sql_list, printf("prompt %s\\", onesql_list[0]))
			else
    			for h in range(len(onesql_list))
					call add(sql_list, printf("prompt %d %s\\", h+1, onesql_list[h]))
				endfor
			endif

    		for h in range(len(onesql_list))
				call add(sql_list, onesql_list[h])
			endfor

			let sql_num = sql_num + 1

			let more_line_flag = 1
		endif
		let onesql_list = []
	endif

	if sql_num == 1
		let sql_list = sql_list2
	endif

	if proc_flag == 1 
		redraw!
		call oracle_tui#ShowErr("PLSQL没有/")
		return
	endif

	"最后一行加;
	let n = len(sql_list) - 1
	let mm = 0
	while n >= 0
	    if sql_list[n] !~ '^[ \t]*$' && sql_list[n] !~ '^[ \t]*--'
			let mm = mm + 1

			let last_line = sql_list[n]

			if last_line =~ '--' && last_line !~ "'.*--.*'" 
				let last_line = substitute(last_line, '--.*', '', "g")
			endif

	    	if last_line !~ '[;/][ \t]*$' && mm == 1
				let sql_list[n] = substitute(last_line, '$', ";", "g")
				let last_line = sql_list[n]
			endif

			if last_line =~? 'for[ \t][ \t]*update[ \t]*;[ \t]*$'
				let upd_flag = 1
				break
			elseif last_line =~? '^[ \t]*update[ \t]*;[ \t]*$'
				let half_update_flag = 1
			elseif last_line =~? 'for[ \t]*$' && half_update_flag == 1
				let upd_flag = 1
				break
			else
				break
			endif
		endif
	    let n -= 1
	endwhile

	call writefile(sql_list, sql_file)
	redir END
	let sql_list = []
	let sql_list2 = []

	if select_flag == 1 && more_line_flag == 0
		"只有一条查询语句
		let one_select_flag = 1
	else
		let one_select_flag = 0
	endif

	if upd_flag == 1 && more_line_flag == 1
		redraw!
		call oracle_tui#ShowErr("修改时只能有一条sql语句")
		return
	endif

	if upd_flag == 1
		if v:version < 704
			call oracle_tui#ShowErr("Your Vim is too old; this plugin requires Vim 7.4 or later.")
			return
		endif

		"let str=substitute(str, "for[ \t][ \t]*update[ \t]*$",  "", "g")
		let sql="db_query_update.sh ".pid
		"if exists('s:username') && exists('s:password')
		"	let sql = sql." ".s:username." ".s:password 
		"endif
	else
		let sql="db_exec_sql.sh ".pid. " ".one_select_flag
		if exists('s:username') && exists('s:password')
			let sql = sql." ".s:username." ".s:password 
		endif
	endif

	"redir => output
	if upd_flag == 1
		"execute "!clear;".sql
		"此处要catch异常，否则shell被中断后后面的语句不再执行(比如redraw!)
		try
			sil execute "!clear;".sql
		catch 
			echo "操作被中断"
		endtry
		let status = shell_error
    	redraw! "刷新屏幕
		if status == 0
			"call ShowMsg("修改数据成功")
			echo "修改数据成功,按<F2>回滚事务 <F6>提交事务"
		elseif status == 1
			call oracle_tui#ShowErr("修改数据失败!")
			echo ""
		elseif status == 3
			call oracle_tui#ShowMsg("数据没有修改!")
			echo ""
		elseif status == 4
			call oracle_tui#ShowErr("数据库连接中断!")
			echo ""
		elseif status == 10
			call oracle_tui#ShowErr("生成更新sql时awk语法错误!")
			echo ""
		elseif status == 11
			call oracle_tui#ShowErr("生成更新sql错误!")
			echo ""
		elseif status == 12
			"call oracle_tui#ShowErr("sql语法错误!")
			"echo ""
			let nouse=1
		elseif status == 13
			call oracle_tui#ShowErr("操作被中断!")
			echo ""
		elseif status == 14
			"call oracle_tui#ShowErr("生成的pl/sql执行错误!")
			"echo ""
			let nouse=1
		elseif status == 15
			call oracle_tui#ShowErr("命令行参数错误!")
			echo ""
		elseif status == 100
			call oracle_tui#ShowMsg("放弃修改!")
		else
			call oracle_tui#ShowErr("异常,未知的返回码:".status)
			echo ""
		endif
	else
		"此处要catch异常，否则shell被中断后后面的语句不再执行(比如redraw!)
		try
			sil execute "!clear;".sql
		catch 
			echo "操作被中断"
		endtry
    	redraw! "刷新屏幕
	endif
	"redir END
	"echo output
endfun

function! oracle_tui#SumVisual() range
	let reg_bak = @a
	let @a = ""

	sil normal! gv"ay
	let buffers=@a
	let @a = reg_bak

	let tot = 0

	for line in split(buffers, '\n')
		let tot = tot + str2float(line)
	endfor

	let str_tot = string(tot)
	if str_tot =~ "\."
		let str_tot = substitute(str_tot, '0*$', "", "g")
		let str_tot = substitute(str_tot, '\.$', "", "g")
	endif
	echo "sum:".str_tot."\n"
endfun

"剪切当前光标所在的所有列
function! oracle_tui#SumColumn()
	let reg_bak = @a
	let @a = ""
    let l:col_data = []
    
    " 获取当前光标所在的列位置
    let l:cur_line = line('.')
    let l:vir_col = virtcol('.')
    let l:separator_text = getline(3)
	let real_col = col('.')  
    
    " 获取字段边界
    let l:boundary = oracle_tui#GetFieldBoundaries(l:separator_text, l:vir_col)
    if empty(l:boundary)
        return
    endif
    
    " 计算数据行范围（第2行开始，直到遇到第一个空行）
    let l:start_line = 4
    let l:end_line = line('$')
    
    " 查找第一个空行
    for l:i in range(2, line('$'))
        if getline(l:i) == ''
            let l:end_line = l:i - 1
            break
        endif
    endfor
    

    " 从所有数据行提取对应列的内容
	let line_num = l:end_line - l:start_line
	if l:boundary.start == 1
		call cursor(l:start_line,l:boundary.start)
		let l:boundary.end = l:boundary.end + 1
	else
		call cursor(l:start_line,l:boundary.start-1)
	endif

	let cmd = "normal! \<C-V>".l:boundary.end."|".line_num."j\"ay"
	
	sil execute cmd

	call cursor(l:cur_line, real_col)

	let buffers=@a
	let @a = reg_bak

	let tot = 0

	for line in split(buffers, '\n')
		let tot = tot + str2float(line)
	endfor

	let str_tot = string(tot)
	if str_tot =~ "\."
		let str_tot = substitute(str_tot, '0*$', "", "g")
		let str_tot = substitute(str_tot, '\.$', "", "g")
	endif
	echo "sum:".str_tot
endfunction

function! oracle_tui#Line()
    setlocal cul
    setlocal nowrap
	noremap <silent> <buffer> 9 zh
	noremap <silent> <buffer> 0 zl
	noremap <silent> <buffer> ( zH
	noremap <silent> <buffer> ) zL
endfun

function! oracle_tui#UnLine()
    setlocal nocul
    setlocal wrap
	unmap 9
	unmap 0
	unmap (
	unmap )
endfun

func! oracle_tui#ShowErr(msg)
	echohl ErrorMsg
	echo a:msg
	echohl None
endfun

func! oracle_tui#ShowMsg(msg)
	echohl Directory
	echo a:msg
	echohl None
endfun

function! oracle_tui#Plan() range
	let pid=getpid()
	let plan_file=$HOME."/.dbtmp/plan_".pid.".sql"
	let sql_list = []
	call add(sql_list, "set autotrace trace;")
	let n = a:firstline
	while n <= a:lastline
		let line = getline(n)
		call add(sql_list, line)
		let n = n + 1
	endwhile

    let last_idx = len(sql_list) - 1
    let last_element = sql_list[last_idx]
    
    " 检查是否以分号结尾
	while last_element =~ '^[ \t]*$'
		call remove(sql_list, last_idx)
    	let last_idx = last_idx - 1
    	let last_element = sql_list[last_idx]
	endwhile

    if len(sql_list) == 1 
		redraw!
		call oracle_tui#ShowErr("没有sql语句")
		return
    endif

    if last_element !~ ';[ \t]*$'
        " 添加分号
        let sql_list[last_idx] = last_element . ';'
    endif

	call add(sql_list, "set autotrace off;")

	call writefile(sql_list, plan_file)
	redir END
	if exists('s:username') && exists('s:password')
		sil! execute "!db_exec_file.sh ".plan_file." ".s:username." ".s:password 
	else
		sil! execute "!db_exec_file.sh ".plan_file
	endif
	"用delete函数不会有屏幕闪烁
	"sil! execute "!rm -f ".plan_file
	call delete(plan_file)
	redraw!
endfun

let g:grep_table_window_flag = 0
function! oracle_tui#Tablist(...)  
	if g:grep_table_window_flag == 1
		if winnr('$') > 1
			try
				wincmd j
			catch
				call oracle_tui#ShowErr("列表窗口丢失\n")
				return
			endtry

			if &buftype != "nofile"
				call oracle_tui#ShowErr("没有列表窗口\n")
				return
			endif
			q!
		else
			call oracle_tui#ShowErr("窗口错误\n")
			return
		endif
	endif

	let pid=getpid()
	if s:mydblist == 1
    	if a:0 == 1
			let cmd = "0read !(cat ".$HOME."/oracle_tui/crtdb.txt;cat ".$HOME."/oracle_tui/kjdb.txt)|grep ^表名|awk '{printf \"\\%-30s    \\%s\\n\", $2,$4}' |grep -i ".a:1
		else
			let cmd = "0read !(cat ".$HOME."/oracle_tui/crtdb.txt;cat ".$HOME."/oracle_tui/kjdb.txt)|grep ^表名|awk '{printf \"\\%-30s    \\%s\\n\", $2,$4}'"
		endif
	else
    	if a:0 == 1
			let cmd = "0read !cat ".$HOME."/.dbtmp/.dbobj.".pid."|grep -i ".a:1
		else
			let cmd = "0read !cat ".$HOME."/.dbtmp/.dbobj.".pid
		endif
	endif
	below new
	let g:prompt_str = "按Ctrl+k完成补齐"

	if g:grep_table_window_flag != 1
		let s:save_laststatus = &laststatus
		let s:save_statusline = &statusline
	endif
	setlocal laststatus=2
	setlocal statusline=%{g:prompt_str}
	setlocal nowrap

	"call add(s:head_update_buffers, bufnr('%'))
	set buftype=nofile
	sil execute cmd
	if shell_error != 0
		call oracle_tui#ShowErr("没有表名:".a:1."\n")
		execute "setlocal laststatus=" . s:save_laststatus
		execute "setlocal statusline=" . escape(s:save_statusline, ' ')
		let g:grep_table_window_flag = 0
		:q
		return
	else
		exe "normal gg"
		"echo "按:q推出"
		"sleep 3
	endif
	"<F9> 显示crtdb.txt中表定义
	nnoremap <silent> <buffer> [20~ :ShowTab<CR>
	
	"<F10> 显示创建数据库对象语句
	nnoremap <silent> <buffer> [21~ :DescObj<CR>

	"Ctrl+k 完成自动对齐
	nnoremap <silent> <buffer> <C-K> :GetWord<CR>
	cnoremap <silent> <buffer> <expr> <CR> oracle_tui#CheckGrepTableCommand()
	let g:grep_table_window_flag = 1
endfun

function! oracle_tui#CheckGrepTableCommand() abort
    let cmd = getcmdline()
    let type = getcmdtype()

    if type == ':' && (cmd =~# '^[ \t]*q'||cmd =~# '^[ \t]*x')
		let g:grep_table_window_flag = 0
		execute "setlocal laststatus=" . s:save_laststatus
		execute "setlocal statusline=" . escape(s:save_statusline, ' ')
    endif

    "执行原始命令
    return "\<CR>"
endfunction

function! oracle_tui#GetWord() 
	let line1 = getline('.')
	let col1 = col('.')
	"echo "|". strpart(line1, col1-1, 1) . "|"
	"sleep 1
	"return

	if strpart(line1, col1-1, 1) == " " || strpart(line1, col1-1, 1) == "\t"
	    \ || strpart(line1, col1-1, 1) == ""
	   	echo "请将光标放在单词上"
		return
	endif

	let word=expand("<cword>")
	if &buftype == "nofile"
		execute "setlocal laststatus=" . s:save_laststatus
		execute "setlocal statusline=" . escape(s:save_statusline, ' ')
		:q
		let line = getline('.')
		let col = col('.')
		if strpart(line, col-1, 1) == ' ' || strpart(line, col-1, 1) == '\t'
			execute "normal a".word." "
		else
			let str = strpart(line,0,col(".")-1)
			let str2 = strpart(line,col(".")-1)

			if str =~ "[ \t.,]"
				if str2 =~ "[ \t,]"
					"execute "normal ?[ \t.,]lc/[ \t]".word." "
					execute "normal ?[ \t.,]"
					let col2 = col('.')
					"如果当位置是.*则继续往前找
					if strpart(str, col2-1, 1) == "\." && strpart(str, col2, 1) == "\*"
						let str3 = strpart(line,0,col2-1)
						if str3 =~ "[ \t.,]"
							execute "normal ?[ \t.,]lc/[ \t,]".word." "
						else
							execute "normal ^c/[ \t,]".word." "
						endif
					else
						execute "normal lc/[ \t,]".word." "
					endif
				else
					"execute "normal ?[ \t.,]lc$".word." "
					execute "normal ?[ \t.,]"
					let col2 = col('.')
					"如果当位置是.*则继续往前找
					if strpart(str, col2-1, 1) == "\." &&  strpart(str, col2, 1) == "\*"
						let str3 = strpart(line,0,col2-1)
						if str3 =~ "[ \t.,]"
							execute "normal ?[ \t.,]lc$".word." "
						else
							execute "normal ^c$".word." "
						endif
					else
						execute "normal lc$".word." "
					endif
				endif
			else
				if str2 =~ "[ \t,]"
					execute "normal ^c/[ \t,]".word." "
				else
					execute "normal ^c$".word." "
				endif
			endif
		endif
		"不退出插入模式
		startinsert
	else
		call oracle_tui#ShowErr("Error\n")
	endif
	let g:grep_table_window_flag = 0
endfun

"let s:head_update_buffers = []
function! oracle_tui#ShowTab() 
	"let word=expand("<cword>")
	"execute  "!db_showtab.sh ".word

	let word=expand("<cword>")
	if s:mydblist == 1 
		let cmd = "0read !db_showtab.sh ".word
	else
		let line = getline('.')
		let col = col('.')
		if strpart(line, col-1, 1) == " " ||
    	   	\ strpart(line, col-1, 1) == "\t" ||
    	   	\ strpart(line, col-1, 1) == "." 
		   	echo "请将光标放在单词上"
		   	return
   		endif

		let start = matchstr(line[:col-1],  '[a-zA-Z0-9_.]\+$')
		"line[n:10] :前不能直接用变量
		"let end   = matchstr(line[col-1+1:],'^[^ \t.]\+') 
		let end   = matchstr(strpart(line, col),'^[a-zA-Z0-9_.]\+') 

		let word = start.end
		if exists('s:username') && exists('s:password')
			let cmd = "0read !db_desc_table.sh ".word." ".s:username." ".s:password 
		else
			let cmd = "0read !db_desc_table.sh ".word
		endif
	endif

	"below new
	"wincmd L
	"vertical resize 60
	"set hid
	"enew
	tabnew
	"call add(s:head_update_buffers, bufnr('%'))

	"set nowrap
	setlocal buftype=nofile
	noremap <silent> <buffer> [ zh
	noremap <silent> <buffer> ] zl
	noremap <silent> <buffer> { zH
	noremap <silent> <buffer> } zL
	setlocal nowrap
	setlocal cul
	if s:mydblist != 1 
		nnoremap <silent> <buffer> <Tab> :call oracle_tui#JumpToNextField()<CR>
		nnoremap <silent> <buffer> <C-T> :call oracle_tui#JumpToPrevField()<CR>
		nnoremap <silent> <buffer>  :call oracle_tui#ReduceColumn()<CR>
		nnoremap <silent> <buffer> \x :call oracle_tui#CutColumn()<CR>
		nnoremap <silent> <buffer> \p :call oracle_tui#PasteColumn()<CR>
	endif

	call oracle_tui#SetEnv() 
    set virtualedit=all
	sil execute cmd
	if shell_error != 0
		q
		redraw!
		echo "没有表[".word."]说明"
	else
		exe "normal gg"
    	call feedkeys(":echo '按[或{左移 ]或}右移 j或J下移 k或K上移'\<CR>", 'n')
		"只在当前缓冲区内有效
		"cmap <silent> <buffer> q bd
	   	"cmap <silent> <buffer> q bd<bar>execute s:last_win_nr.'wincmd w'
		"cmap <silent> <buffer> q bd<bar>execute winnr('#').'wincmd w'
		"echo "按:q推出"
		"sleep 3
	endif
endfun

function! oracle_tui#DescObj() 
	let old_iskeyword = &iskeyword
	set iskeyword+=.
	let save_cursor = getpos('.')
	let line = getline('.')
	let word=expand("<cword>")
	let &iskeyword = old_iskeyword

	let object_type = ''
	if  strpart(line, 0, 1) == '	'
		normal! ?^[^\t]
		let object_type = getline('.')
		let object_type = substitute(object_type, '\[', "", "g")
		let object_type = substitute(object_type, '\]', "", "g")
	endif 
	call setpos('.', save_cursor)

	if object_type == ''
		if exists('s:username') && exists('s:password')
			let cmd = "db_desc_obj.sh ".word." ".s:username." ".s:password 
		else
			let cmd = "db_desc_obj.sh ".word
		endif
	else
		if exists('s:username') && exists('s:password')
			let cmd = "db_desc_obj.sh ".word." ".object_type." ".s:username." ".s:password 
		else
			let cmd = "db_desc_obj.sh ".word." ".object_type
		endif
	endif

	try
		sil execute "!clear;".cmd
	catch 
		echo "操作被中断"
	endtry
    redraw! "刷新屏幕
endfun
command!  DescObj call oracle_tui#DescObj()

"根据光标所在单词搜索表名
function! oracle_tui#GrepTab() 
	"let word=expand("<cword>")
	let line = getline('.')
	let col = col('.')
	if strpart(line, col-1, 1) == " " ||
       	\ strpart(line, col-1, 1) == "\t" ||
       	\ strpart(line, col-1, 1) == "." 
	   	echo "请将光标放在单词上"
	   	return
   	endif

	let start = matchstr(line[:col-1],  '[^ \t,]\+$')
	"let start = matchstr(line[:col-1],  '[^ \t,@=\-+|:;\"]\+$')
	"let start = matchstr(line[:col-1],  '[a-zA-Z0-9_.*]\+$')

	"line[n:10] :前不能直接用变量
	"let end   = matchstr(line[col-1+1:],'^[^ \t.]\+') 

	let end   = matchstr(strpart(line, col),'^[^ \t,]\+')
	"let end   = matchstr(strpart(line, col),'^[^ \t,@=\-+|:;\"]\+') 

	let word = start.end

	"echo "start=".start
	"echo "end=".end
	"echo "word=".word
	if word =~ "\\.[^*]"
		let word = substitute(word, '^[^.]*\.', "", "g")
		"echo "word2=".word
	endif
	"sleep 2
	execute ":Tablist ".word
endfun

function! oracle_tui#Seelock()
	let str = "db_runsql_sqlplus.sh \"select   p.spid,c.object_name,b.session_id,a.sid,a.serial\\#,a.process,a.program,b.oracle_username,b.os_user_name   from   v\\$process   p,v\\$session   a,   v\\$locked_object   b,all_objects   c   where   p.addr=a.paddr   and   a.process=b.process   and   c.object_id=b.object_id\""
	if exists('s:username') && exists('s:password')
		let str = str." ".s:username." ".s:password 
	endif

	try
		sil execute  "!".str
	catch 
		echo "操作被中断"
	endtry
	
    redraw! "刷新屏幕
endfun

function! oracle_tui#Tabspace()
	let str = "db_runsql_sqlplus.sh \"select substr(dbf.tablespace_name,1,12) 表空间, round(dbf.totalspace,0)  总量M, dbf.totalblocks  总块数, round(dfs.freespace,0)  剩余总量M, dfs.freeblocks  剩余块数, round((dfs.freespace / dbf.totalspace)*100,2)  空闲比例 from (select t.tablespace_name, sum(t.bytes) / 1024 / 1024 totalspace, sum(t.blocks) totalblocks from dba_data_files t group by t.tablespace_name) dbf, (select tt.tablespace_name, sum(tt.bytes) / 1024 / 1024 freespace, sum(tt.blocks) freeblocks from dba_free_space tt group by tt.tablespace_name) dfs where trim(dbf.tablespace_name) = trim(dfs.tablespace_name)\""
	if exists('s:username') && exists('s:password')
		let str = str." ".s:username." ".s:password 
	endif

	try
		sil execute  "!".str
	catch 
		echo "操作被中断"
	endtry
	
    redraw! "刷新屏幕
endfun

function! oracle_tui#Tabused()
	let str = "db_runsql_sqlplus.sh \"select cast(substr(Segment_Name,1,30) as char(30)) 表名,round( Sum(bytes)/1024/1024,0) 占用M From User_Extents Group By Segment_Name order by 2 desc\""
	if exists('s:username') && exists('s:password')
		let str = str." ".s:username." ".s:password 
	endif

	try
		sil execute  "!".str
	catch 
		echo "操作被中断"
	endtry
	
    redraw! "刷新屏幕
endfun

function! oracle_tui#Nowsql()
	let str = "db_runsql_sqlplus.sh \"SELECT osuser, username, a.PROGRAM, b.sql_id,b.address,piece,sql_text from v\\$session a, v\\$sqltext b where a.sql_address =b.address order by osuser,username,sql_id,piece\""
	if exists('s:username') && exists('s:password')
		let str = str." ".s:username." ".s:password 
	endif

	try
		sil execute  "!".str
	catch 
		echo "操作被中断"
	endtry
	
    redraw! "刷新屏幕
endfun

function! oracle_tui#Unlock(...)
	if a:0 != 2
		call oracle_tui#ShowErr("Usage:Unlock sid serial")
		return
	endif

	let str = "db_runsql_sqlplus.sh \"alter system kill session '".a:1.",".a:2."'\""
	if exists('s:username') && exists('s:password')
		let str = str." ".s:username." ".s:password 
	endif

	try
		sil execute  "!".str
	catch 
		echo "操作被中断"
	endtry
	
    redraw! "刷新屏幕
endfun

"执行文件中的所有sql
fun! oracle_tui#Fsql()
	let file=expand("%")
	if exists('s:username') && exists('s:password')
		let cmd = "!db_exec_file.sh ".file." ".s:username." ".s:password
	else
		let cmd = "!db_exec_file.sh ".file
	endif
	execute  cmd
endfun

function! oracle_tui#RollCommit(flag)
	"let s:commit_str = ""
	"setlocal laststatus=0

	let pid=getpid()
	if a:flag == 1
		let cmd="db_transaction.sh commit ".pid
	else
		let cmd="db_transaction.sh rollback ".pid
	endif
	"sil execute "!".cmd
	let output = system(cmd)
	redraw!
	"echo output
    "不用敲回车
	let output = substitute(output, "\n", "", "g") 
	if output == "执行完成" || output == ""
		if a:flag == 1
			let output = "提交已完成"
		else
			let output = "回滚已完成"
		endif
	endif
	echo output
endfun

function! MyFoldText() 
	let line_count = v:foldend - v:foldstart + 1
	let text = printf("+-- Total %d items", line_count)
	return text
endfun

let g:brow_objects_window_flag = 0
function! oracle_tui#ListObj() 
	if g:brow_objects_window_flag != 1
		let pid=getpid()

		if exists('s:username') && exists('s:password')
			let cmd = "!db_list_obj.sh ".pid." ".s:username." ".s:password
		else
			let cmd = "!db_list_obj.sh ".pid
		endif

		let result_file=$HOME."/.dbtmp/.dblist_".pid.".txt"

		if !filereadable(result_file)
			try
				sil execute cmd
				redraw!
			catch 
				redraw!
				call oracle_tui#ShowErr("中断列出数据库对象")
				return
			endtry
		endif

		"below new
		"wincmd L
		"vertical resize 60
		"set hid
		vertical vnew

		"call add(s:head_update_buffers, bufnr('%'))

		"set nowrap
		set buftype=nofile
		"ts要与sw长度一致,否则不能缩进
		setlocal ts=4
		setlocal sw=4
		setlocal foldmethod=indent
		setlocal foldtext=MyFoldText()
		setlocal foldminlines=0
		"sil execute cmd
		let lines = readfile(result_file)
		call append(0, lines)

		set nowrap
		wincmd H
		vertical resize 30
		normal gg
		"let &l:stl="%#Normal#".repeat(' ',winwidth(0))
		"exe "normal gg"
		"只在当前缓冲区内有效
		"cmap <silent> <buffer> q bd<bar>wincmd p
		"cmap <silent> <buffer> q bd<bar>execute s:last_win_nr.'wincmd w'
		"cmap <silent> <buffer> q bd<bar>execute winnr('#').'wincmd w'

		"<F9> 显示crtdb.txt中表定义
		nnoremap <silent> <buffer> [20~ :ShowTab<CR>
		
		"<F10> 显示创建数据库对象语句
		nnoremap <silent> <buffer> [21~ :DescObj<CR>

		cnoremap <silent> <buffer> <expr> <CR> oracle_tui#CheckListObjViewCommand()

		let g:brow_objects_window_flag = 1
	else
		let g:brow_objects_window_flag = 0
		wincmd h
		q!
	endif
endfun

function! oracle_tui#IfCommit() 
	let pid=getpid()
	if exists('s:username') && exists('s:password')
		let sql="db_check_trans.sh ".pid." ".s:username." ".s:password 
	else
		let sql="db_check_trans.sh ".pid
	endif

	"下面会闪屏
	"sil execute "! ".sql

	let output=system(sql)
	"redraw!
	let exit_status = shell_error
	if exit_status == 1
		let str = "有未提交事务"
		call oracle_tui#ShowErr(str)
	else
		let str = "无未提交事务"
		echo str
	endif
endfun

function! oracle_tui#CheckIfCommit()
	let pid=getpid()
	let sql="db_check_trans.sh ".pid

	if exists('s:username') && exists('s:password')
		let sql = sql." ".s:username." ".s:password 
	endif
	"用sil则屏幕会清空
	"sil! execute "! ".sql
	let output = system(sql)

	let exit_status = shell_error

	return exit_status
endfun

function! oracle_tui#HandleQuit()
    let type = getcmdtype()
    let cmd = getcmdline()

    if type == ':' && (cmd =~# '^[ \t]*$' || cmd =~# '^[ \t]*w$')
        if !oracle_tui#CheckIfCommit()
            return 'q'
        else
			if cmd =~# '^[ \t]*w$'
            	call oracle_tui#ShowErr("有未提交事务,不能退出,按<F2>回滚 <F6>提交")
            	call feedkeys("\<CR>", 'n')
				"不加sleep，则错误信息一闪而过
				sleep 1
				return ''
			else
            	call oracle_tui#ShowErr("有未提交事务,不能退出,按<F2>回滚 <F6>提交")
				"不加下面这一行，则光标会停留在上面显示的错误信息一行，还要再按个回车
            	call feedkeys("\<CR>", 'n')
            	return ''
			endif
        endif
	else
		return 'q'
    endif
endfunction

function! oracle_tui#HandleQuit_x()
    let type = getcmdtype()
    let cmd = getcmdline()

    if type == ':' && cmd =~# '^[ \t]*$'
        if !oracle_tui#CheckIfCommit()
            return 'x'
        else
            call oracle_tui#ShowErr("有未提交事务,不能退出,按<F2>回滚 <F6>提交")
            call feedkeys("\<CR>", 'n')
            return ''
        endif
	else
		return 'x'
    endif
endfunction

function! oracle_tui#DBCliHelp()
	echo "  +------------------------------------------------------------------------+"
	echo "  |                          按键说明                                      |"
	echo "  |按 F1 显示帮助                                                          |"
	echo "  |按 F8 执行sql(先用Shift+v或Ctrl+v选中要执行的sql,不选执行当前行)        |"
	echo "  |按 Ctrl+c 中断正在执行的操作                                            |"
	echo "  |按 F2 回滚事务   F6 提交事务  F4 查看是否有未提交事务                   |"
	echo "  |按 F5 查看sql执行计划(先用Shift+v选中要执行的sql,不选执行当前行)        |"
	echo "  |按 F7 列出数据库对象                                                    |"
	echo "  |按 F9 显示光标所在单词对应的表结构说明                                  |"
	echo "  |按 F10 显示光标所在单词对应创建数据库对象语句                           |"
	echo "  |按 - 缩小当前窗口宽度           = 增加当前窗口宽度                      |"
	echo "  |按 shift - 缩小当前窗口高度     shift = 增加当前窗口高度                |"
	echo "  |按 Ctrl+↑ 跳到上面窗口          Ctrl+↓ 跳到下面窗口                     | "
	echo "  |按 Ctrl+→ 跳到右面窗口          Ctrl+← 跳到下面窗口                     | "
	echo "  |按 Ctrl+n 对象名自动补齐(开头字符串的自动补齐,适用于插入模式)           |"
	echo "  |按 Ctrl+k 表名自动补齐(支持中间字符串的自动补齐,适用于插入和普通模式)   |"
	echo "  |按 gt 在标签页之间切                                                    |"
	echo "  |按 :Tablist 显示所有表名及其注释                                        |"
	echo "  |按 :Seelock 查看锁  :Unlock 进行解锁                                    |"
	echo "  |按 :Tabused 查看每个表占用空间情况 :Tabspace 进行查看表空间使用情况     |"
	echo "  |按 :Nowsql 查看当前正在运行的sql                                        |"
	echo "  |                         臧建伟制作                                     |"
	echo "  +------------------------------------------------------------------------+"
endfun

"以下是浏览器
let s:show_view_vertical_flag = 0
fun! oracle_tui#ViewVerSplit()
	if s:show_view_vertical_flag == 1
		let s:show_view_vertical_flag = 0
		:q!
    	"call feedkeys(":call oracle_tui#ShowViewTitle()\<CR>", 'n')
    	call oracle_tui#ShowViewTitle()
		return
	else
		let s:show_view_vertical_flag = 1

		if s:show_view_title_flag == 1
			let s:show_view_title_flag = 0
			wincmd k
			q
			"echo "hello"
			"sleep 1
			autocmd! CursorMoved <buffer>
			call oracle_tui#UnMapHideTitleLines()
		endif

		set sbo=ver
		let line = line('.') 
		let col = col('.')
		exec "normal gg"
		vsp
		wincmd l
    	"要执行一下此步骤，否则滚动不同步
		normal! j 
		call cursor(line,col)
	endif
endfun

let s:show_update_vertical_flag = 0
fun! oracle_tui#UpdateVerSplit()
	if s:show_update_vertical_flag == 1
		let s:show_update_vertical_flag = 0
		:q!
		if line('$') > 1
    		"call feedkeys(":call oracle_tui#ShowUpdateTitle()\<CR>", 'n')
    		call oracle_tui#ShowUpdateTitle()
		endif
		return
	else
		let s:show_update_vertical_flag = 1

		if v:version < 900
			"vim9.0 版本一下如果在diffthis模式下，会导致两个垂直分割的
			"窗口会在水平方向同步移动
			diffoff
			let s:show_diff_flag = 0
		endif

		if s:show_update_title_flag == 1
			let s:show_update_title_flag = 0
			wincmd k
			q
			"bwipeout

			autocmd! CursorMoved <buffer>
			call oracle_tui#UnMapHideTitleLines()
		endif

		set sbo=ver
		let line = line('.') 
		let col = col('.')
		exec "normal gg"
		vsp
		wincmd l
    	"要执行一下此步骤，否则滚动不同步
		normal! j 
		call cursor(line,col)
		normal! 20zl
	endif
endfun

fun! oracle_tui#ShowSql()
	let b:file="cat ".expand("%").".sql"
	let b:sql="--------------------------------------------------------------------------------\n".system(b:file)."--------------------------------------------------------------------------------"
	echo b:sql
endfun

fun! oracle_tui#Crtsql()
	let b:file=expand("%").".sql"
    "sil execute "!db_gen_sql.sh ".b:file
	"redraw!

	if exists('s:username') && exists('s:password')
		let cmd="!db_gen_sql.sh ".b:file." ".s:username." ".s:password 
	else
		let cmd="!db_gen_sql.sh ".b:file
	endif

	try
    	"sil execute "!db_gen_sql.sh ".b:file
    	sil execute cmd
	catch 
		echo "操作被中断"
	endtry
    redraw! "刷新屏幕
endfun

"初始化为没有转载列定义文件
let s:load_column_define_flag = 0
let s:field_charset = []
let s:field_data_len = []
let s:field_widths = []
let s:field_types = []
let s:field_names = []
"当前文件总行数
let s:tot_line_num = 0
fun! oracle_tui#ReadColumn()
	"如果没有已经加载过一次，则不再装载
	"因为用tabnew打开一个文件，然后再tabclose时回重新调用ReadColumn
	if s:load_column_define_flag == 0
		let s:load_column_define_flag = 1
	else
		return
	endif
	
	normal! 20zl

	"获取当前文件总行数
	let s:tot_line_num = line('$') - 1
	let s:field_widths = []
	let s:field_types = []
	let s:field_names = []
	let s:field_data_len = []

    let file=expand("%")
    let shortfile = substitute(file, '.txt.new', '', "g")
    let vimpid = substitute(shortfile, '.*-', '', "g")
	let dbdir=$HOME."/.dbtmp/"
	let col_file = dbdir.vimpid."_col.txt"

	"第3列是数据长度，第4列是字段名称长度
    let lines = readfile(col_file)
    
    for line in lines
        let parts = split(line)
        call add(s:field_names,  parts[0])
        call add(s:field_types,  parts[1])
		"s:field_widths 为对齐长度,取数据长度和字段名称长度最大值
		"此处要转换成数字进行比较，否则比较按字符串进行比较
		if str2nr(parts[2]) >= str2nr(parts[3])
        	call add(s:field_widths, str2nr(parts[2]))
		else
        	call add(s:field_widths, str2nr(parts[3]))
		endif
		"s:field_data_len为数据的长度
        call add(s:field_data_len, str2nr(parts[2]))
        call add(s:field_charset, str2nr(parts[4]))
    endfor
endfun

fun! ClearColumnList()
	let s:field_widths = []
	let s:field_types = []
	let s:field_names = []
	let s:field_data_len = []
	let s:field_charset = []
	echo "数据已清空"
endfun

fun! oracle_tui#Update()
	:w
    let file=expand("%")
    let shortfile = substitute(file, '.txt.new', '', "g")
    let cmd = "!clear && db_update_data.sh ".shortfile
	"if exists('s:username') && exists('s:password')
	"	let cmd = cmd." ".s:username." ".s:password 
	"endif

	"此处要catch异常，否则shell被中断后后面的语句不再执行(比如redraw!)
	try
    	"sil execute "!clear && db_update_data.sh ".shortfile
    	sil execute cmd
	catch 
		echo "操作被中断"
		"sleep 3
	endtry

	let status = shell_error
	"1:更新有错误 2:中断执行 0:更新成功 4:数据库连接中断
	"定界符不配对或更新错误需要重新修改时不退出

	if status != 1
		:qall!
		return
	endif

	redraw!

	call oracle_tui#ShowErr("请重新编辑")
endfun

"缩短一列的长度
func! oracle_tui#ReduceColumn()
	let cur_linenum = line('.')
	let line1 = getline('.')
    "要取虚拟列
	let vir_col = virtcol('.')  
	let real_col = col('.')  
	"if strpart(line1, vir_col-1, 1) == " " || strpart(line1, vir_col-1, 1) == "\t"
	"    \ || strpart(line1, vir_col-1, 1) == ""

	"if strpart(line1, vir_col-1, 1) == ""
	"   	echo "Place the cursor over the word"
	"	return
	"endif

	"到第三行
	call cursor(3,vir_col)

	let line = getline('.')
	if strpart(line, vir_col-1, 1) != "-"
		call oracle_tui#ShowErr("请将光标置于列的位置\n")
		return
	endif

	let str = strpart(line,0,vir_col-1)
	let str2 = strpart(line,vir_col-1)

	let start = col('.') 

	if str2 =~ " "
		sil execute "normal / "
		let end = col('.') - 1
	else
		normal $
		let end = col('.')
	endif

	let len = end - start + 1

	set nows
	let null_line = 1
	try
		sil normal /^$
	catch
		sil normal G
		let null_line = 0
	endtry

	if null_line == 1
		let end_line = line('.') - 1
	else
		let end_line = line('.')
	endif

	"silent execute "4 , ".end_line." d"

	"下面这行是按字符
	"let cmd="2,".end_line." s/\\%".start."c.\\{".len."\\}//g"

	"下面如果有汉字会有错位
	"let end=end+1
	"let cmd="2,".end_line." normal! ".start."|d".end."|"
	"silent execute cmd

	let linenums = end_line - 2 
	call cursor(2, start)

	let cmd = "normal! \<C-V>".end."|".linenums."jx"
	
	sil execute cmd

	call cursor(cur_linenum, real_col)
endfunc

"根据光标位置获取字段边界
function! oracle_tui#GetFieldBoundaries(line, pos)
    " 获取传入的行字符串
    let l:line_content = a:line
    let l:pos = a:pos
    
    " 检查位置是否有效
    if l:pos < 1 || l:pos > len(l:line_content)
		call oracle_tui#ShowErr("请将光标放于字段位置")
        return {}
    endif
    
    " 检查字符是否为空格
    if l:line_content[l:pos - 1] == ' '
		call oracle_tui#ShowErr("请将光标放于字段位置")
        return {}
    endif
    
    " 查找字段边界
    let l:start = l:pos
    let l:end = l:pos
    
    " 向左查找字段起始位置
    while l:start > 1 && l:line_content[l:start - 2] != ' '
        let l:start -= 1
    endwhile
    
    " 向右查找字段结束位置
    while l:end < len(l:line_content) && l:line_content[l:end] != ' '
        let l:end += 1
    endwhile
    
    return {'start': l:start, 'end': l:end}
endfunction

let g:last_cut_column_flag = 0

"剪切当前光标所在的所有列
function! oracle_tui#CutColumn()
    let l:col_data = []
    
    " 获取当前光标所在的列位置
    let l:cur_line = line('.')
    let l:vir_col = virtcol('.')
    let l:separator_text = getline(3)
	let real_col = col('.')  
    
    " 获取字段边界
    let l:boundary = oracle_tui#GetFieldBoundaries(l:separator_text, l:vir_col)
    if empty(l:boundary)
        return
    endif
    
    " 计算数据行范围（第2行开始，直到遇到第一个空行）
    let l:start_line = 2
    let l:end_line = line('$')
    
    " 查找第一个空行
    for l:i in range(2, line('$'))
        if getline(l:i) == ''
            let l:end_line = l:i - 1
            break
        endif
    endfor
    

    " 从所有数据行提取对应列的内容
	let line_num = l:end_line - l:start_line
	if l:boundary.start == 1
		let g:last_cut_column_flag = 1
		call cursor(l:start_line,l:boundary.start)
		let l:boundary.end = l:boundary.end + 1
	else
		let g:last_cut_column_flag = 2
		call cursor(l:start_line,l:boundary.start-1)
	endif
	"let cmd = "\<C-V>".l:boundary.end."|".line_num."jx\<CR>:autocmd CursorMoved <buffer> call oracle_tui#ViewHideTitleLines()\<CR>:call cursor(".l:cur_line.",".real_col.")\<CR>"
	"autocmd! CursorMoved <buffer>
	"call feedkeys(cmd, 'n')

	let cmd = "normal! \<C-V>".l:boundary.end."|".line_num."jx"
	
	sil execute cmd

	call cursor(l:cur_line, real_col)

	"下面如果是UTF-8文件则位置错乱，因为是按字符截取
	"autocmd CursorMoved <buffer> call oracle_tui#ViewHideTitleLines()
    "for l:i in range(l:start_line, l:end_line)
    "    let l:line_text = getline(l:i)
    "    
    "    let l:col_content = strpart(l:line_text, l:boundary.start - 1, l:boundary.end - l:boundary.start + 1)
    "    call add(l:col_data, l:col_content)

	"	"删除列
	"	if l:boundary.start == 1
    "    	let l:new_line = strpart(l:line_text, l:boundary.end + 1)
	"	else
    "    	let l:new_line = strpart(l:line_text, 0, l:boundary.start - 2) . 
    "                \ strpart(l:line_text, l:boundary.end)
	"	endif
    "    call setline(l:i, l:new_line)
    "endfor
    "
    "" 将列数据保存到全局变量
    "let g:last_cut_column_flag = l:col_data
endfunction

" 函数：按\p将刚才剪切的所有列复制到当前列后面
function! oracle_tui#PasteColumn()
    "if empty(g:last_cut_column_flag) 
    if g:last_cut_column_flag != 1 && g:last_cut_column_flag != 2
        echo "没有数据粘贴"
        return
    endif

	"autocmd! CursorMoved <buffer>
    
    " 获取当前光标所在的列位置
    let l:cur_line = line('.')
    let l:cur_col = col('.')
    let l:vir_col = virtcol('.')
    
    let l:separator_text = getline(3)

    " 获取当前列的字段边界
    let l:boundary = oracle_tui#GetFieldBoundaries(l:separator_text , l:vir_col)
    if empty(l:boundary)
		return
    else
		if g:last_cut_column_flag == 1
        	let l:paste_pos = l:boundary.end + 1  
		else
        	let l:paste_pos = l:boundary.end  
		endif
    endif

	call cursor(2, l:paste_pos)
	normal! p

	"autocmd CursorMoved <buffer> call oracle_tui#ViewHideTitleLines()
	call cursor(l:cur_line, l:cur_col)

	"不加下面这行会重复显示标题行
	call feedkeys("lh", 'n')

	"let cmd = ":autocmd CursorMoved <buffer> call oracle_tui#ViewHideTitleLines()\<CR>:call cursor(".l:cur_line.",".l:cur_col.")\<CR>"
	"call feedkeys(cmd, 'n')

	"echom "l:boundary.end=".l:boundary.end
    
    "" 计算数据行范围（第2行开始，直到遇到第一个空行）
    "let l:start_line = 2
    "let l:end_line = line('$')
    "
    "" 查找第一个空行
    "for l:i in range(2, line('$'))
    "    if getline(l:i) == ''
    "        let l:end_line = l:i - 1
    "        break
    "    endif
    "endfor
    "
    "" 将剪切的数据粘贴到对应行
    "for l:i in range(l:start_line, l:end_line)
    "    let l:line_idx = l:i - l:start_line
    "    let l:line_text = getline(l:i)
    "    
    "    " 插入剪切的列数据
    "    let l:col_content = g:last_cut_column_flag[l:line_idx]
    "    let l:new_line = strpart(l:line_text, 0, l:paste_pos) . ' '.
    "                \ l:col_content .
    "                \ strpart(l:line_text, l:paste_pos)
    "    
    "    call setline(l:i, l:new_line)
    "endfor
endfunction

let s:start_pos = 0
let s:end_pos = 0

"sil execute "4,".end_line." s/.*/\=strpart(submatch(0),".start_pos.",".len.").\" \".submatch(0)/g"
"根据某列的内容进行排序
"vim中sort n 按数字排序时如果有负数，则排序不正确，所用用sort函数进行排序
func! oracle_tui#Sort(sort_flag)
	let save_cursor = getpos('.')
	let line1 = getline('.')
	let col1 = col('.')
	let vir_col = virtcol('.')
	"if strpart(line1, col1-1, 1) == " " || strpart(line1, col1-1, 1) == "\t"
	"    \ || strpart(line1, col1-1, 1) == ""
	"if line(".") < 4
	"	echo "请将光标放在大于等于第4行"
	"	return 
	"endif

	"if strpart(line1, col1-1, 1) == ""
	"   	echo "请将光标放在单词上"
	"	return
	"endif

	"到第三行
	call cursor(3,vir_col)
	let line3 = getline('.')

	if strpart(line3, vir_col-1, 1) == " " || strpart(line3, vir_col-1, 1) == "" 
    	call setpos('.', save_cursor)
		let vir_col = vir_col -1
		exe "normal! ".vir_col."|"
		call oracle_tui#ShowErr("请将光标放在列上")
		return
	endif

	let str = line3[0: vir_col-1]
	"echo "str=|".str."|"
	"sleep 2
	"sil execute "normal ?--*?b"

	let col2 = match(str, '--*$')

	call cursor(2,col2)
	let line2 = getline('.')


	if (strpart(line2, col2, 1) == " ")
		let type = 1 "数字
	else
		let type = 2 "非数字
	endif

    call setpos('.', save_cursor)

	call oracle_tui#ColSort(a:sort_flag, type)
endfunc

function! NumCompareAsc(i1,i2)
	let str1 = g:column_list[a:i1]
	let str1 = substitute(str1, '[ \t]', '', "g")

	let str3 = g:column_list[a:i2]
	let str3 = substitute(str3, '[ \t]', '', "g")

	if str1 == ""
		let str1 = "-99999999999999999999"
	endif

	if str3 == ""
		let str3 = "-99999999999999999999"
	endif
	
	let v1 = str2float(str1)
	let v2 = str2float(str3)
	return v1 == v2 ? 0 : v1 > v2 ? 1 : -1
endfunc

"按数字反排序
function! NumCompareDesc(i1,i2)
	let str1 = g:column_list[a:i1]
	let str1 = substitute(str1, '[ \t]', '', "g")

	let str3 = g:column_list[a:i2]
	let str3 = substitute(str3, '[ \t]', '', "g")

	if str1 == ""
		let str1 = "-99999999999999999999"
	endif

	if str3 == ""
		let str3 = "-99999999999999999999"
	endif
	let v1 = str2float(str1)
	let v2 = str2float(str3)
	return v1 == v2 ? 0 : v1 < v2 ? 1 : -1
endfunc

"按字母正排序
function! ChrCompareAsc(i1,i2)
	let v1 = g:column_list[a:i1]
	let v2 = g:column_list[a:i2]
	return v1 ==# v2 ? 0 : v1 > v2 ? 1 : -1
endfunc

"按字母反排序
function! ChrCompareDesc(i1,i2)
	let v1 = g:column_list[a:i1]
	let v2 = g:column_list[a:i2]
	return v1 ==# v2 ? 0 : v1 < v2 ? 1 : -1
endfunc

func! oracle_tui#ColSort(sort_flag, data_type)
	let line1 = getline('.')
	let col1 = col('.')
	let vir_col = virtcol('.')
	"if strpart(line1, col1-1, 1) == " " || strpart(line1, col1-1, 1) == "\t"
	"    \ || strpart(line1, col1-1, 1) == ""
	"if strpart(line1, col1-1, 1) == ""
	"   	echo "请将光标放在单词上"
	"	return
	"endif

	"到第三行
	call cursor(3,vir_col)

	let line = getline('.')
   
	let str = strpart(line,0,vir_col-1)
	let str2 = strpart(line,vir_col-1)

	if str =~ " "
		sil execute "normal ? "
		let start = col('.') + 1
	else
		let start = 1
	endif

	if str2 =~ " "
		sil execute "normal / "
		let end = col('.') - 1
	else
		normal $
		let end = col('.')
	endif

	let s:start_pos = start - 1
	let s:end_pos = end - 1

	set nows
	let null_line = 1
	try
		sil normal /^$
	catch
		sil normal G
		let null_line = 0
	endtry

	if null_line == 1
		let end_line = line('.') - 1
	else
		let end_line = line('.')
	endif

	"let reg_save = @@

	let lines = getline(4, end_line)
	let line_num = end_line - 4 + 1

	call cursor(3,start)
	let cmd = "normal! \<C-v>".end."|".line_num."jojy"
	
	sil execute cmd
	let column_list = split(@", '\n')
	let g:column_list = column_list

	let indices = range(len(lines))

	if (a:data_type == 1)
		if a:sort_flag == 0
			call sort(indices, "NumCompareAsc")
		else
			call sort(indices, "NumCompareDesc")
		endif
	else
		if a:sort_flag == 0
			call sort(indices, "ChrCompareAsc")
		else
			call sort(indices, "ChrCompareDesc")
		endif
	endif

	let sorted_lines = map(copy(indices), 'lines[v:val]')

	silent execute "4 , ".end_line." d"

	call append(3, sorted_lines)

	call cursor(3, vir_col-1)
endfunc

func! oracle_tui#Filter(str)
	if a:str == ''
		call oracle_tui#ShowErr("Usage:Filter /str")
		return 
	endif

	if strpart(a:str, 0, 1) != '/'
		call oracle_tui#ShowErr("Usage:Filter /str")
		return 
	endif

    let l:vir_col = virtcol('.')
    let l:separator_text = getline(3)
    
    " 获取字段边界
    let l:boundary = oracle_tui#GetFieldBoundaries(l:separator_text, l:vir_col)
    if empty(l:boundary)
        return
    endif

	let second_line = getline(2)

	let first_char = strpart(second_line, boundary.start-1, 1) 

	if first_char == ' '
		let type = 1 "数字
	else
		let type = 2 "非数字
	endif

    let l:end_line = line('$')
	let match_list = []
    " 查找第一个空行
	let find_flag = 0
    for l:i in range(4, line('$'))
        if getline(l:i) == ''
            let l:end_line = l:i - 1
            break
        endif

		let line_str = getline(l:i)
        let column_str = oracle_tui#GetVColRange(line_str, boundary.start-1, boundary.end)
		let column_str = substitute(column_str, " *$", "", "g")
		if type == 1
			let column_str = substitute(column_str, "^ *", "", "g")
		endif

		let match_str = strpart(a:str, 1)

		if column_str =~# match_str
			let find_flag = 1
			call add(match_list, line_str)
		endif
    endfor
	
	if find_flag == 0
		call oracle_tui#ShowErr("该列不包含:".match_str)
		return 
	endif

	silent execute "4 , ".end_line." d"

	call append(3, match_list)

	call cursor(3, vir_col-1)
endfunc

function! oracle_tui#GetVColRange(str, start_pos, end_pos)
    "let pos = match(a:str, '\%>' . a:end_pos . 'v.*')
	"let before_str = strpart(a:str, 0, pos)

    let before_str = substitute(a:str, '\%>' . a:end_pos . 'v.*', "", "g")
    
    let result = matchstr(before_str, '\%>' . a:start_pos . 'v.*')
    
    return result
endfunction

function! oracle_tui#Hid()
	setlocal syntax=csv
	"必须加下面这行，否则在vim9.2下会有问题
	syntax clear

	setlocal conceallevel=2
	if v:version >= 800
		setlocal concealcursor=nvic
	els
		setlocal concealcursor=nvc
	endif
	"如果超过缺省3000长度行，则后面的内容无法转换
	setlocal synmaxcol=100000
	"隐藏第一列
	syn match HiddenRowID /^[^]*/ conceal
	"syn match HiddenRowID /"/ conceal
	syn match Substitute // conceal cchar=|
	"NBSP字符显示成-
	"syn match Substitute / / conceal cchar=-
	"字符显示成?
	syn match Substitute // conceal cchar=?

	"\t显示成?
	syn match Substitute /	/ conceal cchar=?
	" 设置隐藏级别
	"set conceallevel=0  " 不隐藏（默认）
	"set conceallevel=1  " 隐藏，但显示一个字符
	"set conceallevel=2  " 完全隐藏
	"set conceallevel=3  " 完全隐藏，即使光标在行上

	" 控制光标在哪些模式下显示隐藏文本
	"set concealcursor=    " 所有模式下都隐藏（默认）
	"set concealcursor=n   " Normal 模式下显示隐藏文本
	"set concealcursor=v   " Visual 模式下显示
	"set concealcursor=i   " Insert 模式下显示
	"set concealcursor=c   " Command-line 模式下显示
	"set concealcursor=nc  " Normal 和 Command-line 模式下显示
	"set concealcursor=nv  " Normal 和 Visual 模式下显示
	redraw!
endfun

"恢复隐藏
function! oracle_tui#NoHid()
	"syn clear match HiddenRowID 
	set conceallevel=0
endfun

"第一行不允许修改
function! oracle_tui#ProtectFirstLine()
	"if line('.') == 1 
	"	setlocal readonly
	"	echo "第一行不能修改"
	"else
	"	setlocal noreadonly
	"endif
	nnoremap <buffer> <expr> dd line('.')==1 ? '' : 'dd'
	"nnoremap <expr> \cl line('.')==1 ? '' : '\cl'
	nnoremap <buffer> <expr> i line('.')==1 ? '' : 'i'
	nnoremap <buffer> <expr> I line('.')==1 ? '' : 'I'
	nnoremap <buffer> <expr> a line('.')==1 ? '' : 'a'
	nnoremap <buffer> <expr> A line('.')==1 ? '' : 'A'
	"nnoremap <expr> x line('.')==1 ? '' : 'x'
	"nnoremap <expr> X line('.')==1 ? '' : 'X'
	nnoremap <buffer> <expr> r line('.')==1 ? '' : 'r'
	nnoremap <buffer> <expr> R line('.')==1 ? '' : 'R'
	nnoremap <buffer> <expr> S line('.')==1 ? '' : 'S'
	nnoremap <buffer> <expr> s line('.')==1 ? '' : 's'
	nnoremap <buffer> <expr> c line('.')==1 ? '' : 'c'
	nnoremap <buffer> <expr> C line('.')==1 ? '' : 'C'
	"nnoremap <expr> O line('.')==1 ? '' : 'O'
	"nnoremap <buffer> <expr> P line('.')==1 ? '' : 'P'
	"nnoremap <buffer> <expr> D line('.')==1 ? '' : 'D'
endfunction

let s:head_update_buffers = []
"与原始文件比较显示不同
let s:show_diff_flag = 0
function! oracle_tui#ShowDiff()
	"nnoremap <silent> <buffer> r R
	
	if s:show_diff_flag == 0
		let view = winsaveview()
		let file=expand("%")
		let oldfile = substitute(file, "new$", "old", "g")
		diffthis
		"echo "oldfile=".oldfile
		"sleep 3
		execute "vert diffsplit ".oldfile
		"call add(s:head_update_buffers, bufnr('%'))
		hid
		set foldcolumn=0
		setlocal nofoldenable
		"取消两个屏幕上下一起滚动
		"保持水平和垂直同步
		"set scrollbind
		"取消垂直同步，保持水平同步
		"set nocursorbind
		let s:show_diff_flag = 1
		"不加这行会显示标题行
		call winrestview(view)
	else
		diffoff
		let s:show_diff_flag = 0

		if s:show_update_title_flag == 1
			set sbo=hor
		endif
	endif
endfunction

function! oracle_tui#HorSplitHeader()
	let file=expand("%")
	let cmd = "0read !head -1 ".file
	new split

	setlocal buftype=nofile
	setlocal bufhidden=delete
	setlocal noswapfile
	
	setlocal nowrap
	setlocal cul

	"call add(s:head_update_buffers, bufnr('%'))

	sil execute cmd
	Hid
	2d
	resize 1

	set scrollopt=hor
	set scrollbind

	wincmd j
	set scrollopt=hor
	set scrollbind
endfunction

"修改一行内容时能实时显示修改内容(只对插入模式有效(输入后按ESC),x,X模式无效)
function! oracle_tui#PreserveView()
	let view = winsaveview()
	diffupdate
	call winrestview(view)
endfunction

function! oracle_tui#CloseAllBuffs()
	for bufnum in s:head_update_buffers
		if bufexists(bufnum)
			"echo 'bwipeout! '.bufnum
			"sleep 2
			execute 'bwipeout! '.bufnum
		endif
	endfor
endfunction

"跳到下一个字段
function! oracle_tui#JumpNextColumn()
	if strpart(getline('.'),col('.')) =~ ""
    	"要有3个lll才行
		"exec "normal flllR" 
		exec "normal f" 
		call cursor(line('.'),col('.')+1)
	else
		try
			if line('.') == line('$')
				throw 'LastLineError'
			else
				call cursor(line('.')+1,1)
			endif
		catch /^LastLineError$/
			call oracle_tui#ShowErr("到文件尾部")
			echo ""
			return 
		endtry
	endif
endfunction

function! oracle_tui#GetCurrentColumn()
    let line = getline('.')
    let col = col('.') - 1
    
    if col < 0
        return 0
    endif
    
    let before_cursor = strpart(line, 0, col)
    let comma_count = 0
    let i = 0
    while i < strlen(before_cursor)
        if before_cursor[i] == ''
            let comma_count += 1
        endif
        let i += 1
    endwhile
    
    return comma_count + 1
endfunction

"跳到指定的列
function! oracle_tui#JumpToColumn(column)
    let line = getline('.')
    let col_num = a:column
    
    if col_num <= 1
        call cursor(line('.'), 1)
        return
    endif
    
    let comma_pos = -1
    let found = 0
    let i = 0
    
    while i < strlen(line)
        if line[i] == ''
            let found += 1
            if found == col_num - 1
                let comma_pos = i
                break
            endif
        endif
        let i += 1
    endwhile
    
    if comma_pos >= 0
        call cursor(line('.'), comma_pos + 2)
		exec "normal! lR"
		startreplace
    endif
endfunction

"跳到下一个分隔符
function! oracle_tui#EditColumnAfter2()
	"获取当前列数
	let current_column_num = oracle_tui#GetCurrentColumn()
	let next_column_num = current_column_num + 1

	let result = oracle_tui#AlignColumnReal() 
    if result == 0
		"call oracle_tui#EditColumnAfter()
		"跳到下一列
		call oracle_tui#JumpToColumn(next_column_num)
	endif
endfunction

"跳到下一个分隔符
function! oracle_tui#EditColumnBefore2()
	"获取当前列数
	let current_column_num = oracle_tui#GetCurrentColumn()
	let next_column_num = current_column_num - 1

	let result = oracle_tui#AlignColumnReal() 
    if result == 0
		"call oracle_tui#EditColumnBefore()
		"跳到下一列
		call oracle_tui#JumpToColumn(next_column_num)
	endif
endfunction

"跳到下一个分隔符
function! oracle_tui#EditColumnAfter()
	"if strpart(getline('.'),col('.')-1) =~ ""
	if strpart(getline('.'),col('.')) =~ ""
    	"要有3个lll才行
		"exec "normal flllR" 
		exec "normal f" 
		call cursor(line('.'),col('.')+1)
		"call oracle_tui#CursorMovedForUpdate()
		startreplace
	else
		try
			if line('.') == line('$')
				throw 'LastLineError'
			else
				call cursor(line('.')+1,1)
				"call oracle_tui#CursorMovedForUpdate()
				"call cursor(line('.')+1,21)
    			let cur_col = col('.')
    			let line_text = getline('.')
    			let first_comma = stridx(line_text, '')

    			if cur_col <= first_comma + 1
					"此处要加3才行
    			    call cursor(line('.'), first_comma + 3)
    			endif
			endif
		catch /^LastLineError$/
			call oracle_tui#ShowErr("到文件尾部")
			echo ""
			return 
		endtry
		if getline('.')[col('.')-1] == ''
			exec "normal I"
			startinsert
		else
			exec "normal R" 
			startreplace
		endif
	endif
endfunction

"跳到前一个分隔符(插入模式)
function! oracle_tui#EditColumnBefore()
	"如果光标在分隔符上后移一位
	if strpart(getline('.'),col('.')-1,1) == ""
		call cursor(line('.'),col('.')+1)
		"call oracle_tui#CursorMovedForUpdate()
	endif

	"如果当前光标前面有列分隔符,跳到前两个分隔符的后一位
	if strpart(getline('.'), 0, col('.')) =~ ""
		exec "normal F" 
		call cursor(line('.'),col('.')-1)
		"call oracle_tui#CursorMovedForUpdate()

		if strpart(getline('.'), 0, col('.')) =~ ""
			exec "normal F" 
			call cursor(line('.'),col('.')+1)
			"call oracle_tui#CursorMovedForUpdate()
			startreplace
		else
			"到行首
			call cursor(line('.'),1)
			call oracle_tui#CursorMovedForUpdate()
			startreplace
		endif
	else
		try
			if line('.') == 2
				throw 'FirstLineError'
			else
				"跳到上一行的行尾
				normal! k$
			endif
		catch /^FirstLineError$/
			call oracle_tui#ShowErr("到文件首部")
			echo ""
			return 
		endtry

		if strpart(getline('.'), 0, col('.')) =~ ""
			exec "normal F" 
			call cursor(line('.'),col('.')+1)
			"call oracle_tui#CursorMovedForUpdate()
			startreplace
		else
			"到行首
			call cursor(line('.'),1)
			call oracle_tui#CursorMovedForUpdate()
			startreplace
		endif
	endif
endfunction

"跳到前一个分隔符
function! oracle_tui#JumpBeforeColumn()
	"如果光标在分隔符上后移一位
	if strpart(getline('.'),col('.')-1,1) == ""
		call cursor(line('.'),col('.')+1)
		"call oracle_tui#CursorMovedForUpdate()
	endif

	"如果当前光标前面有列分隔符,跳到前两个分隔符的后一位
	"if strpart(getline('.'), 0, col('.')) =~ ""
	if strpart(getline('.'), 19, col('.')-19) =~ ""
		if strpart(getline('.'),col('.')-2,1) != ""
			exec "normal F" 
			call cursor(line('.'),col('.')+1)
			"call oracle_tui#CursorMovedForUpdate()
		else
			exec "normal F" 
			call cursor(line('.'),col('.')-1)
			"call oracle_tui#CursorMovedForUpdate()

			if strpart(getline('.'), 0, col('.')) =~ ""
				exec "normal F" 
				call cursor(line('.'),col('.')+1)
				"call oracle_tui#CursorMovedForUpdate()
				"startreplace
			else
				"到行首
				call cursor(line('.'),1)
				call oracle_tui#CursorMovedForUpdate()
				"startreplace
			endif
		endif
	else
		if strpart(getline('.'),col('.')-2,1) != ""
			exec "normal F" 
			call cursor(line('.'),col('.')+1)
		else
			try
				if line('.') == 2
					throw 'FirstLineError'
				else
					"跳到上一行的行尾
					normal! k$
				endif
			catch /^FirstLineError$/
				call oracle_tui#ShowErr("到文件首部")
				echo ""
				return 
			endtry

			if strpart(getline('.'), 0, col('.')) =~ ""
				exec "normal F" 
				call cursor(line('.'),col('.')+1)
				"call oracle_tui#CursorMovedForUpdate()
				"startreplace
			else
				"到行首
				call cursor(line('.'),1)
				call oracle_tui#CursorMovedForUpdate()
				"startreplace
			endif
		endif
	endif
endfunction

function! oracle_tui#NewLine()
	"normal o
    let first_cont = getline(1)
   	call setline(line('.'), first_cont)
	:s/[^]/ /g
	:s/^[^]*/                  /g
	"normal! 0
	call oracle_tui#CursorMovedForUpdate()
	startreplace
endfunction

function! oracle_tui#Visual_paste(type)
	let regname = v:register
	let content = getreg(regname)

	let lines = split(content, "\n", 1)
    let line_count_reg = len(lines)
	let line_count_sel = line("'>'") - line("'<") + 1

	if visualmode() ==# ''
		if line_count_reg != line_count_sel
			redraw!
			call oracle_tui#ShowErr("选中的行数与寄存器行数不一致")
			return
		endif
	endif

    let s:visual_insert = {
        \ 'start_line': line("'<"),
        \ 'end_line': line("'>")
        \ }

	"执行normal! gv之后v:register 会变
	normal! gv
	if a:type == 'p'
		if regname == '"' 
			execute 'normal! p'
		else
			execute 'normal! "' . regname . 'p'
		endif
	else
		if regname == '"' 
			execute 'normal! P'
		else
			execute 'normal! "' . regname . 'P'
		endif
	endif
	call oracle_tui#AlignColumnReal() 
endfunction

function! oracle_tui#Normal_paste(type)
	"v:register 说明
	"如果敲入 p v:register就等于"  
	"如果敲入 "ap v:register就等于a  
	"如果敲入 "bp v:register就等于b  
	"如果敲入 "cp v:register就等于c  
	"以此类推
	let content = getreg(v:register)

	let lines = split(content, "\n", 1)
	"如果是整行复制,len(lines)会比实际复制的行数多1,对齐时行数范围刚好覆盖复制的行数
    let line_count_reg = len(lines)
	let start_line = line('.')
	let end_line = start_line + line_count_reg - 1

    let s:visual_insert = {
        \ 'start_line': start_line,
        \ 'end_line': end_line
        \ }

	if a:type == 'p'
		if v:register == '"'
			execute 'normal! p'
		else
			execute 'normal! "' . v:register . 'p'
		endif
	else
		if v:register == '"'
			execute 'normal! P'
		else
			execute 'normal! "' . v:register . 'P'
		endif
	endif
	call oracle_tui#AlignColumnReal() 
endfunction

function! oracle_tui#VisualSaveState()
    let s:visual_insert = {
        \ 'start_line': line("'<"),
        \ 'end_line': line("'>")
        \ }
endfunction

function! oracle_tui#VisualSaveStateX()
	"如果是在一行，则不会触发TextChanged事件
	if line("'<") <= 1
		redraw!
		call oracle_tui#ShowErr("不能删除第一行")
		return
	endif

	if visualmode() ==# ''
    	let s:visual_insert = {
    	    \ 'start_line': line("'<"),
    	    \ 'end_line': line("'>")
    	    \ }
		normal! gvx
		call oracle_tui#AlignColumnReal()
	elseif visualmode() ==# 'v'
		redraw!
		call oracle_tui#ShowErr("v模式下不能删除!")
		return
	else
		normal! gvx
	endif
endfunction

function! oracle_tui#VisualSaveStateD()
	"如果是在一行，则不会触发TextChanged事件
	if line("'<") <= 1
		redraw!
		call oracle_tui#ShowErr("不能删除第一行")
		return
	endif

	if visualmode() ==# ''
    	let s:visual_insert = {
    	    \ 'start_line': line("'<"),
    	    \ 'end_line': line("'>")
    	    \ }
		normal! gvD
		call oracle_tui#AlignColumnReal()
	elseif visualmode() ==# 'v'
		redraw!
		call oracle_tui#ShowErr("v模式下不能删除!")
		return
	else
		normal! gvD
	endif
endfunction

"如果是数字,删除之后光标后移一个字符
function! oracle_tui#Process_x()
    let current_line = getline('.')
    let cursor_col = col('.') - 1
    
    " 找出光标所在的字段
    let fields = split(current_line, '', 1)
    let current_field = 0
    let pos = 0
    
    for i in range(len(fields))
        if cursor_col >= pos && cursor_col <= pos + len(fields[i])
            let current_field = i
            break
        endif
        let pos += len(fields[i]) + 1
    endfor

	call oracle_tui#AlignColumnReal()
	if s:field_types[current_field] == 2 || s:field_types[current_field] == 100 || s:field_types[current_field] == 101
		if getline('.')[col('.')-1] == ''
			normal! h
		else
			normal! l
		endif
	endif
endfunction

let s:title_line = ''
function! oracle_tui#AlignColumnReal()
    if exists('s:visual_insert') 
		let type = 1
	else
		"normal x X dw de D 单行
		let type = 2
    	let s:visual_insert = {
    	    \ 'start_line': line('.'),
    	    \ 'end_line': line('.')
    	    \ }
	endif
    let current_col = virtcol('.')

	let file=expand("%")
	let shortfile=substitute(file, ".*/", "", "g")
	if shortfile =~# "^p_c_" || shortfile =~# "^c_"
		let lob_file_flag = 1
	else
		let lob_file_flag = 0
    endif

	let view = winsaveview()

    "let save_cursor = getpos('.')
    
	let more_flag = 0
    " 处理每一行（从第二行开始）
	if s:visual_insert.start_line <= 1
		normal! u
		redraw!
		call oracle_tui#ShowErr("不能修改标题行")
		"要加下面这行
    	unlet s:visual_insert
		return 1
	endif

    for lnum in range(s:visual_insert.start_line, s:visual_insert.end_line)
		let extend_lob_file_flag = 0
        let line = getline(lnum)
        let fields = split(line, '', 1)
		if len(fields) != len(s:field_names)
			normal! u
			redraw!
			if len(fields) < len(s:field_names)
				call oracle_tui#ShowErr("一次只能修改一列")
			else
				call oracle_tui#ShowErr("列数超出字段个数")
			endif
			"要加下面这行
    		unlet s:visual_insert
			return 1
		endif

        let new_fields = []

		"lob类型字段超过原来长度数组
    	let add_len = {}

    	" 对齐每个字段
    	for i in range(len(fields))
			"先去掉尾部的NBSP字符，再将剩余的NBSP字符替换成空格
    		let field = substitute(fields[i], ' *$', '', 'g')
    		let field = substitute(field, ' ', ' ', 'g')

			if s:field_types[i] == 2 || s:field_types[i] == 100 || s:field_types[i] == 101
				"数字类型
    	    	let field = substitute(field, ' ', '', 'g')
			elseif s:field_types[i] == 96
				"如果是char类型，如果都是空格，不变，否则去掉后面空格
				if field !~ "^  *$"
    	    		let field = substitute(field, ' *$', '', 'g')
				endif
			elseif s:field_types[i] != 1 && s:field_types[i] != 112 
				"varchar2/nvarchar2/clob/nclob 不能去后面空格
    	    	let field = substitute(field, ' *$', '', 'g')
			endif

			"数字右对齐
			if s:field_types[i] == 2 || s:field_types[i] == 100 || s:field_types[i] == 101
				"右对齐
    	    	call add(new_fields, repeat(' ', s:field_widths[i] - strwidth(field)).field)
			elseif (s:field_types[i] == 112 ||
				\   s:field_types[i] == 8 || 
				\   s:field_types[i] == 113 || 
				\   s:field_types[i] == 24)
				"lob
				if (s:field_types[i] == 112 ||
					\ s:field_types[i] == 8 ||
					\ s:field_types[i] == 113 ||
					\ s:field_types[i] == 24 )
					\ && s:lob_substitute_flag == 1
					"如果替换后lob字段是文件名，则用替换前备份的字段内容恢复
					let idx = printf("'%d,%d'", lnum, i)
    	    		call add(new_fields, s:field_lob_content[idx])
				else
					if (s:field_types[i] == 112 ||
						\ s:field_types[i] == 8 ||
						\ s:field_types[i] == 113 ||
						\ s:field_types[i] == 24 )
						\ && lob_file_flag == 1
						"let lob_old_filename = printf("<lob_%d_%d_%d.txt.old>", pid,cur_line_num-1,i)
						"let lob_new_filename = printf("<lob_%d_%d_%d.txt.new>", pid,cur_line_num-1,i)
						"if field != lob_old_filename && field != lob_new_filename 
						"	call oracle_tui#ShowErr("lob字段只能通过Ctrl+a来修改")
						"	return
						"endif
    	    			let field = substitute(field, ' ', '', 'g')
						if field !~# '^<lob_.*.txt.old>$' && field !~# '^<lob_.*.txt.new>$' && field != ''
							normal! u
							redraw!
    						unlet s:visual_insert
							call oracle_tui#ShowErr("该字段只能通过Ctrl+a来修改")
							"防止光标不动时出现提示
							let s:prompt_flag = s:field_types[i]
							return 1
						endif
					endif

					if strwidth(field)  > s:field_widths[i] 
					 	let s:field_widths[i] = strwidth(field)
    	    			call add(new_fields, field)
						"let add_len[i] = strwidth(field) - s:field_widths[i]
						let extend_lob_file_flag = 1
					else
						if lob_file_flag == 1 
    	    				call add(new_fields, field.repeat(' ', s:field_widths[i] - strwidth(field)))
						else
    	    				call add(new_fields, field.repeat(' ', s:field_widths[i] - strwidth(field)))
						endif
						"let add_len[i] = 0
					endif
				endif
			elseif s:field_types[i] == 1 || s:field_types[i] == 96
				"char/nchar/varchar2/nvarchar2 填充不间断空格 其他填充空格
    	    	call add(new_fields, field.repeat(' ', s:field_widths[i] - strwidth(field)))
			else
				"左对齐
    	    	call add(new_fields, field.repeat(' ', s:field_widths[i] - strwidth(field)))
			endif

			if s:field_types[i] == 96 && field =~ "^  *$" 
				if  strwidth(field) > str2nr(s:field_widths[i])
					"如果都是空格的char类型，判断是否大于显示宽度
					let more_flag = 1
				endif
			elseif strwidth(field) > str2nr(s:field_data_len[i]) 
				\ && s:field_types[i] != 112 
				\ && s:field_types[i] != 8
				\ && s:field_types[i] != 113 
				\ && s:field_types[i] != 24
				let more_flag = 1
			endif
    	endfor
    	
    	" 重新组合行
    	call setline(lnum, join(new_fields, ''))
    endfor

	"如果有一列lob字段超过原来长度，则扩展整个文件该列的长度
	if extend_lob_file_flag == 1
    	for lnum in range(1, line('$'))
			"下面应该不要
			"if lnum >= s:visual_insert.start_line && lnum <= s:visual_insert.end_line
			"	continue
			"endif

    	    let line = getline(lnum)
    	    let fields = split(line, '', 1)
    	    let new_fields = []
    	    
    	    " 对齐每个字段
    		for i in range(len(fields))
    			let field = fields[i]
				if (s:field_types[i] == 112 ||
					\ s:field_types[i] == 8 ||
					\ s:field_types[i] == 113 ||
					\ s:field_types[i] == 24)
					"lob
    		    	call add(new_fields, field.repeat(' ', s:field_widths[i] - strwidth(field)))
				else
					"左对齐
    		    	call add(new_fields, field)
				endif
    		endfor
    	    
			if (lnum == 1)
				let s:title_line = join(new_fields, '')
			endif
    	    " 重新组合行
    	    call setline(lnum, join(new_fields, ''))
    	endfor
	endif
    
    "call setpos('.', save_cursor)

	diffupdate
	call winrestview(view)
	"要跳到虚拟列才能回到原来的位置
	exe "normal! ".current_col."|"

	redraw!
    
    unlet s:visual_insert
	if s:lob_substitute_flag == 1
		let s:lob_substitute_flag = 0
		let s:field_lob_content = {}
	endif

	if extend_lob_file_flag == 1
		if s:show_update_title_flag == 1
			wincmd k
    		call setline(1, s:title_line)
			Hid

			wincmd j
			normal! zl
			normal! zh
		endif
	endif

	if more_flag == 1
		"要加个换行符,让用户敲回车,否则信息会一闪而过
		call oracle_tui#ShowErr("修改后超出当前列长度\n")
		return 1
	endif

	return 0
endfunction

"对齐整个文件中所有字段
function! oracle_tui#AlignColumn()
    let save_cursor = getpos('.')

    for lnum in range(2, line('$'))
        let line = getline(lnum)
        let fields = split(line, '', 1)
        let new_fields = []
        
        "对于lob类型字段，取他们的最大长度
    	for i in range(len(fields))
			if (s:field_types[i] == 112 ||
			    \ s:field_types[i] == 8 ||
			    \ s:field_types[i] == 113 ||
			    \ s:field_types[i] == 24) 
				if len(fields[i] )  > str2nr(s:field_widths[i])
					let s:field_widths[i] = len(fields[i] )
				endif
			endif
    	endfor
    endfor
    
	let more_flag = 0
    for lnum in range(1, line('$'))
        let line = getline(lnum)
        let fields = split(line, '', 1)
        let new_fields = []
        
        " 对齐每个字段
    	for i in range(len(fields))
			"先去掉尾部的NBSP字符，再将剩余的NBSP字符替换成空格
    		let field = substitute(fields[i], ' *$', '', 'g')
    		let field = substitute(field, ' ', ' ', 'g')

			"数字类型
			if s:field_types[i] == 2 || s:field_types[i] == 100 || s:field_types[i] == 101
    	    	let field = substitute(field, ' ', '', 'g')
			endif

			"如果是char类型，如果都是空格，不变，否则去掉后面空格
			if s:field_types[i] == 96
				if field =~ "^  *$"
					let field = " "
				else
    	    		let field = substitute(field, ' *$', '', 'g')
				endif
			endif

			"数字右对齐
			if s:field_types[i] == 2 || s:field_types[i] == 100 || s:field_types[i] == 101
				"右对齐
    	    	call add(new_fields, repeat(' ', s:field_widths[i] - strwidth(field)).field)
			elseif (s:field_types[i] == 112 ||
				\   s:field_types[i] == 8 || 
				\   s:field_types[i] == 113 || 
				\   s:field_types[i] == 24 )
				"lob
				if (s:field_types[i] == 112 ||
					\ s:field_types[i] == 8 ||
					\ s:field_types[i] == 113 ||
					\ s:field_types[i] == 24 )
					\ && s:lob_substitute_flag == 1
					"如果替换后lob字段是文件名，则用替换前备份的字段内容恢复
					let idx = printf("'%d,%d'", lnum, i)
    	    		call add(new_fields, s:field_lob_content[idx])
				else
					if (s:field_types[i] == 112 ||
						\ s:field_types[i] == 8 ||
						\ s:field_types[i] == 113 ||
						\ s:field_types[i] == 24 )
						\ && lob_file_flag == 1
						"let lob_old_filename = printf("<lob_%d_%d_%d.txt.old>", pid,cur_line_num-1,i)
						"let lob_new_filename = printf("<lob_%d_%d_%d.txt.new>", pid,cur_line_num-1,i)
						"if field != lob_old_filename && field != lob_new_filename 
						"	call oracle_tui#ShowErr("lob字段只能通过Ctrl+a来修改")
						"	return
						"endif
    	    			let field = substitute(field, ' ', '', 'g')
						if field !~# '^<lob_.*.txt.old>$' && field !~# '^<lob_.*.txt.new>$' && field != ''
							normal! u
							redraw!
    						unlet s:visual_insert
							call oracle_tui#ShowErr("该字段只能通过Ctrl+a来修改")
							"防止光标不动时出现提示
							let s:prompt_flag = s:field_types[i]
							return 1
						endif
					endif

					if strwidth(field)  > s:field_widths[i] 
					 	let s:field_widths[i] = strwidth(field)
    	    			call add(new_fields, field)
						"let add_len[i] = strwidth(field) - s:field_widths[i]
						let extend_lob_file_flag = 1
					else
						if lob_file_flag == 1 
    	    				call add(new_fields, field.repeat(' ', s:field_widths[i] - strwidth(field)))
						else
    	    				call add(new_fields, field.repeat(' ', s:field_widths[i] - strwidth(field)))
						endif
						"let add_len[i] = 0
					endif
				endif
			elseif s:field_types[i] == 1
				"varchar2/nvarchar2 填充不间断空格 其他填充空格
    	    	call add(new_fields, field.repeat(' ', s:field_widths[i] - strwidth(field)))
			else
				"左对齐
    	    	call add(new_fields, field.repeat(' ', s:field_widths[i] - strwidth(field)))
			endif

			"判断大于数据的最大长度,而不是判断显示的长度
			if strwidth(field) > str2nr(s:field_data_len[i]) 
				\ && s:field_types[i] != 112 
				\ && s:field_types[i] != 8
				\ && s:field_types[i] != 113 
				\ && s:field_types[i] != 24
				let more_flag = 1
			endif
    	endfor
        
        " 重新组合行
        call setline(lnum, join(new_fields, ''))
    endfor
    
    call setpos('.', save_cursor)

	"redraw!
	if more_flag == 1
		"要加个换行符,让用户敲回车,否则信息会一闪而过
		call oracle_tui#ShowErr("有列超出当前列长度")
	endif
endfunction

let s:show_update_title_flag = 0
function! oracle_tui#ShowUpdateTitle()
	if s:show_update_title_flag == 0
		if winwidth(0) < &columns
			call oracle_tui#ShowErr("有垂直分割窗口,不能显示标题行")
			return
		endif

		let top_line = line("w0")
		let cur_line = line('.')
		let cur_col = col('.')

		:w
		let s:show_update_title_flag = 1
		let file=expand("%")
		let cmd = "0read !head -1 ".file
		new split

		setlocal buftype=nofile
		setlocal bufhidden=delete
		setlocal noswapfile
		
		setlocal nowrap
		setlocal nocul
		setlocal nonu

		"call add(s:head_update_buffers, bufnr('%'))

		sil execute cmd
		Hid
		2d
		resize 1

		set scrollbind
		set sbo=hor
		call cursor(1,cur_col)
		"let &l:stl="%#Normal#".repeat('=',winwidth(0))
		"highlight MyStatusLine ctermbg=Yellow ctermfg=Black
		"let &l:stl="%#MyStatusLine#".repeat('=',winwidth(0))
		let &l:stl="%#Comment#".repeat('=',winwidth(0))

		wincmd j
		set scrollbind
		set sbo=hor
		if top_line <= 2
			"将第二行置为窗口第一行
			execute "normal! 2zt"
		endif
		call cursor(cur_line,cur_col)
		"要加下面这行，否则水平位置不同步
		normal! zl
		normal! zh

		call oracle_tui#UpdateHideTitleLines()
		call oracle_tui#UpdateMapHideTitleLines()

		autocmd CursorMoved <buffer> call oracle_tui#UpdateHideTitleLines()
	else
		let save_cursor = getpos('.')
		let s:show_update_title_flag = 0
		wincmd k
		q
		"bwipeout

    	let current_line = line('.')
    	let win_height = winheight(0)
    	let screen_line = winline()
    	
    	if current_line < win_height && current_line > screen_line
    	    normal! gg
			"必须加下面这行，否则按0时向右移动屏幕时会有问题
			normal! 20zl
			call setpos('.', save_cursor)
    	endif

		autocmd! CursorMoved <buffer>
		call oracle_tui#UnMapHideTitleLines()
	endif
endfunction

let s:show_view_title_flag = 0
function! oracle_tui#ShowViewTitle()
	if s:show_view_title_flag == 0
		if winwidth(0) < &columns
			call oracle_tui#ShowErr("有垂直分割窗口,不能显示标题行")
			return
		endif

		let cur_line = line('.')
		let cur_col = col('.')
		let top_line = line("w0")

		let s:show_view_title_flag = 1
		set sbo=hor
		sp 
		resize 3 
		setlocal nocul
		"在vim7.2环境下有问题
		"call cursor(1,cur_col)
		exec "normal! gg" 
		"let &l:stl="%#Normal#".repeat('=',winwidth(0))
		"highlight MyStatusLine ctermbg=Yellow ctermfg=Black
		let &l:stl="%#Comment#".repeat('=',winwidth(0))

		wincmd j
		if top_line <= 4
			"将第四行置为窗口第一行
			execute "normal! 4zt"
		endif
		call cursor(cur_line,cur_col)
		"要加下面这行，否则水平位置不同步
		normal! zl
		normal! zh

		call oracle_tui#ViewHideTitleLines()
		call oracle_tui#ViewMapHideTitleLines()

		autocmd CursorMoved <buffer> call oracle_tui#ViewHideTitleLines()
	else
		let save_cursor = getpos('.')
		let s:show_view_title_flag = 0
		wincmd k
		q

    	let current_line = line('.')
    	let win_height = winheight(0)
    	let screen_line = winline()
    	
    	if current_line < win_height && current_line > screen_line
    	    normal! gg
			call setpos('.', save_cursor)
    	endif

		autocmd! CursorMoved <buffer>
		call oracle_tui#UnMapHideTitleLines()
	endif
endfunction

function! oracle_tui#ViewHideTitleLines()
    let top_line = line('w0')

    if top_line == 1
        " 如果显示第1行，向下滚动2行
        execute "normal! 3\<C-e>"
    elseif top_line == 2
        " 如果显示第2行，向下滚动1行
        execute "normal! 2\<C-e>"
    elseif top_line == 3
        " 如果显示第2行，向下滚动1行
        execute "normal! \<C-e>"
    endif
endfunction

function! oracle_tui#UpdateHideTitleLines()
    let top_line = line('w0')

    if top_line == 1
        execute "normal! \<C-e>"
    endif
endfunction

function! oracle_tui#ViewMapHideTitleLines()
	nnoremap <buffer> <silent> <C-b> <C-b>:call oracle_tui#ViewHideTitleLines()<CR>
	nnoremap <buffer> <silent> <PageUp> <PageUp>:call oracle_tui#ViewHideTitleLines()<CR>
	nnoremap <buffer> <silent> H H:call oracle_tui#ViewHideTitleLines()<CR>
	nnoremap <buffer> <silent> <C-u> <C-u>:call oracle_tui#ViewHideTitleLines()<CR>
	nnoremap <buffer> <silent> <C-y> <C-y>:call oracle_tui#ViewHideTitleLines()<CR>
endfunction

function! oracle_tui#UpdateMapHideTitleLines()
	nnoremap <buffer> <silent> <C-b> <C-b>:call oracle_tui#UpdateHideTitleLines()<CR>
	nnoremap <buffer> <silent> <PageUp> <PageUp>:call oracle_tui#UpdateHideTitleLines()<CR>
	nnoremap <buffer> <silent> H H:call oracle_tui#UpdateHideTitleLines()<CR>
	nnoremap <buffer> <silent> <C-u> <C-u>:call oracle_tui#UpdateHideTitleLines()<CR>
	nnoremap <buffer> <silent> <C-y> <C-y>:call oracle_tui#UpdateHideTitleLines()<CR>
endfunction

function! oracle_tui#UnMapHideTitleLines()
	nunmap <buffer>  <C-b>
	nunmap <buffer>  <PageUp>
	nunmap <buffer>  H
	nunmap <buffer>  <C-u>
	nunmap <buffer>  <C-y>
endfunction

let s:show_nullchar_flag = 0
function! oracle_tui#ShowNullChar()
	if s:show_nullchar_flag == 0
		syn match Substitute / / conceal cchar=-
		let s:show_nullchar_flag = 1
	else
		syn match Substitute / / conceal cchar= 
		let s:show_nullchar_flag = 0
		Hid
	endif
endfunction

"如果用Ctrl+a打开一个新的窗口后原来的显示空字符会失效
"用下面语句保证新窗口退出后能正常显示空字符
"autocmd BufNewFile,BufRead,BufEnter,VimEnter <buffer> call oracle_tui#ReShowNullChar() 
function! oracle_tui#ReShowNullChar()
	if s:show_nullchar_flag == 1
		syn match Substitute / / conceal cchar=-
	endif
endfunction

let s:current_pipe_field = 0
let s:current_pipe_line = 0
let s:original_field_content = ''
function! oracle_tui#PipeFieldEdit()
    " 获取当前行内容和光标位置
	let file=expand("%")
	let shortfile=substitute(file, ".*/", "", "g")
	if shortfile =~# "^p_c_" || shortfile =~# "^c_"
		let lob_file_flag = 1
	else
		let lob_file_flag = 0
    endif

	let pid = substitute(file, ".*-", "", "g")
	let pid = substitute(pid, ".txt.new", "", "g")
	let lob_file=$HOME."/.dbtmp/lob_res_".pid.".txt"
    let current_line = getline('.')
    let cursor_col = col('.') - 1
	let linenum = line('.')
    
    " 找出光标所在的字段
    let fields = split(current_line, '', 1)
    let current_field = 0
    let pos = 0
    
	sil w
    for i in range(len(fields))
        if cursor_col >= pos && cursor_col <= pos + len(fields[i])
            let current_field = i
            break
        endif
        let pos += len(fields[i]) + 1
    endfor
    
    " 保存当前字段索引和行号
    let s:current_pipe_field = current_field
    let s:current_pipe_line = line('.')
    let s:original_field_content = fields[current_field]
	let s:original_field_content = substitute(s:original_field_content, " *$", "", "g")
	"let s:original_field_content = substitute(s:original_field_content, "^ *", "", "g")
	if s:field_types[current_field] == 96 
		"char/nchar
	elseif s:field_types[current_field] != 1
		"不是varchar2/nvarchar2,去掉前后空格
		let s:original_field_content = substitute(s:original_field_content, "^ *", "", "g")
		let s:original_field_content = substitute(s:original_field_content, " *$", "", "g")
	endif

    
    " 在新标签页中创建临时缓冲区（不保存到文件）
	if (s:field_types[current_field] == 112 || 
		\ s:field_types[current_field] == 8 ||
		\ s:field_types[current_field] == 113 ||
		\ s:field_types[current_field] == 24 ) 
		\ && lob_file_flag == 1
		"去掉空格
		let s:original_field_content = substitute(s:original_field_content, " ", "", "g")
		if s:original_field_content == ""
			let s:tot_line_num = s:tot_line_num + 1
			let lob_file = printf("lob_%d_%d.txt.new", pid,s:tot_line_num)
			let lob_file=$HOME."/.dbtmp/".lob_file
		else
			let lob_file=substitute(s:original_field_content, "<", "", "g")
			let lob_file=substitute(lob_file, ">.*", "", "g")
			let lob_file=$HOME."/.dbtmp/".lob_file
		endif
    	execute "tabnew ".lob_file
		"autocmd BufWriteCmd <buffer> redraw!|echo "请按Ctrl+a进行保存"
		"cnoremap <buffer> <expr> w oracle_tui#HandleWrite()
		"cnoremap <buffer> <expr> x oracle_tui#HandleWrite_x()
		cnoremap <buffer> <expr> <CR> oracle_tui#CheckSaveCommand()
		inoremap <buffer> <C-A> <Nop>
		"autocmd BufWriteCmd <buffer> redraw!|
    	"		\ if expand('%') =~# '.txt.old$' |
    	"		\   echo "请按Ctrl+a进行保存" |
    	"		\ else |
    	"		\   write |
    	"		\ endif
	else
    	tabnew
    	setlocal buftype=nofile    " 不关联物理文件
    	setlocal bufhidden=delete  " 隐藏时自动删除
    	setlocal noswapfile        " 不创建交换文件
		inoremap <buffer> <C-A> <Nop>
	endif

	setlocal nonu
	"setlocal timeout
	"setlocal ve=
    
	let g:prompt_str = "按Ctrl+a 保存所作修改 :q 放弃修改"
	setlocal laststatus=2
	"必须要用g:str 全局变量
	setlocal statusline=%{g:prompt_str}\ %=%l,%c-%v\ %{&fileencoding} 
	if (s:field_types[current_field] == 112 ||
	  	\ s:field_types[current_field] == 8 ||
	  	\ s:field_types[current_field] == 113 ||
	  	\ s:field_types[current_field] == 24 )
		\ && lob_file_flag == 1
    	" 映射 Ctrl+a 来保存并关闭
    	nnoremap <buffer> <silent> <C-A> :SavePipeLobField<CR>
	else
    	" 填入原始字段内容
    	call setline(1, split(s:original_field_content, ''))
    	
    	" 映射 Ctrl+a 来保存并关闭
    	nnoremap <buffer> <silent> <C-A> :SavePipeField<CR>
		"echo "按Ctrl+N 保存所作修改 :q 放弃修改"
		"let s:prompt_str = "按Ctrl+a 保存所作修改 :q 放弃修改"
		"setlocal ve=
		"setlocal laststatus=2
		"setlocal statusline=%{s:prompt_str}
		"echo "按Ctrl+a 保存所作修改 :q 放弃修改\n"
	endif
endfunction

function! oracle_tui#HandleWrite()
    let type = getcmdtype()
    let cmd = getcmdline()

    if type == ':' && (cmd =~# '^[ \t]*$' )
        call oracle_tui#ShowErr("按Ctrl+a 保存所作修改 :q 放弃修改")
        call feedkeys("\<CR>", 'n')
        return ''
	else
		return 'w'
    endif
endfunction

function! oracle_tui#HandleWrite_x()
    let type = getcmdtype()
    let cmd = getcmdline()

    if type == ':' && (cmd =~# '^[ \t]*$' )
        call oracle_tui#ShowErr("按Ctrl+a 保存所作修改 :q 放弃修改")
        call feedkeys("\<CR>", 'n')
        return ''
	else
		return 'x'
    endif
endfunction

function! oracle_tui#SavePipeField()
    " 获取编辑后的内容
    let lines = getline(1, '$')
	" new_content 在执行tabclose后值还在
    let new_content = len(lines) > 1 ? join(lines, '') : lines[0]
    
    " 关闭当前标签页
    tabclose

	setlocal laststatus=1

	"下面original_buf返回的是-1
    " 回到原来的缓冲区
    "let original_buf = bufnr('#')
    "if original_buf != -1
    "    execute 'buffer ' . original_buf
    "endif
    
    " 更新原文件
	let current_col = virtcol('.')
    if exists('s:current_pipe_line') && exists('s:current_pipe_field')
        let current_line = getline(s:current_pipe_line)
        let fields = split(current_line, '', 1)
        let fields[s:current_pipe_field] = new_content
        call setline(s:current_pipe_line, join(fields, ''))
		call oracle_tui#AlignColumnReal() 
    endif
	exe "normal! ".current_col."|"   
	                                 
	"保持和标题行同步
	normal! ma
	normal! gg
	normal! `a
    
    " 清理变量
    unlet! s:current_pipe_field s:current_pipe_line s:original_field_content
endfunction

function! oracle_tui#SavePipeLobField()
    " 获取编辑后的内容
	autocmd! BufWriteCmd <buffer>
    let new_content = ""
	if &modified
		let file=expand("%")
		if file =~ "old$"
			let new_file=substitute(file, "old$", "new", "g")
			execute "w! "new_file
			execute "e!"
    		let new_content = substitute(s:original_field_content, "old>", "new>", "g") 
			"let new_content = printf("%-30s", new_content)
		else
			if s:original_field_content == ''
				let file=substitute(file, ".*/", "", "g")
    			let new_content = printf("<%s>", file)
			endif

			execute "w!"
		endif
	endif

    " 关闭当前标签页
    tabclose

	setlocal laststatus=1
    
    " 更新原文件
    if exists('s:current_pipe_line') && exists('s:current_pipe_field')
		if new_content != ""
        	let current_line = getline(s:current_pipe_line)
        	let fields = split(current_line, '', 1)
        	let fields[s:current_pipe_field] = new_content
        	call setline(s:current_pipe_line, join(fields, ''))
			call oracle_tui#AlignColumnReal() 
		endif
    endif
    
    " 清理变量
    unlet! s:current_pipe_field s:current_pipe_line s:original_field_content
endfunction

" 光标定位函数
function! oracle_tui#CursorMovedForUpdate()
    let cur_col = col('.')
    let line_text = getline('.')
    let first_comma = stridx(line_text, '')

    if cur_col <= first_comma + 1
		normal! 20zl
        call cursor(line('.'), first_comma + 2)
    endif
endfunction

function! oracle_tui#Smart_zh()
	let view = winsaveview()
	if view.leftcol + 1 > 21
        normal! zh
    else
        "echo "第一列已完全遮挡，不再向左移动"
        return
    endif
endfunction

function! oracle_tui#Smart_zH()
    " 获取当前屏幕最左侧显示的列
    let screen_col = wincol()
    let current_col = virtcol('.')

    if current_col - screen_col > 20 + winwidth(0)/2
        normal! zH
    else
        "echo "第一列已完全遮挡，不再向左移动"
		normal! ^
        "return
    endif
endfunction

function! oracle_tui#ChangeCmd()
    let type = getcmdtype()
    let line = getcmdline()

    "	\ || line =~# '^[^/][^/]*, *[^ /][^ /]* *$'
    if type == ':' && (line =~# '^ *$'
        \ || line =~# '^ *[gv]/[^/][^/]*/ *$'
        \ || line =~# "^[^/,][^/,]*, *'[a-bA-Z>] *$"
        \ || line =~# "^[^/,][^/,]*, *[0-9][0-9]* *$"
        \ || line =~# "^[^/,][^/,]*, *\\$ *$"
        \ || line =~# '^ *% *$')
        return 'MySubstitute/'
    else
        return 's/'
    endif
endfunction

"防止出现:set 被替换
function! oracle_tui#ChangeCmd_s()
    let type = getcmdtype()
    let line = getcmdline()

    if type == ':' && line =~# '^ *$'
		return 's'
	endif

    "    \ || line =~# '^[^/][^/]*, *[^ /][^ /]* *$'
    if type == ':' && (line =~# '^ *[gv]/[^/][^/]*/ *$'
        \ || line =~# "^[^/,][^/,]*, *'[a-bA-Z>] *$"
        \ || line =~# "^[^/,][^/,]*, *[0-9][0-9]* *$"
        \ || line =~# "^[^/,][^/,]*, *\\$ *$"
        \ || line =~# '^ *% *$')
        return 'MySubstitute'
    else
        return 's'
    endif
endfunction

function! oracle_tui#CheckUpdateCommand() abort
    let cmd = getcmdline()
    let type = getcmdtype()

    if type == ':' 
		if s:current_update_file == expand("%")
    		if cmd =~# 's[ \t]*/[^/]*/[^/]*/[giIecn#pl]*[ \t]*$' "s/aaa/bbb/g
    			if cmd =~# 's[ \t]*//[^/]*/[giIecn#pl]*[ \t]*$'
        			let modified_cmd = 'ShowErr 无被替换字符'
    			elseif cmd =~# 's[ \t]*/[^/]*/[^/]*/[giIen#pl]*c[giIen#pl]*[ \t]*$' "s/aaa/bbb/g
        			let modified_cmd = 'ShowErr 不能带参数c'
				else
        			let modified_cmd = substitute(cmd, 's[ \t]*/\([^/]*\)/\([^/]*\)/\([giIecn#pl]*$\)', 'MySubstitute/\\%>19c\1/\2/\3', '')
        			let modified_cmd = substitute(modified_cmd, '^[ \t]*g/\([^/][^/]*\)/', 'g/\\%>19c\1/', '')
					"回车替换成NBSP字符,否则传不过去
        			let modified_cmd = substitute(modified_cmd, '', ' ', '')
				endif
        		"call feedkeys(":\<C-U>" . modified_cmd . "\<CR>", 'n')
				"call feedkeys("\<C-U>ShowErr 无效命令\<CR>", 'n')
				"在该函数中不能修改文件内容，直接调用call oracle_tui#AlignColumn()会报错,可以用下面方式调用 
				"feedkeys函数后面的语句不会被调用，但是下面用timer_start能调用
				"call timer_start(0, {-> oracle_tui#AlignColumn()})
        		return "\<C-U>" . modified_cmd . "\<CR>"
    		elseif cmd =~# 's[ \t]*/[^/]*/[^/]*$' "s/aaa/bbb
    			if cmd =~# 's[ \t]*//[^/]*$'
        			let modified_cmd = 'ShowErr 无被替换字符'
				else
        			let modified_cmd = substitute(cmd, 's[ \t]*/\([^/]*\)/\([^/]*$\)', 'MySubstitute/\\%>19c\1/\2', '')
        			let modified_cmd = substitute(modified_cmd, '^[ \t]*g/\([^/][^/]*\)/', 'g/\\%>19c\1/', '')
				endif
        		"call feedkeys(":\<C-U>" . modified_cmd . "\<CR>", 'n')
        		return "\<C-U>" . modified_cmd . "\<CR>"
			elseif cmd =~# 's[ \t]*/[^/]*[ \t]*$' "s/aaa
			    if cmd =~# 's[ \t]*/[ \t]*$'
        			let modified_cmd = 'ShowErr 无被替换字符'
				else
        			let modified_cmd = substitute(cmd, 's[ \t]*/\([^/]*[ \t]*$\)', 'MySubstitute/\\%>19c\1', '')
        			let modified_cmd = substitute(modified_cmd, '^[ \t]*g/\([^/][^/]*\)/', 'g/\\%>19c\1/', '')
				endif
        		"call feedkeys(":\<C-U>" . modified_cmd . "\<CR>", 'n')
        		return "\<C-U>" . modified_cmd . "\<CR>"
			endif
			"比如ls messages buffers等以s结尾的命令不管
			"elseif cmd =~# 's[ \t]*$' "s
        	"	"let modified_cmd = substitute(cmd, 's[ \t]*$', 'MySubstitute', '')
        	"	let modified_cmd = 'ShowErr 没有参数'
        	"	call feedkeys(":\<C-U>" . modified_cmd . "\<CR>", 'n')
		endif

		if winnr('$') > 1 
			if s:show_update_title_flag == 1 
				if cmd =~# '^[ \t]*q[ \t]*$'
        		    let modified_cmd = 'qall'
        			return "\<C-U>" . modified_cmd . "\<CR>"
				elseif cmd =~# '^[ \t]*q![ \t]*$'
        		    let modified_cmd = 'qall!'
        			return "\<C-U>" . modified_cmd . "\<CR>"
				elseif cmd =~# '^[ \t]*wq[ \t]*$'
        		    let modified_cmd = 'wqall'
        			return "\<C-U>" . modified_cmd . "\<CR>"
				elseif cmd =~# '^[ \t]*wq![ \t]*$'
        		    let modified_cmd = 'wqall!'
        			return "\<C-U>" . modified_cmd . "\<CR>"
				elseif cmd =~# '^[ \t]*x[ \t]*$'
        		    let modified_cmd = 'xall'
        			return "\<C-U>" . modified_cmd . "\<CR>"
				elseif cmd =~# '^[ \t]*x![ \t]*$'
        		    let modified_cmd = 'xall!'
        			return "\<C-U>" . modified_cmd . "\<CR>"
				else
    				return "\<CR>"
        		endif
			else
				if s:show_update_vertical_flag == 1
					if cmd =~# '^[ \t]*q[ \t]*$' ||
						\ cmd =~# '^[ \t]*q![ \t]*$' ||
						\ cmd =~# '^[ \t]*wq[ \t]*$' ||
						\ cmd =~# '^[ \t]*wq![ \t]*$' ||
						\ cmd =~# '^[ \t]*x[ \t]*$' ||
						\ cmd =~# '^[ \t]*x![ \t]*$'
						let s:show_update_vertical_flag = 0
						if line('$') > 1
    						return "\<CR>:call oracle_tui#ShowUpdateTitle()\<CR>"
						endif
					else
    					return "\<CR>"
        			endif
				endif
			endif
		else
    		return "\<CR>"
		endif
    endif

    "执行原始命令
    return "\<CR>"
endfunction

function! oracle_tui#CheckSaveCommand() abort
    let cmd = getcmdline()
    let type = getcmdtype()

    if type == ':' && (cmd =~# '^[ \t]*w'||cmd =~# '^[ \t]*x')
        let modified_cmd = ":call oracle_tui#ShowErr('按Ctrl+a 保存所作修改 :q 放弃修改')"
        return "\<C-U>" . modified_cmd . "\<CR>"
	else
    	"执行原始命令
    	return "\<CR>"
    endif
endfunction

function! oracle_tui#CheckListObjViewCommand() abort
    let cmd = getcmdline()
    let type = getcmdtype()

    if type == ':' && (cmd =~# '^[ \t]*q'||cmd =~# '^[ \t]*x')
		let g:brow_objects_window_flag = 0
    endif

    "执行原始命令
    return "\<CR>"
endfunction

function! oracle_tui#CheckMainCommand() abort
    let cmd = getcmdline()
    let type = getcmdtype()

    if type == ':' && (cmd =~# '^[ \t]*q'||cmd =~# '^[ \t]*wq'||cmd =~# '^[ \t]*x')
		if exists('w:main_window_flag') && w:main_window_flag == 1
        	if oracle_tui#CheckIfCommit()
        	    let modified_cmd = ":call oracle_tui#ShowErr('有未提交事务,不能退出,按<F2>回滚 <F6>提交')"
				"feedkeys在vim7.2版本下无法正常工作
        		"call feedkeys(":\<C-U>" . modified_cmd . "\<CR>", 'n')
        		return "\<C-U>" . modified_cmd . "\<CR>"
        	endif
		endif
    endif

    if type == ':' 
		if (tabpagenr('$') > 1 || winnr('$') > 1) && 
			\ exists('w:main_window_flag') && w:main_window_flag == 1
			if cmd =~# '^[ \t]*q[ \t]*$'
        	    let modified_cmd = 'qall'
        		return "\<C-U>" . modified_cmd . "\<CR>"
			elseif cmd =~# '^[ \t]*q![ \t]*$'
        	    let modified_cmd = 'qall!'
        		return "\<C-U>" . modified_cmd . "\<CR>"
			elseif cmd =~# '^[ \t]*wq[ \t]*$'
        	    let modified_cmd = 'wqall'
        		return "\<C-U>" . modified_cmd . "\<CR>"
			elseif cmd =~# '^[ \t]*wq![ \t]*$'
        	    let modified_cmd = 'wqall!'
        		return "\<C-U>" . modified_cmd . "\<CR>"
			elseif cmd =~# '^[ \t]*x[ \t]*$'
        	    let modified_cmd = 'xall'
        		return "\<C-U>" . modified_cmd . "\<CR>"
			elseif cmd =~# '^[ \t]*x![ \t]*$'
        	    let modified_cmd = 'xall!'
        		return "\<C-U>" . modified_cmd . "\<CR>"
			else
    			return "\<CR>"
        	endif
		else
    		return "\<CR>"
		endif
    endif

    "执行原始命令
    return "\<CR>"
endfunction

function! oracle_tui#ViewCommandLine() abort
    let cmd = getcmdline()
    let type = getcmdtype()

    if type == ':' 
		if s:show_view_title_flag == 1
			if cmd =~# '^[ \t]*q[ \t]*$'
        	    let modified_cmd = 'qall'
        		return "\<C-U>" . modified_cmd . "\<CR>"
			elseif cmd =~# '^[ \t]*q![ \t]*$'
        	    let modified_cmd = 'qall!'
        		return "\<C-U>" . modified_cmd . "\<CR>"
			elseif cmd =~# '^[ \t]*wq[ \t]*$'
        	    let modified_cmd = 'wqall'
        		return "\<C-U>" . modified_cmd . "\<CR>"
			elseif cmd =~# '^[ \t]*wq![ \t]*$'
        	    let modified_cmd = 'wqall!'
        		return "\<C-U>" . modified_cmd . "\<CR>"
			elseif cmd =~# '^[ \t]*x[ \t]*$'
        	    let modified_cmd = 'xall'
        		return "\<C-U>" . modified_cmd . "\<CR>"
			elseif cmd =~# '^[ \t]*x![ \t]*$'
        	    let modified_cmd = 'xall!'
        		return "\<C-U>" . modified_cmd . "\<CR>"
			else
    			return "\<CR>"
        	endif
		elseif s:show_view_vertical_flag == 1
			if cmd =~# '^[ \t]*q[ \t]*$' ||
				\ cmd =~# '^[ \t]*q![ \t]*$' ||
				\ cmd =~# '^[ \t]*wq[ \t]*$' ||
				\ cmd =~# '^[ \t]*wq![ \t]*$' ||
				\ cmd =~# '^[ \t]*x[ \t]*$' ||
				\ cmd =~# '^[ \t]*x![ \t]*$'
				let s:show_view_vertical_flag = 0
    			return "\<CR>:call oracle_tui#ShowViewTitle()\<CR>"
			else
    			return "\<CR>"
        	endif
		endif
    endif

    "执行原始命令
    return "\<CR>"
endfunction

function! oracle_tui#AfterSubstitute(start_line,end_line)
    let s:visual_insert = {
        \ 'start_line': a:start_line,
        \ 'end_line': a:end_line
        \ }
	call oracle_tui#AlignColumnReal() 
endfun

function! oracle_tui#SubstituteWrapperBak(line1, line2, args) abort
	let verbose_save = &verbose
    let &verbose = 0  " 关闭详细错误信息

    try
        execute a:line1 . ',' . a:line2 . 's' . a:args
        call oracle_tui#AfterSubstitute(a:line1, a:line2)
    catch /E486:/  " 模式未找到
        "echoerr '替换失败: 未找到匹配模式'
		call oracle_tui#ShowErr(v:exception)
    catch /E476:/  " 无效参数
        "echoerr '替换失败: 无效参数'
		call oracle_tui#ShowErr(v:exception)
    catch /.*/
        "echoerr '替换失败: ' . v:exception
		call oracle_tui#ShowErr(v:exception)
	finally
        " 恢复设置
        let &verbose = verbose_save
    endtry
endfunction

"代表字典,可以非数字访问
let s:field_lob_content = {} 
"let s:field_lob_content = [] "代表列表，只能用数字索引访问

"替换前先保存lob字段文件名称
function! oracle_tui#SaveLobContent(start_line, end_line) abort
    for lnum in range(a:start_line, a:end_line)
    	let line_text = getline(lnum)
        let fields = split(line_text, '', 1)
    	for i in range(len(fields))
			"先去掉尾部的NBSP字符，再将剩余的NBSP字符替换成空格
    		"let field = substitute(fields[i], ' *$', '', 'g')
    		"let field = substitute(field, ' ', ' ', 'g')

			if (s:field_types[i] == 112 ||
				\ s:field_types[i] == 8 ||
				\ s:field_types[i] == 113 ||
				\ s:field_types[i] == 24 )
				let idx = printf("'%d,%d'", lnum, i)
				let s:field_lob_content[idx] = fields[i]
			endif
    	endfor
    endfor
endfunction

let s:lob_substitute_flag = 0
function! oracle_tui#SubstituteWrapper(line1, line2, args) abort
	"第一行修改要跳过
	let v:errmsg = ''
	let start_line = a:line1
	let end_line = a:line2
	if start_line <= 1 && end_line <= 1
		return
	endif

	if start_line <= 1 && end_line > 1
		let start_line = 2
	endif

	let file=expand("%")
	let shortfile=substitute(file, ".*/", "", "g")
	if shortfile =~# "^p_c_" || shortfile =~# "^c_"
		let lob_file_flag = 1
	else
		let lob_file_flag = 0
    endif

	if lob_file_flag == 1
		let s:lob_substitute_flag = 1
    	call oracle_tui#SaveLobContent(start_line, end_line)
	endif

	"替换回车时前面补一列rowid字段(回车被替换成NBSP字符,否则传不过来
    let sub_str = substitute(a:args, ' ', 'XXXXXXXXXXXXXXXXXX', '')
    silent! execute start_line . ',' . end_line . 's' . sub_str

    " 检查是否有错误
    if v:errmsg != ''
        " 根据错误信息判断错误类型
        if v:errmsg =~# 'E486:'
			"echoerr 会显示详细报错信息
            "echoerr '替换失败: 未找到匹配模式'
			let errstr = substitute(v:errmsg, '\\%>19c', "", "g")

			call oracle_tui#ShowErr(errstr)
        elseif v:errmsg =~# 'E476:'
            "echoerr '替换失败: 无效参数'
			call oracle_tui#ShowErr(v:errmsg)
        else
            "echoerr '替换失败: ' . v:errmsg
			call oracle_tui#ShowErr(v:errmsg)
        endif
		let v:errmsg = ''
        return  
    endif

    " 没有错误，执行后续函数
    call oracle_tui#AfterSubstitute(start_line, end_line)
endfunction

"nnoremap <silent> <buffer> dw :set operatorfunc=AdjustSpacesOperator<CR>g@w
"上面映射说明
"g@w会选择从当前位置到下一个单词开头
"Vim自动设置 `[ 和 `]
"你的函数被调用，type='line'
"`[d`] 删除刚才选择的范围
"然后执行你的自定义逻辑
function! oracle_tui#AdjustSpacesOperator(type)
    " 执行原始的dw操作
    execute 'normal! `[d`]'
    call oracle_tui#AlignColumnReal()
endfunction

function! oracle_tui#MyDeleteMapping()
    " 保存原来的 operatorfunc
    let s:old_opfunc = &operatorfunc

    " 设置自定义函数
    set operatorfunc=MyDeleteOperator

    " 返回 g@ 会等待移动命令
    return 'g@'
endfunction

function! MyDeleteOperator(type, ...)
    " 执行原始删除操作
	if a:type == 'line'
		"dj dG dgg 行删除模式
		silent execute "normal! '[V']d"
	else
    	execute 'normal! `[v`]d'
    	" 调用后处理函数
		call oracle_tui#AlignColumnReal() 
	endif


    " 恢复原来的 operatorfunc（如果需要的话）
    let &operatorfunc = s:old_opfunc
endfunction

let s:prompt_flag = 0
let s:cur_field = 0
function! oracle_tui#ShowPrompt()
    let current_line = getline('.')
    let cursor_col = col('.') - 1
    
    " 找出光标所在的字段
    let fields = split(current_line, '', 1)
    let current_field = 0
    let pos = 0
    
    for i in range(len(fields))
        if cursor_col >= pos && cursor_col <= pos + len(fields[i])
            let current_field = i
            break
        endif
        let pos += len(fields[i]) + 1
    endfor

	let file=expand("%")
	let shortfile=substitute(file, ".*/", "", "g")
	if shortfile =~# "^p_c_" || shortfile =~# "^c_"
		let lob_file_flag = 1
	else
		let lob_file_flag = 0
    endif

	if lob_file_flag == 1 && (s:field_types[current_field] == 112 ||
		\ s:field_types[current_field] == 8 ||   
		\ s:field_types[current_field] == 113 ||   
		\ s:field_types[current_field] == 24 )
		"if s:field_types[current_field] != s:prompt_flag 
		"	\ || s:cur_field != current_field
		if s:cur_field != current_field
			echo "Column ".s:field_names[current_field]. " must press Ctrl+a to edit or view"
			let s:prompt_flag = s:field_types[current_field]
		endif
	elseif s:field_types[current_field] == 12 
		"if s:field_types[current_field] != s:prompt_flag 
		"	\ || s:cur_field != current_field
		if s:cur_field != current_field
			echo "Column ".s:field_names[current_field]. " FORMAT IS yyyy-mm-dd hh24:mi:ss"
			let s:prompt_flag = s:field_types[current_field]
		endif
	elseif s:field_types[current_field] == 180 
		"if s:field_types[current_field] != s:prompt_flag 
		"	\ || s:cur_field != current_field
		if s:cur_field != current_field
			echo "Column ".s:field_names[current_field]. " FORMAT IS YYYY-MM-DD HH24:MI:SSXFF"
			let s:prompt_flag = s:field_types[current_field]
		endif
	elseif s:field_types[current_field] == 181 
		"if s:field_types[current_field] != s:prompt_flag 
		"	\ || s:cur_field != current_field
		if s:cur_field != current_field
			echo "Column ".s:field_names[current_field]. " FORMAT IS YYYY-MM-DD HH24:MI:SSXFF TZR"
			let s:prompt_flag = s:field_types[current_field]
		endif
	else
		if s:prompt_flag > 0
			redraw!
			let s:prompt_flag = 0
		endif
	endif
	let s:cur_field = current_field
endfunction

function! oracle_tui#GentleCheck()
    " 获取文件修改时间
    let current_mtime = getftime(expand('%'))
    if !exists('b:last_mtime')
        let b:last_mtime = current_mtime
        return
    endif
    
    " 如果文件已修改
    if current_mtime > b:last_mtime
        echohl WarningMsg 
        echo "sql正在运行..."
        echohl None
        
        " 可选：自动加载
        silent edit!
        
        " 更新记录的时间
        let b:last_mtime = current_mtime
    endif
endfunction

function! oracle_tui#GotoVirtCol(line, vcol)
    call cursor(a:line, 0)
    execute "normal " . a:vcol . "|"
endfunction

"定义函数：跳到下一个字段
function! oracle_tui#JumpToNextField()
    " 获取当前行号
    let l:current_line = line('.')
    "let l:current_col = col('.')
    let l:current_col = virtcol('.')
    
    " 获取第二行的内容（分隔线）
    let l:separator_line = getline(3)
    if l:separator_line !~ '---'
        echo "第二行不是有效的分隔线"
        return
    endif
    
    " 查找所有字段边界（找到每个---开始的位置）
    let l:boundaries = []
    let l:pos = 1
    let l:sep_len = strlen(l:separator_line)
    
    while l:pos <= l:sep_len
        " 检查当前位置是否是---的开始
        if l:separator_line[l:pos-1] == '-'
            " 如果是---的起始位置，记录边界
            call add(l:boundaries, l:pos)
            " 跳过连续的-
            while l:pos <= l:sep_len && l:separator_line[l:pos-1] == '-'
                let l:pos += 1
            endwhile
        else
            let l:pos += 1
        endif
    endwhile
    
    " 如果当前行不是最后一行，查找下一个字段
    let l:next_boundary = 0
    for l:boundary in l:boundaries
        if l:boundary > l:current_col
            let l:next_boundary = l:boundary
            break
        endif
    endfor
    
    " 如果找到下一个字段位置，跳到那里
    if l:next_boundary > 0
        "call cursor(l:current_line, l:next_boundary)
		call oracle_tui#GotoVirtCol(l:current_line, l:next_boundary)
    else
        " 如果当前行没有下一个字段，跳到下一行的第一个字段
        if l:current_line < line('$')
			if getline(l:current_line + 1) == ''
				call oracle_tui#ShowErr("到达文件结尾!\n")
				return
			endif
            "call cursor(l:current_line + 1, l:boundaries[0])
			call oracle_tui#GotoVirtCol(l:current_line + 1, l:boundaries[0])
        else
            " 如果是最后一行，跳回第一行的第一个字段
            "call cursor(4, l:boundaries[0])
            call oracle_tui#GotoVirtCol(4, l:boundaries[0])
        endif
    endif
endfunction

function! oracle_tui#GetCurrentChar()
    let line = getline('.')
    let col_pos = col('.') - 1
    
    if col_pos >= strlen(line)
        return ''
    endif
    
    " 使用正则匹配当前字符（包括多字节）
    let before = strpart(line, 0, col_pos)
    let after = strpart(line, col_pos)
    
    " 匹配第一个字符（支持多字节）
    let char = matchstr(after, '^.')
	return char
endfunction

function! oracle_tui#Replace_r()
	let l:current_char = oracle_tui#GetCurrentChar()

	if l:current_char == ''
		call oracle_tui#ShowErr("不能修改分隔符")
		return ''
	endif

	if  strwidth(l:current_char) > 1
		return 'R'
	else
		return 'r'
	endif
endfunction

" 定义函数：跳到上一个字段
function! oracle_tui#JumpToPrevField()
    " 获取当前行号
    let l:current_line = line('.')
    let l:real_col = col('.')

	let l:current_char = oracle_tui#GetCurrentChar()
    let l:current_col = virtcol('.')
	if  strwidth(l:current_char) > 1
    	let l:current_col = l:current_col - 1
	endif

	if l:real_col == 1 && l:current_line <= 4
		call oracle_tui#ShowErr("到达文件头部!\n")
		return
	endif
    
    " 获取第二行的内容（分隔线）
    let l:separator_line = getline(3)
    if l:separator_line !~ '---'
        echo "第二行不是有效的分隔线"
        return
    endif
    
    " 查找所有字段边界
    let l:boundaries = []
    let l:pos = 1
    let l:sep_len = strlen(l:separator_line)
    
    while l:pos <= l:sep_len
        if l:separator_line[l:pos-1] == '-'
            call add(l:boundaries, l:pos)
            while l:pos <= l:sep_len && l:separator_line[l:pos-1] == '-'
                let l:pos += 1
            endwhile
        else
            let l:pos += 1
        endif
    endwhile
    
    " 查找上一个字段位置
    let l:prev_boundary = 0
	let break_flag = 0
    for l:boundary in reverse(copy(l:boundaries))
		if break_flag == 1
            let l:prev_boundary = l:boundary
			break
		endif

        if l:boundary <= l:current_col
        	if l:boundary < l:current_col
            	let l:prev_boundary = l:boundary
				break
			else
				let break_flag = 1
			endif
        endif
    endfor
    
    " 如果找到上一个字段位置，跳到那里
    "if l:prev_boundary > 0
	if l:real_col > 1
        call oracle_tui#GotoVirtCol(l:current_line, l:prev_boundary)
    else
        " 如果当前行没有上一个字段，跳到上一行的最后一个字段
        if l:current_line > 4
            call oracle_tui#GotoVirtCol(l:current_line - 1, l:boundaries[-1])
        endif
    endif
endfunction

function! oracle_tui#DBViewHelp()
	echo "                                                                               "
	echo "  +------------------------------------------------------------------------+ "
	echo "  |                          按键说明                                      | "
	echo "  |按[左移 {左快移 按]右移 }右快移 j下移 J下快移  按k上移 K上快移 按/查询  | "
	echo "  |按 F3 冻结/解冻标题行                                                   | "
	echo "  |按 F11 显示当前SQL语句                                                  | "
	echo "  |按 TAB跳到下一个字段 Ctrl+t 跳到上一个字段                              | "
	echo "  |按 wv垂直分割窗口                                                       | "
	echo "  |按 - 缩小当前窗口宽度           = 增加当前窗口宽度                      | "
	"echo "  |按 shift - 缩小当前窗口高度     shift = 增加当前窗口高度                | "
	echo "  |按 Ctrl+↑对当前列正向排序        Ctrl+↓对当前列反向排序                 | "
	echo "  |按 Ctrl+→ 跳到右面窗口           Ctrl+← 跳到下面窗口                    | "
	echo "  |按 :Crtsql 根据当前数据文件生成sql                                      | "
	echo "  |按 :Filter /match_str  过滤当前列符合条件的内容                         | "
	echo "  |按 Ctrl+x 将当前列从当前光标位置删除到列尾(缩短列长度)                  | "
	echo "  |按 \\x 剪切当前列 \\p 粘贴剪切的列到当前列后面                            | "
	echo "  |按 Ctrl+\\ 对选中的列中的数字进行求和                                    | "
	echo "  |按 <F1>显示帮助                                                         | "
	echo "  |                         臧建伟制作                                     | "
	echo "  +------------------------------------------------------------------------+ "
endfun

function! oracle_tui#DBModifyHelp()
	echo "  +------------------------------------------------------------------------+ "
	echo "  |                          按键说明                                      | "
	if v:version >= 800
		echo "  |按[左移 {左快移 按]右移 }右快移 j下移 J下快移  按k上移 K上快移 按/查询  | "
	else
		echo "  |按j下移 J下快移  按k上移 K上快移 按/查询                                | "
	endif
	echo "  |按 F12 提交对表数据的修改(不提交事务)                                   | "
	echo "  |新增行用o或O(普通模式下 o:在当前行下新增一行,O:当前行上新增一行)        | "
	echo "  |按 TAB 跳入下一列(修改或普通模式)                                       | "
	echo "  |按 Ctrl+t 跳入上一列(修改或普通模式)                                    | "
	echo "  |按 Ctrl+→ 跳到右面窗口          Ctrl+← 跳到下面窗口                     | "
	echo "  |按 Ctrl+a 打开一个窗口对当前列进行修改                                  | "
	echo "  |按 Ctrl+n 显示空字符开关        F3 冻结/解冻标题行                      | "
	echo "  |按 Ctrl+@ 显示修改内容开关                                              | "
	echo "  |按 - 缩小当前窗口宽度           = 增加当前窗口宽度                      | "
	"echo "  |按 shift - 缩小当前窗口高度     shift = 增加当前窗口高度                | "
	if v:version >= 800
		echo "  |按 wv垂直分割窗口                                                       | "
	endif
	echo "  |按 <F1>显示帮助                                                         | "
	echo "  |                         臧建伟制作                                     | "
	echo "  +------------------------------------------------------------------------+ "
endfun


function! oracle_tui#SetMapView()
	command! ReduceColumn call oracle_tui#ReduceColumn()
	command! CutColumn call oracle_tui#CutColumn()
	command! PasteColumn call oracle_tui#PasteColumn()
	command! ShowSql call oracle_tui#ShowSql()
	command! Crtsql call oracle_tui#Crtsql()
	command! DBViewHelp call oracle_tui#DBViewHelp()
	command! -nargs=* Filter call oracle_tui#Filter(<q-args>)

	nnoremap <silent> <buffer> J 15j
	nnoremap <silent> <buffer> K 15k

	"- 减小窗口宽度
	nnoremap <silent> <buffer> - <
	"_ 增加窗口宽度
	nnoremap <silent> <buffer> = >
	
	"= 减小窗口高度
	"nnoremap <silent> <buffer> _ -  
	"+  增加窗口高度
	"nnoremap <silent> <buffer> + +

	noremap <silent> <buffer> [ zh
	noremap <silent> <buffer> ] zl
	noremap <silent> <buffer> { zH
	noremap <silent> <buffer> } zL

	noremap <silent> <buffer> <C-W>k <Nop>
	
	"水平分割窗口，显示列名
	"nnoremap <silent> <buffer>  wh :WH<CR>
	"垂直分割窗口
	"map wh :WH<CR>
	nnoremap <silent> <buffer> wv :call oracle_tui#ViewVerSplit()<CR>
	"<F1>
	"map OP :Help<CR>
	nnoremap <silent> <buffer> OP :DBViewHelp<CR>
	
	nnoremap <silent> <buffer>  :ReduceColumn<CR>
	nnoremap <silent> <buffer> \x :CutColumn<CR>
	nnoremap <silent> <buffer> \p :PasteColumn<CR>
	nnoremap <silent> <buffer> <C-\> :call oracle_tui#SumColumn()<CR>
	vnoremap <silent> <buffer> <C-\> :call oracle_tui#SumVisual()<CR>
	
	"Ctrl+N 对当前列进行排序
	"nnoremap <silent> <buffer> <C-N> :Sort<CR>

	"<F3> 冻结/解冻标题行
	nnoremap <buffer> <silent>  OR :call oracle_tui#ShowViewTitle()<CR>
	
	"<F11>
	"nmap [23~ :ShowSql<CR>
	nnoremap <silent> <buffer> <expr> [23~ expand("%") =~# ".txt.new$" ? '' : ':ShowSql'
	
	"let mapleader = "|"
	"按数字进行排序
	"nnoremap <silent> <buffer> \1 :ColSort 1<CR>
	
	"按字符进行排序(好像只要右对齐，数字也能正确排序)
	"nnoremap <silent> <buffer> \2 :ColSort 2<CR>
	
	"生成sql语句
	"nnoremap <silent> <buffer> \sql :Crtsql<CR>

	cnoremap <silent> <expr> <CR> oracle_tui#ViewCommandLine()

	" 映射TAB键到跳转到下一个字段功能
	nnoremap <silent> <buffer> <Tab> :call oracle_tui#JumpToNextField()<CR>
	"inoremap <Tab> <C-o>:call JumpToNextField()<CR>

	" 映射Crtl+T到跳转到上一个字段功能
	nnoremap <silent> <buffer> <C-T> :call oracle_tui#JumpToPrevField()<CR>
	"inoremap <S-Tab> <C-o>:call JumpToPrevField()<CR>

	nnoremap <silent> <buffer> <C-Up> :call oracle_tui#Sort(0)<CR> 
	nnoremap <silent> <buffer> <C-Down> :call oracle_tui#Sort(1)<CR> 
	nnoremap <silent> <C-Left> h
	nnoremap <silent> <C-Right> l
endfun

function! oracle_tui#SetMapUpdate()
	let s:current_update_file = expand('%')
	setlocal t_BE=
	"不加下面这行ShowDiff()不能显示比较差异
	set diffopt-=closeoff
	"map 中不能用call oracle_tui#Func() 要用call oracle_tui#Func()
	"映射展开时，Vim 会将 oracle_tui# 替换为当前脚本的唯一ID

	"不做如下设置则dw的映射当d和w之间的输入间隔比较长时映射无效
	"nnoremap <silent> <buffer> dw dw:call oracle_tui#AlignColumnReal()<CR>
	"不加这个又没问题了
	"setlocal notimeout
	"call UnMap()
	command! Update call oracle_tui#Update()
	command! Hid  call oracle_tui#Hid()
	command! ShowNullChar  call oracle_tui#ShowNullChar()
	command! NoHid  call oracle_tui#NoHid()
	command! EditColumnAfter call oracle_tui#EditColumnAfter()
	command! EditColumnAfter2 call oracle_tui#EditColumnAfter2()
	command! JumpNextColumn call oracle_tui#JumpNextColumn()
	command! EditColumnBefore call oracle_tui#EditColumnBefore()
	command! JumpBeforeColumn call oracle_tui#JumpBeforeColumn()
	command! EditColumnBefore2 call oracle_tui#EditColumnBefore2()
	command! NewLine call oracle_tui#NewLine()
	command! -range ClearCont <line1>,<line2>s/[^]/ /g<bar>normal! 0
	command! DBModifyHelp call oracle_tui#DBModifyHelp()
	command! PipeFieldEdit call oracle_tui#PipeFieldEdit()
	command! SavePipeField call oracle_tui#SavePipeField()
	command! SavePipeLobField call oracle_tui#SavePipeLobField()
	"command! -range -nargs=* MySubstitute <line1>,<line2>s<args> | call oracle_tui#AfterSubstitute(<line1>, <line2>)
	command! -range -nargs=* MySubstitute call oracle_tui#SubstituteWrapper(<line1>, <line2>, <q-args>)
	command! -nargs=* ShowErr call oracle_tui#ShowErr(<f-args>)

	"command! -range -nargs=* Substitute execute printf('%d,%d s%s',
    "	\ (<line1> == 1 ? 2 : <line1>),
    "	\ <line2>,
    "	\ <q-args>) |call oracle_tui#AfterSubstitute(<line1>, <line2>) 

	"cnoremap <buffer> <expr> s/ oracle_tui#ChangeCmd()
	"cnoremap <buffer> <expr> s oracle_tui#ChangeCmd_s()
	cnoremap <silent> <expr> <CR> oracle_tui#CheckUpdateCommand()

	nnoremap <silent> <buffer> J 15j
	nnoremap <silent> <buffer> K 15k

	"- 减小窗口宽度
	nnoremap <silent> <buffer> - <
	"_ 增加窗口宽度
	nnoremap <silent> <buffer> = >

	nnoremap <silent> <C-Left> h
	nnoremap <silent> <C-Right> l
	
	"= 减小窗口高度
	"nnoremap <silent> <buffer> _ -  
	"+  增加窗口高度
	"nnoremap <silent> <buffer> + +

	"noremap <silent> <buffer> 9 zh
	"7.4版本有bug
	"当编辑一个UTF-8文件并且调用:syn match Substitute /@/ conceal cchar=|
	"时，移动屏幕到右侧出现分隔符时vim会没有反应，此时vim进程cpu占用会达到100%
	if v:version >= 800
		noremap <silent> <buffer> [ :call oracle_tui#Smart_zh()<CR>
		noremap <silent> <buffer> ] zl
		"noremap <silent> <buffer> ( zH
		noremap <silent> <buffer> { :call oracle_tui#Smart_zH()<CR>
		noremap <silent> <buffer> } zL
	else
		noremap <silent> <buffer> zl <Nop>
		noremap <silent> <buffer> zL <Nop>
		noremap <silent> <buffer> zh <Nop>
		noremap <silent> <buffer> zH <Nop>
	endif

	noremap <silent> <buffer> <C-W>k <Nop>

	call oracle_tui#ProtectFirstLine()

	nnoremap <buffer> <silent> <expr> r oracle_tui#Replace_r()
	"noremap <buffer> <silent>  <expr> \cl line('.') > 1 ? ':ClearCont' : ''
	nnoremap <buffer> <silent> <Tab> :JumpNextColumn<CR>
	inoremap <buffer> <silent> <Tab> :call oracle_tui#EditColumnAfter2()<CR>
	"nnoremap <buffer> <silent>  :EditColumnAfter<CR>
	inoremap <buffer> <silent> <C-T> l:call oracle_tui#EditColumnBefore2()<CR>
	"nnoremap <buffer> <silent>  :EditColumnBefore<CR>
	nnoremap <buffer> <silent> <C-T> :JumpBeforeColumn<CR>
	inoremap <buffer> <silent> <CR> <Esc>:call oracle_tui#AlignColumnReal()<CR>
	nnoremap <buffer> <silent>  o o:NewLine<CR>
	"nnoremap <buffer> <C-A> call oracle_tui#PipeFieldEdit()<CR>
	nnoremap <buffer> <silent> <C-A> :PipeFieldEdit<CR>
	inoremap <buffer> <silent> <C-A> l:PipeFieldEdit<CR>

	nnoremap <buffer> <silent> <expr> O line('.')==1 ? '' : 'O:NewLine'
	"nnoremap <buffer> <silent>  O O:NewLine<CR>
	
	"水平分割窗口，显示列名
	"nnoremap <silent> <buffer>  wh :HorSplitHeader<CR>
	"垂直分割窗口
	"map wh :WH<CR>
	if v:version >= 800
		"7.4版本在垂直分割的窗口移动时会导致vim cpu 达100%
		nnoremap <silent> <buffer> wv :call oracle_tui#UpdateVerSplit()<CR>
	endif
	"<F1>
	"map OP :Help<CR>
	nnoremap <silent> <buffer>  OP :DBModifyHelp<CR>

	"<F3> 冻结/解冻标题行
	nnoremap <buffer> <silent>  OR :call oracle_tui#ShowUpdateTitle()<CR>

	"Ctrl+n 显示空字符开关
	nnoremap <buffer> <silent>  <C-N> :call oracle_tui#ShowNullChar()<CR>


	"Ctrl+@ 显示比较差异开关
	nnoremap <buffer> <silent>  <C-@> :call oracle_tui#ShowDiff()<CR>

	"<F9> 对其所有列
	"nnoremap <buffer> <silent>  [20~ :AlignColumn<CR>

	"<F12>
	"nmap [24~ :Update<CR>
	nnoremap <silent> <buffer>  [24~ :Update<CR>

	inoremap <buffer> <silent> <Esc> <Esc>:call oracle_tui#AlignColumnReal()<CR>

	"noremap x 必须要定义在vnoremap x之前，否则vnoremap x不生效
	"nnoremap <silent> <buffer> <expr> x or(line('.')==1,getline('.')[col('.')-1] == '') ? '' : 'x:call oracle_tui#AlignColumnReal()<CR>'
	nnoremap <silent> <buffer> <expr> x or(line('.')==1,getline('.')[col('.')-1] == '') ? '' : 'x:call oracle_tui#Process_x()<CR>'
	nnoremap <silent> <buffer> <expr> X or(line('.')==1,getline('.')[col('.')-2] == '') ? '' : 'X:call oracle_tui#AlignColumnReal()<CR>'

	" 设置操作符函数并触发自定义删除
	nnoremap <silent> <buffer> <expr> d oracle_tui#MyDeleteMapping()
	"nnoremap <silent> <buffer> dw :set operatorfunc=AdjustSpacesOperator<CR>g@w
	"nnoremap <silent> <buffer> <expr> dw (line('.') == 1) ? '' : 'dw:call oracle_tui#AlignColumnReal()<CR>'
	"nnoremap <silent> <buffer> <expr> diw (line('.') == 1) ? '' : 'diw:call oracle_tui#AlignColumnReal()<CR>'
	"nnoremap <silent> <buffer> <expr> daw (line('.') == 1) ? '' : 'daw:call oracle_tui#AlignColumnReal()<CR>'
	"nnoremap <silent> <buffer> <expr> de (line('.') == 1) ? '' : 'de:call oracle_tui#AlignColumnReal()<CR>'
	"nnoremap <silent> <buffer> <expr> db (line('.') == 1) ? '' : 'db:call oracle_tui#AlignColumnReal()<CR>'
	nnoremap <silent> <buffer> <expr> D (line('.') == 1) ? '' : 'D:call oracle_tui#AlignColumnReal()<CR>'
	nnoremap <silent> <buffer> <expr> p (line('.') == 1) ? '' : ":call oracle_tui#Normal_paste('p')<CR>"
	nnoremap <silent> <buffer> <expr> P (line('.') == 1) ? '' : ":call oracle_tui#Normal_paste('P')<CR>"

	vnoremap <silent> <buffer> I :<C-u>call oracle_tui#VisualSaveState()<CR>gvI
	vnoremap <silent> <buffer> A :<C-u>call oracle_tui#VisualSaveState()<CR>gvA
	vnoremap <silent> <buffer> c :<C-u>call oracle_tui#VisualSaveState()<CR>gvc
	"vnoremap <silent> <buffer> x :<C-u>call oracle_tui#VisualSaveStateX()<CR>gvx:call oracle_tui#AlignColumnReal()<CR> 
	"vnoremap <silent> <buffer> X :<C-u>call oracle_tui#VisualSaveStateX()<CR>gvX:call oracle_tui#AlignColumnReal()<CR>  
	"vnoremap <silent> <buffer> d :<C-u>call oracle_tui#VisualSaveStateX()<CR>gvx:call oracle_tui#AlignColumnReal()<CR>  
	vnoremap <silent> <buffer> x :<C-u>call oracle_tui#VisualSaveStateX()<CR>
	vnoremap <silent> <buffer> X :<C-u>call oracle_tui#VisualSaveStateX()<CR>
	vnoremap <silent> <buffer> d :<C-u>call oracle_tui#VisualSaveStateX()<CR>
	vnoremap <silent> <buffer> D :<C-u>call oracle_tui#VisualSaveStateD()<CR>
	"vnoremap <silent> <buffer> p :<C-u>call VisualSaveStateI()<CR>gvp
	vnoremap <silent> <buffer> p   :<C-u>call oracle_tui#Visual_paste('p')<CR>
	vnoremap <silent> <buffer> P   :<C-u>call oracle_tui#Visual_paste('P')<CR>

	command! AlignColumn call oracle_tui#AlignColumn()
endfun

function! oracle_tui#SetLocal()
	setlocal nocompatible
	"vim8.2下有bracketed_paste(带括号的粘贴)，指的是粘贴时会在
	"粘贴的内容两侧加特殊字符,这个特殊字符带Esc，因为在
	"for update模式下进行修改时会映射Esc键，会导致Esc键不能
	"正常工作,解决办法是将t_BE设置为空,禁止粘贴时两边加特殊
	"字符
	"t_BE=^[[?2004h  
	"setlocal t_BE=
	"setlocal virtualedit=all
	setlocal virtualedit=
	setlocal incsearch
	setlocal noequalalways
	setlocal winwidth=1
	setlocal winheight=1
	setlocal ruler		" show the cursor position all the time
	setlocal showcmd		" display incomplete commands
	setlocal scb
	setlocal sbo=hor
	setlocal nowrap
	setlocal cul
	setlocal nonu
	setlocal nohlsearch
	"加这里没用,要用vim --cmd 加载
	"setlocal encoding=utf-8 
	"setlocal termencoding=utf-8
	"gb18030要放在gbk前面，否则识别编码有误
	"setlocal fileencodings=ucs-bom,utf-8,gb18030,gbk,gb2312,cp936,latin1

	if &t_Co == 0 || empty(&t_Sf) || empty(&t_Sb)
		set t_Co=8
		set t_Sf=[3%p1%dm
		set t_Sb=[4%p1%dm
	endif
endfun

function! oracle_tui#SetEnv()
	setlocal nocompatible
	"setlocal virtualedit=all
	setlocal virtualedit=
	setlocal incsearch
	setlocal noequalalways
	setlocal winwidth=1  
	setlocal winheight=1 
	setlocal ruler		" show the cursor position all the time
	setlocal showcmd		" display incomplete commands
	setlocal scb
	setlocal sbo=hor
	setlocal nonu
	setlocal nohlsearch  
endfun

function! oracle_tui#SetAutocmdView()
	augroup DBView
		autocmd!
		au VimEnter <buffer> echo "按[或{左移 ]或}右移 j或J下移 k或K上移 F1帮助"
		au VimEnter <buffer> setlocal statusline=%{&fileencoding}\ %=%l/%L\ %c-%v\ %p%%
		"执行:e 后，会显示第一行,用下面方法解决
		autocmd BufReadPost <buffer> call feedkeys("lh", 'n')
		"au VimEnter <buffer> call oracle_tui#ShowViewTitle()
		"下面为查询时不等待查询完成才打开结果文件
		"刚打开文件时文件不能刷新，移动光标也不能刷新，但有时候可以
		"au FocusGained,BufEnter,CursorHold * call oracle_tui#GentleCheck()
		"au FocusGained,WinEnter,CursorHold * call oracle_tui#GentleCheck()
		"au BufReadPost * let b:last_mtime = getftime(expand('%'))
		"au BufReadPost * call feedkeys("jjll")
		"setlocal updatetime=100
	augroup END
endfun

function! oracle_tui#SetAutocmdUpdate()
	augroup DBUpdate
		autocmd!
		"只对当前缓冲区有效
		"autocmd BufUnload * call oracle_tui#CloseAllBuffs()
		"执行:e会触发BufUnload事件
		"autocmd BufUnload  <buffer> call oracle_tui#CloseAllBuffs()
		"au VimEnter <buffer> call oracle_tui#ShowUpdateTitle()
		"autocmd BufEnter *.new call oracle_tui#ProtectFirstLine()

		"用:call oracle_tui#Hid也可以
		au BufNewFile,BufRead,BufEnter,VimEnter  <buffer> :call oracle_tui#Hid()
		"au BufNewFile,BufRead,BufEnter,VimEnter  <buffer> :call ShowDiff()

		if v:version >= 800
			au VimEnter <buffer> echo "按[或{左移 ]或}右移 j或J下移 k或K上移 F1帮助"
		else
			au VimEnter * echo "F1帮助"
		endif
		au VimEnter <buffer> setlocal statusline=%{&fileencoding}\ %=%l/%L\ %c-%v\ %p%%

		autocmd BufNewFile,BufRead,BufEnter,VimEnter <buffer> call oracle_tui#ReadColumn()
		autocmd BufNewFile,BufRead,BufEnter,VimEnter <buffer> call oracle_tui#ReShowNullChar() 
		"autocmd vimLeave *.new call ClearColumnList()

		" 使用 CursorMoved 自动调整光标位置
		autocmd CursorMoved <buffer> call oracle_tui#CursorMovedForUpdate()

		autocmd CursorHold * call oracle_tui#ShowPrompt()
		setlocal updatetime=500
		"下面的map会导致vim9.2插入模式下按Esc后回延迟1秒，所以要加setlocal ttimeoutlen=50
		"加setlocal timeoutlen=50同样的效果
		"inoremap <buffer> <silent> <Esc> <Esc>:call oracle_tui#AlignColumnReal()<CR>
		setlocal ttimeoutlen=50
	augroup END
endfun

let &cpo = s:save_cpo
