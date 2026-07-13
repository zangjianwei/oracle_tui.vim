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

"The following line is for loading your own crtdb.txt and should be removed for formal release
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
		"Skip if empty line (do not skip empty lines in stored procedures)
		if (line =~ "^[ \t]*$" || line =~ "^[ \t]*--") && proc_flag == 0
			continue
		endif
		let k = k +1

		call add(onesql_list, line)

		if line !~ "^[ \t]*--" && line !~ "^[ \t]*$"
			let j = j +1
		endif

		"where col like '--%' Exclude this case
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
		call oracle_tui#ShowErr("No SQL to execute!")
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
		call oracle_tui#ShowErr("PLSQL no /")
		return
	endif

	"Add a semicolon at the end of the last line
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
		"There is only one query statement.
		let one_select_flag = 1
	else
		let one_select_flag = 0
	endif

	if upd_flag == 1 && more_line_flag == 1
		redraw!
		call oracle_tui#ShowErr("Only one SQL statement is allowed for modification")
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
		"Catch exceptions here; otherwise, the shell will be interrupted and subsequent statements will not execute (e.g., redraw!)
		try
			sil execute "!clear;".sql
		catch 
			echo "Catch an interrupt"
		endtry
		let status = shell_error
    	redraw! "Refresh screen
		if status == 0
			echo "Data modify success.Press <F2>/rollback <F6>/commit"
		elseif status == 1
			call oracle_tui#ShowErr("Data modification failed!")
			echo ""
		elseif status == 3
			call oracle_tui#ShowMsg("No data has been modified!")
			echo ""
		elseif status == 4
			call oracle_tui#ShowErr("Database connection interrupted!")
			echo ""
		elseif status == 10
			call oracle_tui#ShowErr("AWK syntax error when generating update SQL!")
			echo ""
		elseif status == 11
			call oracle_tui#ShowErr("Error generating update SQL!")
			echo ""
		elseif status == 12
			"call oracle_tui#ShowErr("SQL syntax error!")
			"echo ""
			let nouse=1
		elseif status == 13
			call oracle_tui#ShowErr("Operation interrupted!")
			echo ""
		elseif status == 14
			"call oracle_tui#ShowErr("Error executing the generated PL/SQL!")
			"echo ""
			let nouse=1
		elseif status == 15
			call oracle_tui#ShowErr("Command line parameter error!")
			echo ""
		elseif status == 100
			call oracle_tui#ShowMsg("Discard changes!")
		else
			call oracle_tui#ShowErr("Exception, unknown return code:".status)
			echo ""
		endif
	else
		"Catch exceptions here; otherwise, the shell will be interrupted and subsequent statements will not execute (e.g., redraw!)
		try
			sil execute "!clear;".sql
		catch 
			echo "Catch an interrupt"
		endtry
    	redraw! "Refresh screen
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

function! oracle_tui#SumColumn()
	let reg_bak = @a
	let @a = ""
    let l:col_data = []
    
    let l:cur_line = line('.')
    let l:vir_col = virtcol('.')
    let l:separator_text = getline(3)
	let real_col = col('.')  
    
    let l:boundary = oracle_tui#GetFieldBoundaries(l:separator_text, l:vir_col)
    if empty(l:boundary)
        return
    endif
    
    let l:start_line = 4
    let l:end_line = line('$')
    
    for l:i in range(2, line('$'))
        if getline(l:i) == ''
            let l:end_line = l:i - 1
            break
        endif
    endfor
    
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
    
    " Check whether it ends with a semicolon.
	while last_element =~ '^[ \t]*$'
		call remove(sql_list, last_idx)
    	let last_idx = last_idx - 1
    	let last_element = sql_list[last_idx]
	endwhile

    if len(sql_list) == 1 
		redraw!
		call oracle_tui#ShowErr("No SQL statement")
		return
    endif

    if last_element !~ ';[ \t]*$'
        " Add a semicolon.
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
	"Using the delete function will not cause screen flicker
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
				call oracle_tui#ShowErr("List window is missing\n")
				return
			endtry

			if &buftype != "nofile"
				call oracle_tui#ShowErr("Current window buftype is not nofile\n")
				return
			endif
			q!
		else
			call oracle_tui#ShowErr("Window Error\n")
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
	let g:prompt_str = "Press Ctrl+k for completion"

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
		call oracle_tui#ShowErr("No table name:".a:1."\n")
		execute "setlocal laststatus=" . s:save_laststatus
		execute "setlocal statusline=" . escape(s:save_statusline, ' ')
		let g:grep_table_window_flag = 0
		:q
		return
	else
		exe "normal gg"
		"echo "Press :q to exit"
		"sleep 3
	endif
	"<F9> Display table definitions in crtdb.txt
	nnoremap <silent> <buffer> [20~ :ShowTab<CR>
	
	"<F10> Display statements for creating database objects
	nnoremap <silent> <buffer> [21~ :DescObj<CR>

	"Ctrl+k for completion
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
	   	echo "Place the cursor over the word"
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
					"If the current position is .*, continue searching backwards
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
					"If the current position is .*, continue searching backwards
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
		"Do not exit insert mode
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
		   	echo "Place the cursor over the word"
		   	return
   		endif

		let start = matchstr(line[:col-1],  '[a-zA-Z0-9_.]\+$')
		"Cannot use a variable directly before the colon in line[n:10]
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
		echo "No description found for table[".word."]"
	else
		exe "normal gg"
    	call feedkeys(":echo '[/{ Move left [/} right j/J down k/K up'\<CR>", 'n')
		"Valid only within the current buffer
		"cmap <silent> <buffer> q bd
	   	"cmap <silent> <buffer> q bd<bar>execute s:last_win_nr.'wincmd w'
		"cmap <silent> <buffer> q bd<bar>execute winnr('#').'wincmd w'
		"echo "Press :q to exit"
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
		echo "Catch an interrupt"
	endtry
    redraw! "Refresh screen
endfun
command!  DescObj call oracle_tui#DescObj()

"Search for table name based on the word under the cursor
function! oracle_tui#GrepTab() 
	"let word=expand("<cword>")
	let line = getline('.')
	let col = col('.')
	if strpart(line, col-1, 1) == " " ||
       	\ strpart(line, col-1, 1) == "\t" ||
       	\ strpart(line, col-1, 1) == "." 
	   	echo "Place the cursor over the word"
	   	return
   	endif

	let start = matchstr(line[:col-1],  '[^ \t,]\+$')
	"let start = matchstr(line[:col-1],  '[^ \t,@=\-+|:;\"]\+$')
	"let start = matchstr(line[:col-1],  '[a-zA-Z0-9_.*]\+$')

	"Cannot use a variable directly before the colon in line[n:10]
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
		echo "Catch an interrupt"
	endtry
	
    redraw! "Refresh screen
endfun

function! oracle_tui#Tabspace()
	let str = "db_runsql_sqlplus.sh \"select substr(dbf.tablespace_name,1,12) tablespace_name, round(dbf.totalspace,0)  totalspace, dbf.totalblocks, round(dfs.freespace,0) freespace, dfs.freeblocks, round((dfs.freespace / dbf.totalspace)*100,2) idle_ratio from (select t.tablespace_name, sum(t.bytes) totalspace, sum(t.blocks) totalblocks from dba_data_files t group by t.tablespace_name) dbf, (select tt.tablespace_name, sum(tt.bytes) freespace, sum(tt.blocks) freeblocks from dba_free_space tt group by tt.tablespace_name) dfs where trim(dbf.tablespace_name) = trim(dfs.tablespace_name)\""
	if exists('s:username') && exists('s:password')
		let str = str." ".s:username." ".s:password 
	endif

	try
		sil execute  "!".str
	catch 
		echo "Catch an interrupt"
	endtry
	
    redraw! "Refresh screen
endfun

function! oracle_tui#Tabused()
	let str = "db_runsql_sqlplus.sh \"select cast(substr(Segment_Name,1,30) as char(30)) ObjName,Sum(bytes) Totsize From User_Extents Group By Segment_Name order by 2 desc\""
	if exists('s:username') && exists('s:password')
		let str = str." ".s:username." ".s:password 
	endif

	try
		sil execute  "!".str
	catch 
		echo "Catch an interrupt"
	endtry
	
    redraw! "Refresh screen
endfun

function! oracle_tui#Nowsql()
	let str = "db_runsql_sqlplus.sh \"SELECT osuser, username, a.PROGRAM, b.sql_id,b.address,piece,sql_text from v\\$session a, v\\$sqltext b where a.sql_address =b.address order by osuser,username,sql_id,piece\""
	if exists('s:username') && exists('s:password')
		let str = str." ".s:username." ".s:password 
	endif

	try
		sil execute  "!".str
	catch 
		echo "Catch an interrupt"
	endtry
	
    redraw! "Refresh screen
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
		echo "Catch an interrupt"
	endtry
	
    redraw! "Refresh screen
endfun

"Execute all SQL statements in the file
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
    "No need to press Enter.
	let output = substitute(output, "\n", "", "g") 
	if output == "Execution completed" || output == ""
		if a:flag == 1
			let output = "Submit completed"
		else
			let output = "Rollback complete"
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
				call oracle_tui#ShowErr("Interrupt listing database objects")
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
		"tabstop must match shiftwidth length, otherwise indentation will not work
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
		"Valid only within the current buffer
		"cmap <silent> <buffer> q bd<bar>wincmd p
		"cmap <silent> <buffer> q bd<bar>execute s:last_win_nr.'wincmd w'
		"cmap <silent> <buffer> q bd<bar>execute winnr('#').'wincmd w'

		"<F9> Display table definitions in crtdb.txt
		nnoremap <silent> <buffer> [20~ :ShowTab<CR>
		
		"<F10> Display statements for creating database objects
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

	"sil execute "! ".sql

	let output=system(sql)
	"redraw!
	let exit_status = shell_error
	if exit_status == 1
		let str = "Uncommitted transaction exists"
		call oracle_tui#ShowErr(str)
	else
		let str = "No uncommitted transaction"
		echo str
	endif
endfun

function! oracle_tui#CheckIfCommit()
	let pid=getpid()
	let sql="db_check_trans.sh ".pid

	if exists('s:username') && exists('s:password')
		let sql = sql." ".s:username." ".s:password 
	endif
	"Using sil will clear the screen
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
            	call oracle_tui#ShowErr("Uncommitted transaction exists. Cannot exit. Press F2 to rollback, F6 to commit")
            	call feedkeys("\<CR>", 'n')
				"Without sleep, the error message flashes by
				sleep 1
				return ''
			else
            	call oracle_tui#ShowErr("Uncommitted transaction exists. Cannot exit. Press F2 to rollback, F6 to commit")
				"Without this line, the cursor stays on the error message line, requiring an extra Enter press
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
            call oracle_tui#ShowErr("Uncommitted transaction exists. Cannot exit. Press F2 to rollback, F6 to commit")
            call feedkeys("\<CR>", 'n')
            return ''
        endif
	else
		return 'x'
    endif
endfunction

function! oracle_tui#DBCliHelp()
	echo "+------------------------------------------------------------------------+"
    echo "|                       Key Instructions                                 |"
    echo "| F8: Execute SQL (Use Shift+v or Ctrl+v to select SQL first;            |"
    echo "|     if not selected, executes the current line)                        |"
    echo "| Ctrl+c: Interrupt ongoing operation                                    |"
    echo "| F2/F6: Rollback Transaction/Commit Transaction                         |"
    echo "| F4: Check for uncommitted transactions                                 |"
    echo "| F5: Show SQL Execution Plan (Use Shift+v to select SQL first;          |"
    echo "|     if not selected, checks the current line)                          |"
    echo "| F7: List Database Objects                                              |"
    echo "| F9: Show table structure definition for the word under the cursor      |"
    echo "| F10: Show creation statement for the database object under the cursor  |"
    echo "|       -: Decrease window width             =: Increase window width    |"
    echo "| Shift+-: Decrease window height      Shift+=: Increase window height   |"
	echo "| Ctrl+↑: Jump to up window            Ctrl+↓: Jump to down window       | "
	echo "| Ctrl+→: Jump to right window         Ctrl+←: Jump to left window       | "
    echo "| Ctrl+n: Auto-complete, Only Supports prefix string,Insert mode         |"
    echo "| Ctrl+k: Auto-complete, Support non-prefix string,Insert and Normal Mode|"
    echo "| gt: Switch between tabs                                                |"
    echo "| :Tablist: Show table name and comment                                  |"
    echo "| :Seelock: View locks                                                   |"
    echo "| :Unlock: Unlock                                                        |"
    echo "| :Tabused: View space usage for each table                              |"
    echo "| :Tabspace: View tablespace usage                                       |"
    echo "| :Nowsql: View currently running SQL                                    |"
    echo "|                      Created by Zang Jianwei                           |"
	echo "+------------------------------------------------------------------------+"
endfun

"The following is the browser.
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
		echo "Catch an interrupt"
	endtry
    redraw! "Refresh screen
endfun

"Initialize without loading the column definition file
let s:load_column_define_flag = 0
let s:field_charset = []
let s:field_data_len = []
let s:field_widths = []
let s:field_types = []
let s:field_names = []
"Total number of lines in the current file
let s:tot_line_num = 0
fun! oracle_tui#ReadColumn()
	"Do not load again if it has already been loaded once
	"Because opening a file with tabnew and then closing it with tabclose will re-invoke ReadColumn
	if s:load_column_define_flag == 0
		let s:load_column_define_flag = 1
	else
		return
	endif
	
	normal! 20zl

	"Get total number of lines in the current file
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

    let lines = readfile(col_file)
    
    for line in lines
        let parts = split(line)
        call add(s:field_names,  parts[0])
        call add(s:field_types,  parts[1])
		"s:field_widths stores the alignment width, taking the maximum of the data length and field name length
		"Convert to numbers here for comparison, otherwise it will compare as strings
		if str2nr(parts[2]) >= str2nr(parts[3])
        	call add(s:field_widths, str2nr(parts[2]))
		else
        	call add(s:field_widths, str2nr(parts[3]))
		endif
		"s:field_data_len is the length of the data
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
	echo "Data has been cleared"
endfun

fun! oracle_tui#Update()
	:w
    let file=expand("%")
    let shortfile = substitute(file, '.txt.new', '', "g")
    let cmd = "!clear && db_update_data.sh ".shortfile
	"if exists('s:username') && exists('s:password')
	"	let cmd = cmd." ".s:username." ".s:password 
	"endif

	"Catch exceptions here; otherwise, the shell will be interrupted and subsequent statements will not execute (e.g., redraw!)
	try
    	"sil execute "!clear && db_update_data.sh ".shortfile
    	sil execute cmd
	catch 
		echo "Catch an interrupt"
		"sleep 3
	endtry

	let status = shell_error
	"1: Update error 2: Execution interrupted 0: Update successful 4: Database connection lost
	"Do not exit when delimiters are mismatched, an update error occurs, or re-modification is needed

	if status != 1
		:qall!
		return
	endif

	redraw!

	call oracle_tui#ShowErr("Please edit this again")
endfun

"Reduce column width
func! oracle_tui#ReduceColumn()
	let cur_linenum = line('.')
	let line1 = getline('.')
    "Virtual columns need to be retrieved
	let vir_col = virtcol('.')  
	let real_col = col('.')  
	"if strpart(line1, vir_col-1, 1) == " " || strpart(line1, vir_col-1, 1) == "\t"
	"    \ || strpart(line1, vir_col-1, 1) == ""

	"if strpart(line1, vir_col-1, 1) == ""
	"   	echo "Place the cursor over the word"
	"	return
	"endif

	call cursor(3,vir_col)

	let line = getline('.')
	if strpart(line, vir_col-1, 1) != "-"
		call oracle_tui#ShowErr("Place the cursor at column\n")
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

	"let cmd="2,".end_line." s/\\%".start."c.\\{".len."\\}//g"

	"let end=end+1
	"let cmd="2,".end_line." normal! ".start."|d".end."|"
	"silent execute cmd

	let linenums = end_line - 2 
	call cursor(2, start)

	let cmd = "normal! \<C-V>".end."|".linenums."jx"
	
	sil execute cmd

	call cursor(cur_linenum, real_col)
endfunc

"Get the field boundaries based on the cursor position.
function! oracle_tui#GetFieldBoundaries(line, pos)
    " Get the passed-in line string.
    let l:line_content = a:line
    let l:pos = a:pos
    
    " Check whether the position is valid.
    if l:pos < 1 || l:pos > len(l:line_content)
		call oracle_tui#ShowErr("Please place the cursor at the field position")
        return {}
    endif
    
    " Check whether the character is a space.
    if l:line_content[l:pos - 1] == ' '
		call oracle_tui#ShowErr("Please place the cursor at the field position")
        return {}
    endif
    
    " Find field boundaries.
    let l:start = l:pos
    let l:end = l:pos
    
    " Search left for the starting position of the field.
    while l:start > 1 && l:line_content[l:start - 2] != ' '
        let l:start -= 1
    endwhile
    
    " Search right for the ending position of the field.
    while l:end < len(l:line_content) && l:line_content[l:end] != ' '
        let l:end += 1
    endwhile
    
    return {'start': l:start, 'end': l:end}
endfunction

let g:last_cut_column_flag = 0

"Cut all columns under the current cursor position.
function! oracle_tui#CutColumn()
    let l:col_data = []
    
    let l:cur_line = line('.')
    let l:vir_col = virtcol('.')
    let l:separator_text = getline(3)
	let real_col = col('.')  
    
    let l:boundary = oracle_tui#GetFieldBoundaries(l:separator_text, l:vir_col)
    if empty(l:boundary)
        return
    endif
    
    let l:start_line = 2
    let l:end_line = line('$')
    
    for l:i in range(2, line('$'))
        if getline(l:i) == ''
            let l:end_line = l:i - 1
            break
        endif
    endfor
    
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

	"autocmd CursorMoved <buffer> call oracle_tui#ViewHideTitleLines()
    "for l:i in range(l:start_line, l:end_line)
    "    let l:line_text = getline(l:i)
    "    
    "    let l:col_content = strpart(l:line_text, l:boundary.start - 1, l:boundary.end - l:boundary.start + 1)
    "    call add(l:col_data, l:col_content)

	"	if l:boundary.start == 1
    "    	let l:new_line = strpart(l:line_text, l:boundary.end + 1)
	"	else
    "    	let l:new_line = strpart(l:line_text, 0, l:boundary.start - 2) . 
    "                \ strpart(l:line_text, l:boundary.end)
	"	endif
    "    call setline(l:i, l:new_line)
    "endfor
endfunction

" Paste all the cut columns after the current column.
function! oracle_tui#PasteColumn()
    if g:last_cut_column_flag != 1 && g:last_cut_column_flag != 2
        echo "No data to paste"
        return
    endif

	"autocmd! CursorMoved <buffer>
    
    let l:cur_line = line('.')
    let l:cur_col = col('.')
    let l:vir_col = virtcol('.')
    
    let l:separator_text = getline(3)

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

	"Without the following line, the title row will be displayed repeatedly.
	call feedkeys("lh", 'n')

	"let cmd = ":autocmd CursorMoved <buffer> call oracle_tui#ViewHideTitleLines()\<CR>:call cursor(".l:cur_line.",".l:cur_col.")\<CR>"
	"call feedkeys(cmd, 'n')

	"echom "l:boundary.end=".l:boundary.end
    
    "let l:start_line = 2
    "let l:end_line = line('$')
    "
    "for l:i in range(2, line('$'))
    "    if getline(l:i) == ''
    "        let l:end_line = l:i - 1
    "        break
    "    endif
    "endfor
    "
    "for l:i in range(l:start_line, l:end_line)
    "    let l:line_idx = l:i - l:start_line
    "    let l:line_text = getline(l:i)
    "    
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
"Sort by the content of a specific column
"Since sort -n does not sort negative numbers correctly, use a sorting function instead
func! oracle_tui#Sort(sort_flag)
	let save_cursor = getpos('.')
	let line1 = getline('.')
	let col1 = col('.')
	let vir_col = virtcol('.')
	"if strpart(line1, col1-1, 1) == " " || strpart(line1, col1-1, 1) == "\t"
	"    \ || strpart(line1, col1-1, 1) == ""
	"if line(".") < 4
	"	echo "Please place the cursor on or below line 4"
	"	return 
	"endif

	"if strpart(line1, col1-1, 1) == ""
	"  	echo "Place the cursor over the word"
	"	return
	"endif

	call cursor(3,vir_col)
	let line3 = getline('.')

	if strpart(line3, vir_col-1, 1) == " " || strpart(line3, vir_col-1, 1) == "" 
    	call setpos('.', save_cursor)
		let vir_col = vir_col -1
		exe "normal! ".vir_col."|"
		call oracle_tui#ShowErr("Please place the cursor on the column")
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
		let type = 1 "numeric
	else
		let type = 2 "Non-numeric
	endif

    call setpos('.', save_cursor)

	call oracle_tui#ColSort(a:sort_flag, type)
endfunc

"Sort in ascending numerical order
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

"Sort in descending numerical order
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

"Sort in alphabetical order
function! ChrCompareAsc(i1,i2)
	let v1 = g:column_list[a:i1]
	let v2 = g:column_list[a:i2]
	return v1 ==# v2 ? 0 : v1 > v2 ? 1 : -1
endfunc

"Sort in reverse alphabetical order
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
	"   	echo "Place the cursor over the word"
	"	return
	"endif

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
	"You must add the following line, otherwise there will be issues in Vim 9.2
	syntax clear

	setlocal conceallevel=2
	if v:version >= 800
		setlocal concealcursor=nvic
	els
		setlocal concealcursor=nvc
	endif
	"If the line length exceeds the default 3000, 
	"the subsequent content will not be converted.
	setlocal synmaxcol=100000
	"Hide the first column
	syn match HiddenRowID /^[^]*/ conceal
	"syn match HiddenRowID /"/ conceal
	syn match Substitute // conceal cchar=|
	syn match Substitute // conceal cchar=?

	"Display \t as ?
	syn match Substitute /	/ conceal cchar=?

	redraw!
endfun

"Restore hidden.
function! oracle_tui#NoHid()
	"syn clear match HiddenRowID 
	set conceallevel=0
endfun

"The first row cannot be modified
function! oracle_tui#ProtectFirstLine()
	"if line('.') == 1 
	"	setlocal readonly
	"	echo "The first row cannot be modified"
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
"Show differences compared to the original file
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
		"Cancel synchronized scrolling between two screens
		"Keep horizontal and vertical synchronization
		"set scrollbind
		"Cancel vertical synchronization, keep horizontal synchronization
		"set nocursorbind
		let s:show_diff_flag = 1
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

"Display modifications in real-time when editing a line (only effective in Insert mode (press ESC after input), invalid in x, X modes).
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

"Jump to the next field
function! oracle_tui#JumpNextColumn()
	if strpart(getline('.'),col('.')) =~ ""
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
			call oracle_tui#ShowErr("Go to end of file")
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

"Jump to the next delimiter
function! oracle_tui#EditColumnAfter2()
	let current_column_num = oracle_tui#GetCurrentColumn()
	let next_column_num = current_column_num + 1

	let result = oracle_tui#AlignColumnReal() 
    if result == 0
		"call oracle_tui#EditColumnAfter()
		call oracle_tui#JumpToColumn(next_column_num)
	endif
endfunction

"Jump to the next delimiter
function! oracle_tui#EditColumnBefore2()
	let current_column_num = oracle_tui#GetCurrentColumn()
	let next_column_num = current_column_num - 1
	let result = oracle_tui#AlignColumnReal() 
    if result == 0
		"call oracle_tui#EditColumnBefore()
		call oracle_tui#JumpToColumn(next_column_num)
	endif
endfunction

"Jump to the next delimiter
function! oracle_tui#EditColumnAfter()
	"if strpart(getline('.'),col('.')-1) =~ ""
	if strpart(getline('.'),col('.')) =~ ""
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
    			    call cursor(line('.'), first_comma + 3)
    			endif
			endif
		catch /^LastLineError$/
			call oracle_tui#ShowErr("Go to end of file")
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

"Jump to the previous delimiter
function! oracle_tui#EditColumnBefore()
	"If the cursor is on a delimiter, move one position backward
	if strpart(getline('.'),col('.')-1,1) == ""
		call cursor(line('.'),col('.')+1)
		"call oracle_tui#CursorMovedForUpdate()
	endif

	"If there is a column delimiter before the current cursor, jump to the position after the second previous delimiter
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
			"Go to the beginning of the line
			call cursor(line('.'),1)
			call oracle_tui#CursorMovedForUpdate()
			startreplace
		endif
	else
		try
			if line('.') == 2
				throw 'FirstLineError'
			else
				"Jump to the end of the previous line
				normal! k$
			endif
		catch /^FirstLineError$/
			call oracle_tui#ShowErr("Go to start of file")
			echo ""
			return 
		endtry

		if strpart(getline('.'), 0, col('.')) =~ ""
			exec "normal F" 
			call cursor(line('.'),col('.')+1)
			"call oracle_tui#CursorMovedForUpdate()
			startreplace
		else
			"Go to the beginning of the line
			call cursor(line('.'),1)
			call oracle_tui#CursorMovedForUpdate()
			startreplace
		endif
	endif
endfunction

"Jump to the previous delimiter.
function! oracle_tui#JumpBeforeColumn()
	if strpart(getline('.'),col('.')-1,1) == ""
		call cursor(line('.'),col('.')+1)
		"call oracle_tui#CursorMovedForUpdate()
	endif

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
					normal! k$
				endif
			catch /^FirstLineError$/
				call oracle_tui#ShowErr("Reached the beginning of the file")
				echo ""
				return 
			endtry

			if strpart(getline('.'), 0, col('.')) =~ ""
				exec "normal F" 
				call cursor(line('.'),col('.')+1)
				"call oracle_tui#CursorMovedForUpdate()
				"startreplace
			else
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
			call oracle_tui#ShowErr("Selected row count mismatch with register")
			return
		endif
	endif

    let s:visual_insert = {
        \ 'start_line': line("'<"),
        \ 'end_line': line("'>")
        \ }

	"Executing normal! gv changes the value of v:register
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
	"Description of v:register:
	"If you type p, v:register equals ".
	"If you type "ap, v:register equals a.
	"If you type "bp, v:register equals b.
	"If you type "cp, v:register equals c.
	"And so on.
	let content = getreg(v:register)

	let lines = split(content, "\n", 1)
	"For full-line copies, len(lines) is one greater than the actual number of lines copied; however, the alignment range perfectly covers the copied lines
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
	"If it is on a single line, the TextChanged event will not be triggered
	if line("'<") <= 1
		redraw!
		call oracle_tui#ShowErr("Cannot delete the first row")
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
		call oracle_tui#ShowErr("Cannot delete in v mode!")
		return
	else
		normal! gvx
	endif
endfunction

function! oracle_tui#VisualSaveStateD()
	"If it is on a single line, the TextChanged event will not be triggered
	if line("'<") <= 1
		redraw!
		call oracle_tui#ShowErr("Cannot delete the first row")
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
		call oracle_tui#ShowErr("Cannot delete in v mode!")
		return
	else
		normal! gvD
	endif
endfunction

"If it is a digit, delete it and move the cursor one character forward
function! oracle_tui#Process_x()
    let current_line = getline('.')
    let cursor_col = col('.') - 1
    
    "Find the field where the cursor is located
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
		"normal x X dw de D  for one line
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
    "Process each line (starting from the second line) 
	if s:visual_insert.start_line <= 1
		normal! u
		redraw!
		call oracle_tui#ShowErr("The title row cannot be modified")
		"Add the following line
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
				call oracle_tui#ShowErr("Only one column can be modified at a time")
			else
				call oracle_tui#ShowErr("The number of columns exceeds the number of fields")
			endif
			"Add the following line
    		unlet s:visual_insert
			return 1
		endif

        let new_fields = []

		"The length of the LOB field exceeds the original array length
    	let add_len = {}

    	"Align each field 
    	for i in range(len(fields))
			"First, remove the trailing NBSP characters, then replace any remaining ones with spaces
    		let field = substitute(fields[i], ' *$', '', 'g')
    		let field = substitute(field, ' ', ' ', 'g')

			if s:field_types[i] == 2 || s:field_types[i] == 100 || s:field_types[i] == 101
				"Numeric type
    	    	let field = substitute(field, ' ', '', 'g')
			elseif s:field_types[i] == 96
				"If it is a CHAR type, keep it unchanged if it consists only of spaces; otherwise, remove trailing spaces
				if field !~ "^  *$"
    	    		let field = substitute(field, ' *$', '', 'g')
				endif
			elseif s:field_types[i] != 1 && s:field_types[i] != 112 
				"varchar2/nvarchar2/clob/nclob can not trim space
    	    	let field = substitute(field, ' *$', '', 'g')
			endif

			"Right-align numbers
			if s:field_types[i] == 2 || s:field_types[i] == 100 || s:field_types[i] == 101
				"Right-align
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
					"If the LOB field contains a filename, restore it using the content from the pre-replacement backup
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
						"	call oracle_tui#ShowErr("LOB fields can only be modified using Ctrl+a")
						"	return
						"endif
    	    			let field = substitute(field, ' ', '', 'g')
						if field !~# '^<lob_.*.txt.old>$' && field !~# '^<lob_.*.txt.new>$' && field != ''
							normal! u
							redraw!
    						unlet s:visual_insert
							call oracle_tui#ShowErr("This field can only be modified using Ctrl+a")
							"Disable tooltips on cursor idle
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
				"char/nchar/varchar2/nvarchar2 
    	    	call add(new_fields, field.repeat(' ', s:field_widths[i] - strwidth(field)))
			else
				"Left-align
    	    	call add(new_fields, field.repeat(' ', s:field_widths[i] - strwidth(field)))
			endif

			if s:field_types[i] == 96 && field =~ "^  *$" 
				if  strwidth(field) > str2nr(s:field_widths[i])
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
    	
    	" Recombine lines
    	call setline(lnum, join(new_fields, ''))
    endfor

	"If a LOB field in any row exceeds the original length, extend the column length for the entire file
	if extend_lob_file_flag == 1
    	for lnum in range(1, line('$'))
			"The bottom part shouldn't be there
			"if lnum >= s:visual_insert.start_line && lnum <= s:visual_insert.end_line
			"	continue
			"endif

    	    let line = getline(lnum)
    	    let fields = split(line, '', 1)
    	    let new_fields = []
    	    
    	    " Align all fields
    		for i in range(len(fields))
    			let field = fields[i]
				if (s:field_types[i] == 112 ||
					\ s:field_types[i] == 8 ||
					\ s:field_types[i] == 113 ||
					\ s:field_types[i] == 24)
					"lob
    		    	call add(new_fields, field.repeat(' ', s:field_widths[i] - strwidth(field)))
				else
					"Left-align
    		    	call add(new_fields, field)
				endif
    		endfor
    	    
			if (lnum == 1)
				let s:title_line = join(new_fields, '')
			endif
    	    " Recombine lines
    	    call setline(lnum, join(new_fields, ''))
    	endfor
	endif
    
    "call setpos('.', save_cursor)

	diffupdate
	call winrestview(view)

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
		"Add a newline character and prompt the user to press Enter; otherwise, the information will flash by too quickly
		call oracle_tui#ShowErr("Modification exceeds the current column length\n")
		return 1
	endif

	return 0
endfunction

"Align all fields in the entire file
function! oracle_tui#AlignColumn()
    let save_cursor = getpos('.')

    for lnum in range(2, line('$'))
        let line = getline(lnum)
        let fields = split(line, '', 1)
        let new_fields = []
        
        "Get the maximum length of the LOB fields
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
        
        " Align all fields
    	for i in range(len(fields))
			"First, remove the trailing NBSP characters, then replace any remaining ones with spaces
    		let field = substitute(fields[i], ' *$', '', 'g')
    		let field = substitute(field, ' ', ' ', 'g')

			"Numeric type
			if s:field_types[i] == 2 || s:field_types[i] == 100 || s:field_types[i] == 101
    	    	let field = substitute(field, ' ', '', 'g')
			endif

			"If it is a CHAR type, keep it unchanged if it consists only of spaces; otherwise, remove trailing spaces
			if s:field_types[i] == 96
				if field =~ "^  *$"
					let field = " "
				else
    	    		let field = substitute(field, ' *$', '', 'g')
				endif
			endif

			"Right-align numbers
			if s:field_types[i] == 2 || s:field_types[i] == 100 || s:field_types[i] == 101
				"Right-align
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
					"If the LOB field contains a filename, restore it using the content from the pre-replacement backup
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
						"	call oracle_tui#ShowErr("LOB fields can only be modified using Ctrl+a")
						"	return
						"endif
    	    			let field = substitute(field, ' ', '', 'g')
						if field !~# '^<lob_.*.txt.old>$' && field !~# '^<lob_.*.txt.new>$' && field != ''
							normal! u
							redraw!
    						unlet s:visual_insert
							call oracle_tui#ShowErr("This field can only be modified using Ctrl+a")
							"Disable tooltips on cursor idle
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
				"varchar2/nvarchar2 add with nbsp
    	    	call add(new_fields, field.repeat(' ', s:field_widths[i] - strwidth(field)))
			else
				"Left-align add with space
    	    	call add(new_fields, field.repeat(' ', s:field_widths[i] - strwidth(field)))
			endif

			"Check against the maximum data length, not the display length
			if strwidth(field) > str2nr(s:field_data_len[i]) 
				\ && s:field_types[i] != 112 
				\ && s:field_types[i] != 8
				\ && s:field_types[i] != 113 
				\ && s:field_types[i] != 24
				let more_flag = 1
			endif
    	endfor
        
        " Recombine lines
        call setline(lnum, join(new_fields, ''))
    endfor
    
    call setpos('.', save_cursor)

	"redraw!
	if more_flag == 1
		"Add a newline character and prompt the user to press Enter; otherwise, the information will flash by too quickly
		call oracle_tui#ShowErr("A column exceeds the current column length")
	endif
endfunction

let s:show_update_title_flag = 0
function! oracle_tui#ShowUpdateTitle()
	if s:show_update_title_flag == 0
		if winwidth(0) < &columns
			call oracle_tui#ShowErr("The title line is not available in a vertically split window")
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
			execute "normal! 2zt"
		endif
		call cursor(cur_line,cur_col)
		"Add the following line,Otherwise, they won't align horizontally
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
			"You must add the line below; otherwise, there will be issues when moving the screen right by pressing 0
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
			call oracle_tui#ShowErr("The title line is not available in a vertically split window")
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
		"There is an issue in the Vim 7.2 environment.
		"call cursor(1,cur_col)
		exec "normal! gg" 
		"let &l:stl="%#Normal#".repeat('=',winwidth(0))
		"highlight MyStatusLine ctermbg=Yellow ctermfg=Black
		let &l:stl="%#Comment#".repeat('=',winwidth(0))

		wincmd j
		if top_line <= 4
			execute "normal! 4zt"
		endif
		call cursor(cur_line,cur_col)
		"Add the following line,Otherwise, they won't align horizontally
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
        " If line 1 is displayed, scroll down 2 lines
        execute "normal! 3\<C-e>"
    elseif top_line == 2
        " If line 2 is displayed, scroll down 1 line
        execute "normal! 2\<C-e>"
    elseif top_line == 3
        " If line 2 is displayed, scroll down 1 line
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

function! oracle_tui#ReShowNullChar()
	if s:show_nullchar_flag == 1
		syn match Substitute / / conceal cchar=-
	endif
endfunction

let s:current_pipe_field = 0
let s:current_pipe_line = 0
let s:original_field_content = ''
function! oracle_tui#PipeFieldEdit()
    " Get the current line content and cursor position
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
    
    " Get the current line content and cursor position
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
    
    " Save the current field index and line number
    let s:current_pipe_field = current_field
    let s:current_pipe_line = line('.')
    let s:original_field_content = fields[current_field]
	let s:original_field_content = substitute(s:original_field_content, " *$", "", "g")
	"let s:original_field_content = substitute(s:original_field_content, "^ *", "", "g")
	if s:field_types[current_field] == 96 
		"char/nchar
	elseif s:field_types[current_field] != 1
		let s:original_field_content = substitute(s:original_field_content, "^ *", "", "g")
		let s:original_field_content = substitute(s:original_field_content, " *$", "", "g")
	endif

    
    " Create a temporary buffer in a new tab (without saving to a file)
	if (s:field_types[current_field] == 112 || 
		\ s:field_types[current_field] == 8 ||
		\ s:field_types[current_field] == 113 ||
		\ s:field_types[current_field] == 24 ) 
		\ && lob_file_flag == 1
		"Remove spaces
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
		"autocmd BufWriteCmd <buffer> redraw!|echo "Please press Ctrl+a to save"
		"cnoremap <buffer> <expr> w oracle_tui#HandleWrite()
		"cnoremap <buffer> <expr> x oracle_tui#HandleWrite_x()
		cnoremap <buffer> <expr> <CR> oracle_tui#CheckSaveCommand()
		inoremap <buffer> <C-A> <Nop>
		"autocmd BufWriteCmd <buffer> redraw!|
    	"		\ if expand('%') =~# '.txt.old$' |
    	"		\   echo "Please press Ctrl+a to save" |
    	"		\ else |
    	"		\   write |
    	"		\ endif
	else
    	tabnew
    	setlocal buftype=nofile    " Not associated with a physical file
    	setlocal bufhidden=delete  " Automatically delete when hidden
    	setlocal noswapfile        " Do not create a swap file
		inoremap <buffer> <C-A> <Nop>
	endif

	setlocal nonu
	"setlocal timeout
	"setlocal ve=
    
	let g:prompt_str = "Ctrl+a:Save changes  q:Discard changes"
	setlocal laststatus=2
	setlocal statusline=%{g:prompt_str}\ %=%l,%c-%v\ %{&fileencoding} 
	if (s:field_types[current_field] == 112 ||
	  	\ s:field_types[current_field] == 8 ||
	  	\ s:field_types[current_field] == 113 ||
	  	\ s:field_types[current_field] == 24 )
		\ && lob_file_flag == 1
    	" Map Ctrl+a to save and close
    	nnoremap <buffer> <silent> <C-A> :SavePipeLobField<CR>
	else
    	" Fill in the original field content
    	call setline(1, split(s:original_field_content, ''))
    	
    	" Map Ctrl+a to save and close
    	nnoremap <buffer> <silent> <C-A> :SavePipeField<CR>
		"echo "Press Ctrl+N to save changes; use :q to discard changes"
		"let s:prompt_str = "Press Ctrl+a to save changes, :q to discard"
		"setlocal ve=
		"setlocal laststatus=2
		"setlocal statusline=%{s:prompt_str}
		"echo "Press Ctrl+a to save changes, :q to discard"
	endif
endfunction

function! oracle_tui#HandleWrite()
    let type = getcmdtype()
    let cmd = getcmdline()

    if type == ':' && (cmd =~# '^[ \t]*$' )
        call oracle_tui#ShowErr("Press Ctrl+a to save changes, :q to discard")
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
        call oracle_tui#ShowErr("Press Ctrl+a to save changes, :q to discard")
        call feedkeys("\<CR>", 'n')
        return ''
	else
		return 'x'
    endif
endfunction

function! oracle_tui#SavePipeField()
    "  Get the content after editing
    let lines = getline(1, '$')
	"  The value of new_content still exists after executing tabclose
    let new_content = len(lines) > 1 ? join(lines, '') : lines[0]
    
    " Close the current tab
    tabclose

	setlocal laststatus=1

	"The following original_buf returns -1
    "Return to the original buffer
    "let original_buf = bufnr('#')
    "if original_buf != -1
    "    execute 'buffer ' . original_buf
    "endif
    
    "Update the original file 
	let current_col = virtcol('.')
    if exists('s:current_pipe_line') && exists('s:current_pipe_field')
        let current_line = getline(s:current_pipe_line)
        let fields = split(current_line, '', 1)
        let fields[s:current_pipe_field] = new_content
        call setline(s:current_pipe_line, join(fields, ''))
		call oracle_tui#AlignColumnReal() 
    endif
	exe "normal! ".current_col."|"   
	                                 
	normal! ma
	normal! gg
	normal! `a
    
    " Clear the variable
    unlet! s:current_pipe_field s:current_pipe_line s:original_field_content
endfunction

function! oracle_tui#SavePipeLobField()
    " Get the edited content
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

    " Close the current tab
    tabclose

	setlocal laststatus=1
    
    " Update the original file
    if exists('s:current_pipe_line') && exists('s:current_pipe_field')
		if new_content != ""
        	let current_line = getline(s:current_pipe_line)
        	let fields = split(current_line, '', 1)
        	let fields[s:current_pipe_field] = new_content
        	call setline(s:current_pipe_line, join(fields, ''))
			call oracle_tui#AlignColumnReal() 
		endif
    endif
    
    " Clear the variable
    unlet! s:current_pipe_field s:current_pipe_line s:original_field_content
endfunction

" Cursor positioning function
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
        return
    endif
endfunction

function! oracle_tui#Smart_zH()
    " Get the leftmost displayed column on the current screen
    let screen_col = wincol()
    let current_col = virtcol('.')

    if current_col - screen_col > 20 + winwidth(0)/2
        normal! zH
    else
        "echo "The first column is completely obscured and will not move further left"
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

"Prevent :set from being replaced
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
					"Replace the carriage return with NBSP character, otherwise it cannot be passed through
        			let modified_cmd = substitute(modified_cmd, '', ' ', '')
				endif
        		"call feedkeys(":\<C-U>" . modified_cmd . "\<CR>", 'n')
				"call feedkeys("\<C-U>ShowErr Invalid command.\<CR>", 'n')
				"In this function, the file content cannot be modified. Directly calling call oracle_tui#AlignColumn() will cause an error. You can call it using the following method
				"The statements after the feedkeys function will not be called, but using timer_start below can call them
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
			"For example, commands ending with 's' such as ls, messages, buffers, etc., are ignored.
			"elseif cmd =~# 's[ \t]*$' "s
        	"	"let modified_cmd = substitute(cmd, 's[ \t]*$', 'MySubstitute', '')
        	"	let modified_cmd = 'ShowErr No parameters'
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

    "Execute the original command
    return "\<CR>"
endfunction

function! oracle_tui#CheckSaveCommand() abort
    let cmd = getcmdline()
    let type = getcmdtype()

    if type == ':' && (cmd =~# '^[ \t]*w'||cmd =~# '^[ \t]*x')
        let modified_cmd = ":call oracle_tui#ShowErr('Press Ctrl+a to save changes,:q to discard')"
        return "\<C-U>" . modified_cmd . "\<CR>"
	else
    	"Execute the original command
    	return "\<CR>"
    endif
endfunction

function! oracle_tui#CheckListObjViewCommand() abort
    let cmd = getcmdline()
    let type = getcmdtype()

    if type == ':' && (cmd =~# '^[ \t]*q'||cmd =~# '^[ \t]*x')
		let g:brow_objects_window_flag = 0
    endif

    return "\<CR>"
endfunction

function! oracle_tui#CheckMainCommand() abort
    let cmd = getcmdline()
    let type = getcmdtype()

    if type == ':' && (cmd =~# '^[ \t]*q'||cmd =~# '^[ \t]*wq'||cmd =~# '^[ \t]*x')
		if exists('w:main_window_flag') && w:main_window_flag == 1
        	if oracle_tui#CheckIfCommit()
        	    let modified_cmd = ":call oracle_tui#ShowErr('Cannot exit with uncommitted transactions.Press F2/F6 to rollback or commit')"
				"feedkeys does not work properly in Vim version 7.2
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

    "Execute the original command
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

    "Execute the original command
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
    let &verbose = 0  " Disable detailed error messages

    try
        execute a:line1 . ',' . a:line2 . 's' . a:args
        call oracle_tui#AfterSubstitute(a:line1, a:line2)
    catch /E486:/  " Pattern not found
        "echoerr 'Replacement failed: No matching pattern found'
		call oracle_tui#ShowErr(v:exception)
    catch /E476:/  " Invalid parameter
        "echoerr 'Replacement failed: Invalid parameter'
		call oracle_tui#ShowErr(v:exception)
    catch /.*/
        "echoerr 'Replacement failed: ' . v:exception
		call oracle_tui#ShowErr(v:exception)
	finally
        " Restore settings
        let &verbose = verbose_save
    endtry
endfunction

let s:field_lob_content = {} 

"Save the lob field file name before replacement
function! oracle_tui#SaveLobContent(start_line, end_line) abort
    for lnum in range(a:start_line, a:end_line)
    	let line_text = getline(lnum)
        let fields = split(line_text, '', 1)
    	for i in range(len(fields))
			"First, remove the trailing NBSP characters, then replace the remaining NBSP characters with spaces
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
	"Skip the modification of the first line
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

	"When replacing the carriage return, prepend a rowid field column (the carriage return is replaced with an NBSP character, otherwise it cannot be passed through)
    let sub_str = substitute(a:args, ' ', 'XXXXXXXXXXXXXXXXXX', '')
    silent! execute start_line . ',' . end_line . 's' . sub_str

    " Check for errors
    if v:errmsg != ''
        " Determine the error type based on the error message
        if v:errmsg =~# 'E486:'
			"echoerr Detailed error messages will be displayed
            "echoerr 'Replacement failed: No matching pattern found'
			let errstr = substitute(v:errmsg, '\\%>19c', "", "g")

			call oracle_tui#ShowErr(errstr)
        elseif v:errmsg =~# 'E476:'
            "echoerr 'Replacement failed: Invalid parameter'
			call oracle_tui#ShowErr(v:errmsg)
        else
            "echoerr 'Replacement failed: ' . v:errmsg
			call oracle_tui#ShowErr(v:errmsg)
        endif
		let v:errmsg = ''
        return  
    endif

    " If there are no errors, execute the subsequent function
    call oracle_tui#AfterSubstitute(start_line, end_line)
endfunction

"nnoremap <silent> <buffer> dw :set operatorfunc=AdjustSpacesOperator<CR>g@w
"Explanation of the mapping above:
"g@w selects from the current position to the beginning of the next word
"Vim automatically sets [ and]
"Your function is called with type='line'
"[d] deletes the previously selected range
"Then your custom logic is executed
function! oracle_tui#AdjustSpacesOperator(type)
    "Execute the original dw operation
    execute 'normal! `[d`]'
    call oracle_tui#AlignColumnReal()
endfunction

function! oracle_tui#MyDeleteMapping()
    " save old operatorfunc
    let s:old_opfunc = &operatorfunc

    " Set a custom function
    set operatorfunc=MyDeleteOperator

    " Returning g@ will wait for a motion command
    return 'g@'
endfunction

function! MyDeleteOperator(type, ...)
    " Execute the original delete operation
	if a:type == 'line'
		"dj dG dgg Line deletion mode
		silent execute "normal! '[V']d"
	else
    	execute 'normal! `[v`]d'
    	" Call the post-processing function
		call oracle_tui#AlignColumnReal() 
	endif


    " Restore the original operatorfunc
    let &operatorfunc = s:old_opfunc
endfunction

let s:prompt_flag = 0
let s:cur_field = 0
function! oracle_tui#ShowPrompt()
    let current_line = getline('.')
    let cursor_col = col('.') - 1
    
    " Find the field where the cursor is located
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
    " Get the file modification time
    let current_mtime = getftime(expand('%'))
    if !exists('b:last_mtime')
        let b:last_mtime = current_mtime
        return
    endif
    
    " If the file has been modified
    if current_mtime > b:last_mtime
        echohl WarningMsg 
        echo "sql is running..."
        echohl None
        
        " Optional: Auto-load
        silent edit!
        
        " Update the timestamp of the record
        let b:last_mtime = current_mtime
    endif
endfunction

function! oracle_tui#GotoVirtCol(line, vcol)
    call cursor(a:line, 0)
    execute "normal " . a:vcol . "|"
endfunction

"Define a function: Jump to the next field
function! oracle_tui#JumpToNextField()
    " Get the current line number
    let l:current_line = line('.')
    "let l:current_col = col('.')
    let l:current_col = virtcol('.')
    
    " Get the content of the second line (separator line)
    let l:separator_line = getline(3)
    if l:separator_line !~ '---'
        echo "The second line is not a valid separator"
        return
    endif
    
    " Find all field boundaries (locate the starting position of each '---')
    let l:boundaries = []
    let l:pos = 1
    let l:sep_len = strlen(l:separator_line)
    
    while l:pos <= l:sep_len
        " Check whether the current position is the start of '---'
        if l:separator_line[l:pos-1] == '-'
            " If it is the starting position of '---', record the boundary
            call add(l:boundaries, l:pos)
            " Skip consecutive '-'
            while l:pos <= l:sep_len && l:separator_line[l:pos-1] == '-'
                let l:pos += 1
            endwhile
        else
            let l:pos += 1
        endif
    endwhile
    
    " If the current line is not the last line, find the next field
    let l:next_boundary = 0
    for l:boundary in l:boundaries
        if l:boundary > l:current_col
            let l:next_boundary = l:boundary
            break
        endif
    endfor
    
    " If the next field position is found, jump there.
    if l:next_boundary > 0
        "call cursor(l:current_line, l:next_boundary)
		call oracle_tui#GotoVirtCol(l:current_line, l:next_boundary)
    else
        " If there is no next field on the current line, jump to the first field of the next line.
        if l:current_line < line('$')
			if getline(l:current_line + 1) == ''
				call oracle_tui#ShowErr("Go to end of file")
				return
			endif
            "call cursor(l:current_line + 1, l:boundaries[0])
			call oracle_tui#GotoVirtCol(l:current_line + 1, l:boundaries[0])
        else
            " If it is the last line, jump back to the first field of the first line.
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

" Define a function: Jump to the previous field.
function! oracle_tui#JumpToPrevField()
    " Get the current line number
    let l:current_line = line('.')
    let l:real_col = col('.')

	let l:current_char = oracle_tui#GetCurrentChar()
    let l:current_col = virtcol('.')
	if  strwidth(l:current_char) > 1
    	let l:current_col = l:current_col - 1
	endif

	if l:real_col == 1 && l:current_line <= 4
		call oracle_tui#ShowErr("Reached the beginning of the file\n")
		return
	endif
    
    " Get the content of the second line (separator line)
    let l:separator_line = getline(3)
    if l:separator_line !~ '---'
        echo "The second line is not a valid separator"
        return
    endif
    
    " Find all field boundaries.
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
    
    " Find the position of the previous field.
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
    
    " If the previous field position is found, jump there.
    "if l:prev_boundary > 0
	if l:real_col > 1
        call oracle_tui#GotoVirtCol(l:current_line, l:prev_boundary)
    else
        " If there is no previous field on the current line, jump to the last field of the previous line.
        if l:current_line > 4
            call oracle_tui#GotoVirtCol(l:current_line - 1, l:boundaries[-1])
        endif
    endif
endfunction

function! oracle_tui#DBViewHelp()
	echo "                                                                     "
	echo "+--------------------------------------------------------------------+"
    echo "|                       Key Instructions                             |"
	echo "| [ : Move Left          { : Fast Move Left                          |"
	echo "| ] : Move Right         } : Fast Move Right                         |"
	echo "| j : Move Down          J : Fast Move Down                          |"
	echo "| k : Move Up            K : Fast Move Up                            |"
	echo "| F3 : Freeze/Unfreeze the title bar                                 |"
	echo "| TAB : Jump to next field  Ctrl+t : Jump to previous field          |"
	echo "| F11 : Show current SQL statement                                   |"
	echo "| wv : Split window vertically                                       |"
	echo "| - : Decrease window width  = : Increase window width               |"
	echo "| Ctrl+↑ : Sort by current column asc                                |" 
	echo "| Ctrl+↓ : Sort by current column desc                               |"
	echo "| Ctrl+→ : Jump to right window         Ctrl+← : Jump to left window |"
	echo "| :Crtsql: Generate SQL based on current data file                   |"
	echo "| :Filter /match_str: Filter the current column by condition         |"
	echo "| Ctrl+x : shorten column length                                     |"
	echo "| \\x : Cut the current column                                        |"
	echo "| \\p : Paste the cut column after the current column                 |"
	echo "| Ctrl+\\ : Sum numbers in the selected column                        |"
	echo "| F1 : Show Help                                                     |"
	echo "+--------------------------------------------------------------------+"
	echo "                                                                               "

endfun

function! oracle_tui#DBModifyHelp()
	echo "+-----------------------------------------------------------------------+"
    echo "|                       Key Instructions                                |"
	if v:version >= 800
		echo "| [ : Move Left          { : Fast Move Left                             |"
		echo "| ] : Move Right         } : Fast Move Right                            |"
	endif
	echo "| j : Move Down          J : Fast Move Down                             |"
	echo "| k : Move Up            K : Fast Move Up                               |"
    echo "| F12: Submit modifications (does not commit the transaction)           |"
    echo "| o : Add new row below current line (Normal mode)                      |"
    echo "| O : Add new row above current line (Normal mode)                      |"
    echo "| TAB : Jump to next column(Insert or Normal mode)                      |"
    echo "| Ctrl+t : Jump to previous column(Insert or Normal mode)               |"
	echo "| Ctrl+→ : Jump to right window      Ctrl+← : Jump to left window       |"
    echo "| Ctrl+a : Open a window to modify the current column                   |"
    echo "| F3 : Freeze/Unfreeze the title bar                                    |"
    echo "| Ctrl+n: Toggle display of null characters                             |"
    echo "| Ctrl+@: Toggle display of diff highlighting                           |"
    echo "| - (Minus): Decrease current window width                              |"
    echo "| = (Equals): Increase current window width                             |"
	if v:version >= 800
    	echo "| wv: Split window vertically                                           |"
	endif
    echo "| F1: Show Help                                                         |"
    echo "|                      Created by Zang Jianwei                          |"
	echo "+-----------------------------------------------------------------------+"

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

	"- Decrease the window width.
	nnoremap <silent> <buffer> - <
	"_ Increase the window width.
	nnoremap <silent> <buffer> = >
	
	"= Decrease the window height.
	"nnoremap <silent> <buffer> _ -  
	"+  Increase the window height.
	"nnoremap <silent> <buffer> + +

	noremap <silent> <buffer> [ zh
	noremap <silent> <buffer> ] zl
	noremap <silent> <buffer> { zH
	noremap <silent> <buffer> } zL

	noremap <silent> <buffer> <C-W>k <Nop>
	
	"Split the window horizontally and display column names.
	"nnoremap <silent> <buffer>  wh :WH<CR>
	"Split the window vertically.
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
	
	"<F6> Sort the current column.
	"nnoremap <silent> <buffer> <C-N> :Sort<CR>

	"<F3> Toggle the display of the fixed header bar.
	nnoremap <buffer> <silent>  OR :call oracle_tui#ShowViewTitle()<CR>
	
	"<F11>
	"nmap [23~ :ShowSql<CR>
	nnoremap <silent> <buffer> <expr> [23~ expand("%") =~# ".txt.new$" ? '' : ':ShowSql'
	
	"let mapleader = "|"
	"Sort by number.
	"nnoremap <silent> <buffer> \1 :ColSort 1<CR>
	
	"Sort by character (it seems that as long as Right-align is applied, numbers can also be sorted correctly).
	"nnoremap <silent> <buffer> \2 :ColSort 2<CR>
	
	"Generate SQL statement.
	"nnoremap <silent> <buffer> \sql :Crtsql<CR>

	cnoremap <silent> <expr> <CR> oracle_tui#ViewCommandLine()

	" Map the TAB key to the function of jumping to the next field.
	nnoremap <silent> <buffer> <Tab> :call oracle_tui#JumpToNextField()<CR>
	"inoremap <Tab> <C-o>:call JumpToNextField()<CR>

	" Map Shift+Tab to the function of jumping to the previous field.
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
	set diffopt-=closeoff
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

	"- Decrease the window width.
	nnoremap <silent> <buffer> - <
	"_ Increase the window width.
	nnoremap <silent> <buffer> = >

	nnoremap <silent> <C-Left> h
	nnoremap <silent> <C-Right> l
	
	"= Decrease the window height.
	"nnoremap <silent> <buffer> _ -  
	"+  Increase the window height.
	"nnoremap <silent> <buffer> + +

	"noremap <silent> <buffer> 9 zh
	"7.4 version has a bug
	"When editing a UTF-8 file and calling 
	":syn match Substitute /@/ conceal cchar=|, 
	"moving the screen to the right such 
	"that a separator appears causes Vim to become unresponsive, 
	"and the Vim process's CPU usage spikes to 100%.
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
	
	"Split the window horizontally and display column names.
	"nnoremap <silent> <buffer>  wh :HorSplitHeader<CR>
	"Split the window vertically.
	"map wh :WH<CR>
	if v:version >= 800
		"In version 7.4, moving within vertically split windows 
		"causes Vim CPU usage to reach 100%
		nnoremap <silent> <buffer> wv :call oracle_tui#UpdateVerSplit()<CR>
	endif
	"<F1>
	"map OP :Help<CR>
	nnoremap <silent> <buffer>  OP :DBModifyHelp<CR>

	"<F3> Freeze/Unfreeze the title bar
	nnoremap <buffer> <silent>  OR :call oracle_tui#ShowUpdateTitle()<CR>

	"Ctrl+n Toggle the display of null characters.
	nnoremap <buffer> <silent>  <C-N> :call oracle_tui#ShowNullChar()<CR>

	"Ctrl+@ Toggle the display of comparison differences.
	nnoremap <buffer> <silent>  <C-@> :call oracle_tui#ShowDiff()<CR>

	"<F9> Align all columns.
	"nnoremap <buffer> <silent>  [20~ :AlignColumn<CR>

	"<F12>
	"nmap [24~ :Update<CR>
	nnoremap <silent> <buffer>  [24~ :Update<CR>

	inoremap <buffer> <silent> <Esc> <Esc>:call oracle_tui#AlignColumnReal()<CR>

	"noremap x must be defined before vnoremap x, otherwise vnoremap x will not take effect.
	"nnoremap <silent> <buffer> <expr> x or(line('.')==1,getline('.')[col('.')-1] == '') ? '' : 'x:call oracle_tui#AlignColumnReal()<CR>'
	nnoremap <silent> <buffer> <expr> x or(line('.')==1,getline('.')[col('.')-1] == '') ? '' : 'x:call oracle_tui#Process_x()<CR>'
	nnoremap <silent> <buffer> <expr> X or(line('.')==1,getline('.')[col('.')-2] == '') ? '' : 'X:call oracle_tui#AlignColumnReal()<CR>'

	" Set the operator function and trigger custom deletion.
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
	"In Vim 8.2, there is a feature called bracketed paste, 
	"which adds special characters (containing Esc) on both sides of 
	"the pasted content. When you have mapped the Esc key in insert mode 
	"(for example, using inoremap <Esc>), these special characters can 
	"interfere with the normal operation of the Esc key mapping. 
	"The solution is to set t_BE to empty, 
	"which disables adding those special characters around pasted content.
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
		au VimEnter <buffer> echo "[/{ Move left [/} right j/J down k/K up F1 for help"
		au VimEnter <buffer> setlocal statusline=%{&fileencoding}\ %=%l/%L\ %c-%v\ %p%%
		"After executing :e, the cursor jumps to the first line. 
		"Use the following method to solve this problem.
		autocmd BufReadPost <buffer> call feedkeys("lh", 'n')
	augroup END
endfun

function! oracle_tui#SetAutocmdUpdate()
	augroup DBUpdate
		autocmd!
		"autocmd BufUnload * call oracle_tui#CloseAllBuffs()
		"Executing :e will trigger the BufUnload event
		"autocmd BufUnload  <buffer> call oracle_tui#CloseAllBuffs()
		"au VimEnter <buffer> call oracle_tui#ShowUpdateTitle()
		"autocmd BufEnter *.new call oracle_tui#ProtectFirstLine()

		au BufNewFile,BufRead,BufEnter,VimEnter  <buffer> :call oracle_tui#Hid()
		"au BufNewFile,BufRead,BufEnter,VimEnter  <buffer> :call ShowDiff()

		if v:version >= 800
			au VimEnter <buffer> echo "[/{ Move left [/} right j/J down k/K up F1 for help"
		else
			au VimEnter <buffer> echo "F1 for help"
		endif
		au VimEnter <buffer> setlocal statusline=%{&fileencoding}\ %=%l/%L\ %c-%v\ %p%%

		autocmd BufNewFile,BufRead,BufEnter,VimEnter <buffer> call oracle_tui#ReadColumn()
		autocmd BufNewFile,BufRead,BufEnter,VimEnter <buffer> call oracle_tui#ReShowNullChar() 
		"autocmd vimLeave *.new call ClearColumnList()

		" Use CursorMoved to automatically adjust the cursor position.
		autocmd CursorMoved <buffer> call oracle_tui#CursorMovedForUpdate()

		autocmd CursorHold * call oracle_tui#ShowPrompt()
		setlocal updatetime=500
		setlocal ttimeoutlen=50
	augroup END
endfun

let &cpo = s:save_cpo
