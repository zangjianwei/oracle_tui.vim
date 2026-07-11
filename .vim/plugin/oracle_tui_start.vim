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

if exists("loaded_oracle_tui")
	finish
endif
let loaded_oracle_tui = 1

"禁止光标位置恢复
"set viminfo='0

"下面这行是为了加载自己的crtdb.txt用，正式提供时要删除
if getfsize($HOME."/oracle_tui/crtdb.txt") > 0
	let s:mydblist=1
else
	let s:mydblist=0
endif

function! oracle_tui_start#ConnectDB(...)
	"set encoding=utf-8
	"redraw!
	if &enc != "utf-8"
		call oracle_tui#ShowErr("The 'encoding' setting is not UTF-8")
		return
	endif

	"高亮显示(如果terminfo库有问题，则不能语法高亮)
	"if &t_Co == 0 || empty(&t_Sf) || empty(&t_Sb)
	"	set t_Co=8
	"	set t_Sf=[3%p1%dm
	"	set t_Sb=[4%p1%dm
	"endif

	let pid=getpid()

	let dbdir=$HOME."/.dbtmp"
	if !isdirectory(dbdir)
		call mkdir(dbdir, 'p')
	endif

	"db_disconnect.sh要放在这，否则连接数据库失败则不能删除临时文件
	autocmd vimLeave * sil execute "! db_disconnect.sh ".getpid()

	let input_user_flag = 0
	if a:0 == 1
		if a:1 != "-u" || a:1 == "-h"
			call oracle_tui#ShowErr('Usage:Connect [-u]')
			return
		else
			let input_user_flag = 1
		endif
	endif

	if exists('s:username') 
		unlet s:username
	endif

	if exists('s:password') 
		unlet s:password
	endif

	if input_user_flag == 1
		let s:username = input('Database username:')
		if s:username == ''
			redraw!
			call oracle_tui#ShowErr('没有输入用户名')
			return
		endif

		redraw!
		let s:password = inputsecret('Database username:'.s:username."\nDatabase password:")
		if s:password == ''
			redraw!
			call oracle_tui#ShowErr('没有输入口令')
			return
		endif
	else
		if $DBUSER == ''
			let s:username = input('Database username:')
			if s:username == ''
				redraw!
				call oracle_tui#ShowErr('没有输入用户名')
				return 
			endif

			redraw!
			let s:password = inputsecret('Database username:'.s:username."\nDatabase password:")
			if s:password == ''
				redraw!
				call oracle_tui#ShowErr('没有输入口令')
				return 
			endif
		else
			if $DBPASS == ''
				let s:username = input('Database username:', $DBUSER)
				if s:username == ''
					redraw!
					call oracle_tui#ShowErr('没有输入用户名')
					return 
				endif
				
				redraw!
				let s:password = inputsecret('Database username:'.s:username."\nDatabase password:")
				if s:password == ''
					redraw!
					call oracle_tui#ShowErr('没有输入口令')
					return 
				endif
			endif
		endif
	endif

	if exists('s:username') && exists('s:password')
		let cmd="db_connect.sh ".pid." ".s:username. " ".s:password
	else
		let cmd="db_connect.sh ".pid
	endif


	"sil execute "! ".cmd
	let output = system(cmd)

	let status = shell_error
	if status != 0
		redraw!
		"echo "连接失败!"
		"echo output
		call oracle_tui#ShowErr(output)
		return
	endif

	let w:main_window_flag = 1

	"set paste 会使imap映射失效
	set nopaste

	if exists('s:username') && exists('s:password')
		call oracle_tui#SetUsername(s:username)
		call oracle_tui#SetPassword(s:password)
	endif

	setlocal nohlsearch
	command! Line call oracle_tui#Line()
	command! UnLine call oracle_tui#UnLine()
	"command! -nargs=? -range Exe <line1>,<line2> call oracle_tui#ExeSql(<f-args>)
	command! -range Plan <line1>,<line2> call oracle_tui#Plan()
	command! -nargs=*  Tablist  call oracle_tui#Tablist(<f-args>)
	command! GetWord call oracle_tui#GetWord()
	command! ShowTab call oracle_tui#ShowTab()
	command! DescObj call oracle_tui#DescObj()
	command! GrepTab call oracle_tui#GrepTab()
	command! Seelock call oracle_tui#Seelock()
	command! Tabspace call oracle_tui#Tabspace()
	command! Tabused call oracle_tui#Tabused()
	command! Nowsql call oracle_tui#Nowsql()
	command! -nargs=* Unlock call oracle_tui#Unlock(<f-args>)
	command! IfCommit call oracle_tui#IfCommit()
	command! Fsql call oracle_tui#Fsql()
	command! -nargs=1 RollCommit call oracle_tui#RollCommit(<f-args>)
	command! ListObj call oracle_tui#ListObj()
	"command! ConvWork call oracle_tui#ConvWork()
	"command! ShowMode call oracle_tui#ShowMode()
	command! CheckNoCommit call oracle_tui#CheckNoCommit()
	command! DBCliHelp call oracle_tui#DBCliHelp()
	command! -nargs=* ShowErr call oracle_tui#ShowErr(<f-args>)

	if s:mydblist == 1 
		execute "badd ".$HOME."/oracle_tui/crtdb.txt"
		execute "badd ".$HOME."/oracle_tui/kjdb.txt"
	else
		if exists('s:username') && exists('s:password')
		  	let result = system("db_list_table.sh ".s:username." ".s:password." ".pid)
		else
			let result = system("db_list_table.sh ".pid)
		endif
		execute "badd ".dbdir."/.dbobj.".pid
	endif

	"- 减小窗口宽度
	nnoremap - <
	"_ 增加窗口宽度
	nnoremap = >
	
	"= 减小窗口高度
	nnoremap _ -  
	"+  增加窗口高度
	nnoremap + +
	
	nnoremap <silent> <C-Up> k
	nnoremap <silent> <C-Down> j
	nnoremap <silent> <C-Left> h
	nnoremap <silent> <C-Right> l
	
	"map J 10j
	"map K 10k
	
	"<F1> 显示帮助
	"nmap <silent> OP :Help<CR>
	"nnoremap <expr>  OP expand("%") == "backlist" ? ':HelpBackList<CR>' : ':DBCliHelp<CR>'
	nnoremap  OP :DBCliHelp<CR>
	
	"<F2> 回滚事务
	nnoremap <silent>  OQ :RollCommit 0<CR>
	
	"<F6> 提交事务
	nnoremap <silent>  [17~ :RollCommit 1<CR>
	
	"<F3> 查看锁
	"nnoremap <silent>  OR :Seelock<CR>
	
	"<F4> 查看是否有未提交事务
	nnoremap <silent>  OS :IfCommit<CR>
	
	"<F5> 查看执行计划
	noremap <silent>  [15~ :Plan<CR>
	
	"<F7>
	nnoremap <silent>  [18~ :ListObj<CR>
	
	"<F8> 执行sql
	"map <silent> [19~ :Exe<CR>
	nnoremap <silent>  [19~ :call oracle_tui#ExeSql('n')<CR>
	vnoremap <silent>  [19~ :<C-U>call oracle_tui#ExeSql('v')<CR>
	
	"<F9> 显示crtdb.txt中表定义
	nnoremap <silent>  [20~ :ShowTab<CR>
	
	"<F10> 显示创建数据库对象语句
	nnoremap <silent>  [21~ :DescObj<CR>

	"<F11> 查看表空间
	"nnoremap <silent>  [23~ :Tabspace<CR>

	"<F12> 查看正在运行的sql
	"nnoremap <silent>  [24~ :Nowsql<CR>
	
	"捕获当前光标位置所在单词，将其插入前一个窗口光标所在位置,同时关闭当前窗口
	"map  :call GetWord()a
	"nnoremap <silent>  :GetWord<CR>
	
	"搜索光标所在的字符串对应表名
	"nnoremap <silent>  <CR> :GrepTab<CR>
	inoremap <silent>  <C-K> :GrepTab<CR>
	nnoremap <silent>  <C-K> :GrepTab<CR>

	"cnoremap  <expr> q <SID>HandleQuit()
	"cnoremap  <expr> x <SID>HandleQuit_x()

	cnoremap <silent>  <expr> <CR> oracle_tui#CheckMainCommand()

	"let mapleader = ","
	"nnoremap <silent> <Leader>s :ShowMode<CR>
	
	"autocmd VimLeavePre * call oracle_tui#CheckNoCommit()
	"autocmd vimLeave * sil execute "! db_disconnect.sh ".getpid()
	"autocmd BufReadPost *
	"			\ if line("'\"") > 0 && line("'\"") <= line("$") |
	"			\   exe "normal! g`\"" |
	"			\ endif

	"let s:last_win_nr = 1
	"augroup RememberLastWindow
	"	autocmd!
	"	autocmd WinEnter * let s:last_win_nr = winnr()
	"augroup END

	cnoreabbrev <silent> <expr> only (getcmdtype()==':') ? 'sil only<bar>sil tabonly<bar>' : 'only'
	redraw!
	call oracle_tui#ShowErr("欢迎进入ORACLE TUI 数据库客户端,按F1显示帮助")
endfun

command! -nargs=? Connect call oracle_tui_start#ConnectDB(<f-args>)
"command! VerSplit call oracle_tui#VerSplit()
"command! -range Sum <line1>,<line2> call oracle_tui#Sum()

let &cpo = s:save_cpo
