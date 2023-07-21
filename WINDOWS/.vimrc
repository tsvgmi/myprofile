" == START OF VUNDLE ===
set nocompatible              " be iMproved, required
filetype off                  " required

" ========================================================================
" This file usually is named "$HOME/vimrc".
" Purpose: setup file for the editor "vim"
" Structure of this file:
" Lines starting with an inverted comma (") are comments.
" Some mappings are commented out.  Remove the comment to enable them. (duh)
"
" The first line contains "version 4.0" to allow a check for syntax.
" Versions of VIM other than of version 4 will give a warning.
" Version 3 and older will complain - and that's the intended effect:
" Give a warning so the user knows that there is something odd about vimrc.
" 
" There are three kinds of things which are defined in this file:
" Mapping ("map"), settings ("set"), and abbreviations ("ab").
"   Settings affect the behaviour of commands.
"   Mappings maps a string to a command.
"   Abbreviations define words which are replaced after they are typed in.
" ========================================================================
" Availability:
" This file is available as
" <URL:http://www.math.fu-berlin.de/~guckes/setup/vimrc>
" written by
" <a href="http://www.math.fu-berlin.de/~guckes/"> Sven Guckes          </a>
" <a href="mailto:guckes@math.fu-berlin.de"> (guckes@math.fu-berlin.de) </a>
"
" Please send your comments via email!
" Last update: Sun Jun 30 23:16:20 MET DST 1996
" ========================================================================
" Language:
" VIM allows to give special characters by writing them in a special notation.
" The notation encloses decriptive words in angle brackets (<>).
" Read all about it with ":help <>".
" The characters you will most often are:
" <C-M> for control-m
" <C-V> for control-v which quotes the following character
" <ESC> for the escape character.
" ========================================================================
" External programs used in some commands:
" egrep, date, sed; par
" ========================================================================
"
"set   shell=/bin/bash
set   ttyfast
" ========================================================================
"
" Command line (colon mode) mappings
" valid names are:  <Up> <Down> <Left> <Right> <Home> <End> 
" <S-Left> <S-Right> <S-Up> <PageUp> <S-Down> <PageDown>  <LeftMouse> 
"
" Command line - tcsh style command line editing
"
cnoremap <C-A> <Home>
cnoremap <C-F> <Right>
cnoremap <C-B> <Left>
cnoremap <ESC>b <S-Left>
cnoremap <ESC>f <S-Right>
cnoremap <ESC><C-H> <C-W>

" Map to emtux split sequence.  This won't work if vim is running under emtmux
map <C-E>- <C-W>s
map <C-E>\| <C-W>v
map <C-E>d <C-W>c

" Map to iterm split sequence.  This won't work if vim is running under iterm
map <D-D> <C-W>s
map <D-d> <C-W>v

nnoremap <Leader>t :TlistToggle<CR>
map! <Leader>f <Plug>ShowFunc

"
" DOS keyboard mapping for cursor keys
"
imap <ESC>OA  <Up>
imap <ESC>OD  <Left>
imap <ESC>OC  <Right>
imap <ESC>OB  <Down>
imap <ESC>[5~ <PageUp>
imap <ESC>[6~ <PageDown>
"
"------------------------------------ VIM - Editing and updating the vimrc:
"
"   ,v = vimrc editing (edit this file)
"   ,u = "update" by reading this file
map ,vv :e ~/.vimrc<CR>
map ,vs :source ~/.vimrc<CR>
"
"
" Enable editing of gzipped files.  This comes straight from the vim
" distribution and it served me well.
"   uncompress them after reading
"   compress them before writing, undone after writing
"   binary mode is needed when writing gzipped files
autocmd BufRead *.gz set bin|%!gunzip
autocmd BufRead *.gz set nobin
autocmd BufWritePre *.gz %!gzip
autocmd BufWritePre *.gz set bin
autocmd BufWritePost *.gz undo|set nobin
autocmd FileReadPost *.gz set bin|'[,']!gunzip
autocmd FileReadPost set nobin

" Disable slow process in network volume
autocmd BufReadPre //* :NoMatchParen
"

"--------------------------------------------- So it behaves like crisp ---
"<F7>	Begin of macro (must use 'q' to terminate macro)
"<F8>	Playback of macro
"<F5>	Search
"<F6>	Replace
"<A-N>	Next buffer
"<A-P>	Previous buffer
"<A-B>	List buffers
"<A-W>	Write file/region
"<A-D>	Delete line
"<A-U>	Undo
"<A-X>	Quit
"<A-E>	Edit file
"<A-R>	Read file
"<A-Y>	Yank region
"--------------------------------------------------------------------------
map 	<F7> 	qz
map 	<F8> 	@z
imap 	<F7> 	<C-O>qz
imap 	<F8> 	<C-O>@z
map 	<F5>	/
imap 	<F5>	<C-O>/
map 	<F6>	:s/
imap 	<F6>	<C-O>:s/
imap	<S-F5>	<C-O>n
map 	î 	:bn
imap 	î 	<C-O>:bn
map 	ð 	:bp
imap 	ð 	<C-O>:bp
"map 	â 	:buffers
map 	<M-b> 	:buffers<CR>
map 	b 	:buffers<CR>
map 	<M-t> 	:tj /
map 	t 	:tj /
imap 	â 	<C-O>:buffers
map 	÷	:w
imap 	÷	<C-O>:w
map 	ë	D
imap 	ë	<C-O>D
map 	ä	dd
imap 	ä	<C-O>dd
map 	õ	u
imap 	õ	<C-O>u
map	ø	:q<CR>
imap	ø	<C-O>:q<CR>
map	å	:e 
imap	å	<C-O>:e 
map	ò	:r 
imap	ò	<C-O>:r 
map	í	v
imap	í	<C-O>v
map	ì	V
imap	ì	<C-O>V
map	ù	y
imap	ù	<C-O>y
map	<S-DOWN>	j
map	<S-UP>		k
imap	<S-DOWN>	<C-O>j
imap	<S-UP>		<C-O>k

map	<C-N>		:/^\({\\|class\\|sub\\|proc\\|func\\|main\)<CR>z.
map	<C-_>		:cs find f <C-R>=expand("<cfile>")<CR><CR>

" yank/put support in windows
map     <C-Y>           "+y
map     <C-P>           "+P

map     <M-Right>       :tabnext<CR>
map     <M-Left>        :tabprev<CR>

set wmh=0

"------------------------------------------- Quick switching of buffers ---
" Maximize and split the window
map 	 <Leader>- :only\|split<CR>
" Maximize back windows + show all buffer tabs
nmap     <Leader>0 :only\|bn\|bp<CR>
nmap     <Leader>1 :tabn 1<CR>
nmap     <Leader>2 :tabn 2<CR>
nmap     <Leader>3 :tabn 3<CR>
nmap     <Leader>4 :tabn 4<CR>
nmap     <Leader>5 :tabn 5<CR>
nmap     <Leader>6 :tabn 6<CR>
nmap     <Leader>7 :tabn 7<CR>
nmap     <Leader>8 :tabn 8<CR>
nmap     <Leader>9 :tabn 9<CR>

nmap     <D-1> :tabn 1<CR>
nmap     <D-2> :tabn 2<CR>
nmap     <D-3> :tabn 3<CR>
nmap     <D-4> :tabn 4<CR>
nmap     <D-5> :tabn 5<CR>
nmap     <D-6> :tabn 6<CR>
nmap     <D-7> :tabn 7<CR>
nmap     <D-8> :tabn 8<CR>
nmap     <D-9> :tabn 9<CR>

nmap 	<M-C>	!!~/bin/vimfilt % cbar<CR>
nmap 	c	!!~/bin/vimfilt % cbar<CR>
map	,in	ma/^}<CR>:'a,.!tclIndent<CR>
map	,fl	:g/^\(proc\\|sub\\|func\)/p

"<A-C> Indented shell comment start
"---------------------------------------------------------------------------
imap	ã	.<BS>#---  ---<BS><BS><BS>i
map	c	40A <ESC>41\|C#<Space>

"--------------------------------------------- For navigation with make ---
"Cannot map anything start with <ESC> as it will be a problem for
"macro playback if a slow <ESC> is really needed
"<F4>	Go to next error/warning
"<S-F4>	Go to previous error/warning
"------------------------------------------------------------------------- 
map  	<F4>	:cn<CR>
imap  	<F4>	<C-O>:cn<CR>
map  	<S-F4>	:cp<CR>
imap  	<F4>	<C-O>:cn<CR>

"---------------------------------------------- Remote editing support ---
":wr	Save file to remote machine
"-------------------------------------------------------------------------
cab	wr	wa\|!sshedit.rb putremote %<CR>
map	,si	:source vim.in<CR>

set ttyfast

cmap ,wr	!sshedit.rb putremote %<CR>:bd<CR>

"highlight Normal guibg=White guifg=Black
syntax on

set smartindent
set autowrite
set shiftwidth=2
set ignorecase
set smartcase
set expandtab

"set viminfo='50,\"1000,:1,n~/.vim/viminfo
set cinkeys=0{,0},:,!,o,O,e

set listchars=tab:»­,trail:­
highlight NonText guifg=#ff4444

"For code formatting
set fo=croq
set comments=:#--- 

autocmd!
autocmd BufWritePost ~/.vimrc   source ~/.vimrc

set uc=0
set autoread

if version >= 600
  set sidescrolloff=4
  set foldlevel=10
  set foldcolumn=2
  filetype plugin on
endif

command! -range AlignColumn1 <line1>,<line2>!wsl /home/tvuong/bin/winwrap vimfilt.rb ac 1
command! -range AlignColumn2 <line1>,<line2>!wsl /home/tvuong/bin/winwrap vimfilt.rb ac 2
command! -range AlignColumn3 <line1>,<line2>!wsl /home/tvuong/bin/winwrap vimfilt.rb ac 3
command! -range AlignColumn <line1>,<line2>!wsl /home/tvuong/bin/winwrap winwrap vimfilt.rb ac 
command! -range AlignEqual <line1>,<line2>!wsl /home/tvuong/bin/winwrap vimfilt.rb ae
command! -range FmtComment <line1>,<line2>!~/bin/vimfilt % fmtcmt
command! -range FmtHaml    <line1>,<line2>!~/bin/vimfilt % fmt_haml
command! -range FuncHeader <line1>,<line2>!~/bin/vimfilt % funcHeader

command! FileHeader	0r!~/bin/vimfilt % fileTemplate

" Switch directory - clean current buffers
command! -nargs=1 Sdir %bd | cd <args>

map ,fH		:FileHeader<CR>
map ,#          $50a 51\|C# 
vmap ,a1c	:AlignColumn1<CR>
vmap ,a2c	:AlignColumn2<CR>
vmap ,a3c	:AlignColumn3<CR>
vmap ,ac	:AlignColumn<CR>
vmap ,ae	:AlignEqual<CR>
vmap ,cb        !~/bin/vimfilt % cbar<CR>
vmap ,cf	:FmtComment<CR>
vmap ,hf	:FmtHaml<CR>
vmap ,fh	:FuncHeader<CR>

" Open current file in new window
map <C-N> :!gvim %<CR><CR>:bd<CR>

" Map alt-z to fold alternate
map <BS>	za
map <C-BS>	zM
map <M-BS>	zR

map <Up>   gk
map <Down> gj

function! MapBoth(keys, rhs)
  execute 'nmap' a:keys a:rhs
  execute 'imap' a:keys '<C-o>' . a:rhs
endfunction

" Tab selection mapping
call MapBoth('<M-1>', ':tabn 1<CR>')
call MapBoth('<M-2>', ':tabn 2<CR>')
call MapBoth('<M-3>', ':tabn 3<CR>')
call MapBoth('<M-4>', ':tabn 4<CR>')
call MapBoth('<M-5>', ':tabn 5<CR>')
call MapBoth('<M-6>', ':tabn 6<CR>')
call MapBoth('<M-7>', ':tabn 7<CR>')
call MapBoth('<M-8>', ':tabn 8<CR>')
call MapBoth('<M-9>', ':tabn 9<CR>')

syntax on

set mouse=a
set mousefocus

highlight Folded guibg=#444444 guifg=#888888

if $VIMCOLOR != ""
  execute "color " . $VIMCOLOR
else
  "color koehler
  "color darkblue
  "color pablo
  "color zellner
  "color evening
  color torte
  set mouse=a

  " Highlight the search pattern
  set hlsearch
  highlight Folded guibg=#444444 guifg=#888888
endif
set iskeyword=48-57,_,A-Z,a-z

set tags=tags,TAGS
set number

autocmd FileType ruby   compiler ruby
autocmd FileType go     setlocal ts=4 sw=4 expandtab! list
autocmd FileType python setlocal ts=2 sw=2 expandtab list foldmethod=indent
autocmd FileType ruby   setlocal ts=2 sw=2 expandtab list norelativenumber nocursorline re=1 foldmethod=manual

set nocompatible      " We're running Vim, not Vi!
syntax on             " Enable syntax highlighting
filetype on           " Enable filetype detection
filetype indent on    " Enable filetype-specific indenting
filetype plugin on    " Enable filetype-specific plugins

set noincsearch
set colorcolumn=82
colorscheme darkblue

let ruby_fold = 1
let ruby_foldable_groups = 'def class module for if case'
let ruby_minlines = 100

let g:is_bash = 1
let g:sh_fold_enabled = 1

hi Comment guifg=#AAFFAA

set guifont=Consolas:h9:cANSI:qDRAFT
set foldmethod=syntax
set directory^=$HOME/tmp
set backupdir^=$HOME/tmp

if has("gui_running")
  "Copy
  nnoremap <C-c> "+y  " Normal (must follow with an operator)
  xnoremap <C-c> "+y  " Visual

  "Paste
  "nnoremap <C-v> "+p  " Normal
  noremap! <C-v> <C-r>+
  inoremap <C-v> <C-r>+
endif
