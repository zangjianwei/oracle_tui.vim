# oracle_tui.vim

[English](https://github.com/zangjianwei/oracle_tui.vim) | [中文](https://github.com/zangjianwei/oracle_tui.vim/tree/zh-CN)

# 简介

一款功能完备、原生运行于 UNIX/Linux Vim 环境中的 Oracle 客户端，提供媲美 GUI 工具的用户体验。基于 SQL*Plus 执行 SQL，支持电子表格风格的数据操作——像 Excel 一样编辑数据，修改后自动对齐。此外还支持执行计划分析、表结构查看、数据库对象 DDL 提取、事务控制、LOB 字段编辑、智能自动补全（支持中间字符串匹配）以及标题行固定等功能。

![演示动图](https://raw.githubusercontent.com/zangjianwei/oracle_tui.vim/master/images/oracle_tui_en.gif)

# 功能特性

- **快速连接**：支持通过环境变量自动登录，一条命令即可连接数据库。
- **电子表格风格编辑**：在 Vim 中像 Excel 一样编辑数据（`SELECT ... FOR UPDATE`）。
  - 隐藏 ROWID，防止误修改。
  - 支持 CLOB/BLOB 字段的文件式编辑。
  - 自动对齐：数字类型右对齐，日期类型自动格式化。
- **键盘驱动的工作流**：
  - F8：执行 SQL
  - F12：提交数据修改
  - F2 / F6：回滚 / 提交事务
- **安全机制**：退出 Vim 时如有未提交事务，强制报错并阻止退出。
- **智能补全**：支持表名自动补全（支持非前缀匹配）。
- **多语句支持**：支持 PL/SQL 块执行，结果分别展示。
- **三种不同的窗口模式**：
  - **SQL 执行窗口**：进入 Vim 时的默认窗口。
  - **查询窗口**：执行单条 SELECT 语句时打开。
    - 列标题完整显示，突破 sqlplus 截断限制。
    - 支持标题行固定。
  - **数据修改窗口**：执行 `SELECT ... FOR UPDATE` 时打开。
    - 电子表格风格编辑，标题行固定。
    - 插入/删除/修改/替换时自动对齐（数字右对齐）。
    - 智能识别 VARCHAR2 字段的尾部空格。
    - 为 CLOB/BLOB 字段生成临时文件，在字段上按 Ctrl+A 打开编辑窗口。
    - 替换操作保留标题行和 CLOB/BLOB 文件名。
    - 光标移至 DATE/TIMESTAMP 字段时自动提示输入格式。
    - 光标移至 CLOB/BLOB 字段时自动提示按 Ctrl+A 编辑。

# 安装

## 依赖

- Linux/Unix 环境
- Oracle Instant Client（必须配置好 sqlplus）
- Vim 7.4+（推荐 Vim 8.2 或以上版本，Vim 7.4 存在部分功能限制）

## 安装步骤

1. 将 `oracle_tui.tar` 放在安装用户的 `$HOME` 目录下。
2. 解压文件：`tar xvf oracle_tui.tar`。
3. 在 profile 文件中添加以下环境变量：
export PATH=
P
A
T
H
:
PATH:HOME/oracle_tui:.

text
4. 检查 `NLS_LANG` 和 `LC_CTYPE` 环境变量是否设置为 UTF-8。如果没有，在 profile 文件中添加以下环境变量（请根据你的 [语言]_[地区] 设置选择）：
export TUI_NLS_LANG="AMERICAN_AMERICA.AL32UTF8"
export TUI_LC_CTYPE=en_US.UTF-8

text
5. 设置文件编码为 UTF-8。在 `~/.vimrc` 或你自己的 `.vimrc` 文件中添加以下配置：
set encoding=utf-8
set fileencodings=ucs-bom,utf-8,gb18030,gbk,gb2312,cp936,latin1
set termencoding=utf-8

text
6. 在 profile 文件中添加 `DBUSER` 和 `DBPASS` 环境变量（可选）：
export DBUSER=user
export DBPASS=pass

text
如果设置了这些变量，工具将自动使用它们登录；否则会提示手动输入用户名和密码。
7. 在 profile 文件中设置别名（可选）：
alias vidb='vim -c "call oracle_tui_start#ConnectDB()"'

text
或
alias vidb='vim -u /path/to/your/.vimrc -c "call oracle_tui_start#ConnectDB()"'

text
设置别名后，输入 `vidb` 即可自动连接数据库。
8. 使 profile 生效（例如：`. ~/.profile`）。

# 启动步骤

1. 将终端编码设置为 UTF-8。
2. 方法一：
打开 Vim 并输入 `:Connect`。如果设置了 `DBUSER` 和 `DBPASS` 环境变量，工具将使用它们登录；否则会提示输入用户名和密码。也可以输入 `:Connect -u` 强制弹出登录提示手动输入。
3. 方法二：
使用别名自动启动，输入 `vidb <文件名>`。

# 快捷键说明

## SQL 执行窗口

| 快捷键         | 功能                                                             |
|:---------------|:-----------------------------------------------------------------|
| F1             | 显示帮助                                                         |
| F8             | 执行 SQL（可视模式下执行选中内容，普通模式下执行当前行）           |
| Ctrl+C         | 中断当前操作                                                     |
| F2 / F6        | 回滚 / 提交事务                                                  |
| F4             | 检查未提交事务                                                   |
| F5             | 查看 SQL 执行计划                                                |
| F7             | 列出数据库对象（弹出窗口中 F9 和 F10 可用）                      |
| F9             | 显示光标所在表的表结构描述                                       |
| F10            | 显示光标所在数据库对象的 DDL 语句                                |
| - / =          | 缩小 / 增加窗口宽度                                              |
| Shift + - / =  | 缩小 / 增加窗口高度                                              |
| Ctrl+↑         | 跳转到上方窗口                                                   |
| Ctrl+↓         | 跳转到下方窗口                                                   |
| Ctrl+→         | 跳转到右侧窗口                                                   |
| Ctrl+←         | 跳转到左侧窗口                                                   |
| Ctrl+n         | 对象名自动补全（仅前缀匹配，插入模式）                           |
| Ctrl+k         | 表名自动补全（支持非前缀匹配，插入或普通模式）                   |
| gt             | 切换标签页                                                       |
| :Tablist       | 显示表名及注释                                                   |
| :Seelock       | 查看锁                                                           |
| :Unlock        | 解锁                                                             |
| :Tabused       | 查看表空间使用情况                                               |
| :Tabspace      | 查看表空间使用情况                                               |
| :Nowsql        | 查看当前正在运行的 SQL                                           |

## 查询窗口

| 快捷键     | 功能                                     |
|:-----------|:-----------------------------------------|
| [ / ]      | 左移 / 右移                              |
| { / }      | 快速左移 / 快速右移                      |
| j / k      | 下移 / 上移                              |
| J / K      | 快速下移 / 快速上移                      |
| /          | 搜索                                     |
| -          | 缩小窗口宽度                             |
| +          | 增加窗口宽度                             |
| Ctrl+→     | 跳转到右侧窗口                           |
| Ctrl+←     | 跳转到左侧窗口                           |
| Ctrl+↑     | 按当前列升序排序                         |
| Ctrl+↓     | 按当前列降序排序                         |
| F3         | 固定 / 取消固定标题行                    |
| wv         | 垂直分割窗口                             |
| TAB        | 跳转到下一个字段                         |
| Ctrl+t     | 跳转到上一个字段                         |
| F11        | 显示当前 SQL 语句                        |
| Crtsql     | 根据当前数据文件生成 SQL                 |
| Ctrl+X     | 缩短列长度                               |
| \x         | 剪切当前列                               |
| \p         | 将剪切列粘贴到当前列之后                 |
| Ctrl+\     | 对选中列中的数字求和                     |
| F1         | 显示帮助                                 |

## 数据修改窗口

| 快捷键     | 功能                                                             |
|:-----------|:-----------------------------------------------------------------|
| [ / ]      | 左移 / 右移                                                      |
| { / }      | 快速左移 / 快速右移                                              |
| j / k      | 下移 / 上移                                                      |
| J / K      | 快速下移 / 快速上移                                              |
| /          | 搜索                                                             |
| F12        | 提交表数据修改（不提交事务）                                     |
| o          | 在当前行下方新增一行（普通模式）                                 |
| O          | 在当前行上方新增一行（普通模式）                                 |
| Ctrl+→     | 跳转到右侧窗口                                                   |
| Ctrl+←     | 跳转到左侧窗口                                                   |
| Ctrl+T     | 跳转到上一列（插入或普通模式）                                   |
| TAB        | 跳转到下一列（插入或普通模式）                                   |
| Ctrl+A     | 打开窗口编辑当前列（用于 CLOB/BLOB）                             |
| F3         | 固定 / 取消固定标题行                                            |
| wv         | 垂直分割窗口                                                     |
| Ctrl+n     | 切换显示空字符                                                   |
| Ctrl+@     | 切换显示差异高亮                                                 |
| -          | 缩小当前窗口宽度                                                 |
| +          | 增加当前窗口宽度                                                 |
| F1         | 显示帮助                                                         |

# ⚠️ 限制

- 数据修改窗口不支持修改包含 LONG 或 LONG RAW 类型的字段。
- AIX 系统上 Vim 9 存在 list 处理 bug，因此 AIX 上不能使用 Vim 9。

## 作者

**zangjianwei**

- GitHub: [@zangjianwei](https://github.com/zangjianwei)
- 邮箱: [zangjianwei35@gmail.com](mailto:zangjianwei35@gmail.com)
