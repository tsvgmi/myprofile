"source $HOME/.vim/vundle.vim

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
set   shell=/bin/bash
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

nmap 	<M-C>	!!~/bin/vimfilt.rb % cbar<CR>
nmap 	c	!!~/bin/vimfilt.rb % cbar<CR>
map	,in	ma/^}<CR>:'a,.!tclIndent<CR>
map	,fl	:g/^\(proc\\|sub\\|func\)/p

"<A-C> Indented shell comment start
"---------------------------------------------------------------------------
imap	ã	.<BS>#---  ---<BS><BS><BS>i
imap	c	.<BS>#---  ---<BS><BS><BS>i

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
set maxmemtot=10000		"Give me lots of memory

cmap ,wr	!sshedit.rb putremote %<CR>:bd<CR>

"highlight Normal guibg=White guifg=Black
syntax on

set smartindent
set autowrite
set shiftwidth=2
set ignorecase
set smartcase
set expandtab

if has('nvim')
  set shada='50,\"1000,:1,n~/.vim/shada
else
  set viminfo='50,\"1000,:1,n~/.vim/viminfo
end
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

command! -range AlignColumn1 <line1>,<line2>!~/bin/vimfilt.rb % alcol 1
command! -range AlignColumn2 <line1>,<line2>!~/bin/vimfilt.rb % alcol 2
command! -range AlignColumn3 <line1>,<line2>!~/bin/vimfilt.rb % alcol 3
command! -range AlignColumn <line1>,<line2>!~/bin/vimfilt.rb '%' alcol
command! -range AlignEqual <line1>,<line2>!~/bin/vimfilt.rb '%' ae
command! -range FmtComment <line1>,<line2>!~/bin/vimfilt.rb % fmtcmt
command! -range FmtHaml    <line1>,<line2>!~/bin/vimfilt.rb % fmt_haml
command! -range FuncHeader <line1>,<line2>!~/bin/vimfilt.rb % funcHeader

command! AddFold    	.!~/bin/vimfilt.rb % addFold
command! FileHeader	0r!~/bin/vimfilt.rb % fileTemplate

command! Bartedit      set guifont=Monaco:h14|color zellner
command! Normedit      set guifont=Monaco:h12|color koehler
command! Bigfont       set guifont=Monaco:h14
command! Normfont      set guifont=Monaco:h12

if !has('nvim')
  set guifont=Monaco:h12
end

map ,af		:AddFold<CR>
map ,fH		:FileHeader<CR>
map ,#          $40a 41\|C# 
vmap ,a1c	:AlignColumn1<CR>
vmap ,a2c	:AlignColumn2<CR>
vmap ,a3c	:AlignColumn3<CR>
vmap ,ac	:AlignColumn<CR>
vmap ,ae	:AlignEqual<CR>
vmap ,cb        !~/bin/vimfilt.rb % cbar<CR>
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

map <T-Up>   :call FontAdjust(1)<CR>
map <T-Down> :call FontAdjust(-1)<CR>

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

let g:miniBufExplMapWindowNavArrows = 1
let g:miniBufExplMapCTabSwitchWindows = 1
let g:miniBufExplUseSingleClick = 1
let g:miniBufExplModSelTarget = 1

if !has('nvim')
  set ttymouse=xterm
end
set number

" Change cursor based on insert mode
let &t_SI = "\<Esc>]50;CursorShape=1\x7"
let &t_EI = "\<Esc>]50;CursorShape=0\x7"

" 256 colors
set t_Co=256

command! -bang Svim redir @" | silent ls<bang> | redir END | echo " " |
 \ perl {
 \ my $msg=VIM::Eval('@"');
 \ my $file, $value, $bfile;
 \ my @flist, %slist;
 \ while($msg =~ m/(.*?line\s+\d+)/g) {
 \   $value = $1;
 \   $value =~ m/"([^"]+)"/;
 \   $file  = $1;
 \   next if ($file =~ /No Name/);
 \   ($bfile = $file) =~ s!^.*/_?!!;
 \   $bfile =~ tr/[A-Z]/[a-z]/;
 \   $slist{$bfile} = $file;
 \ }
 \ my $cmd = "mvim";
 \ for $bfile (sort keys %slist) {
 \   $cmd .= " $slist{$bfile}";
 \ }
 \ system($cmd);
 \ VIM::Msg("OK - $cmd");
 \ }
 \ <CR>

command! -bang Smate redir @" | silent ls<bang> | redir END | echo " " |
 \ perl {
 \ my $msg=VIM::Eval('@"');
 \ my $file, $value, $bfile;
 \ my @flist, %slist;
 \ while($msg =~ m/(.*?line\s+\d+)/g) {
 \   $value = $1;
 \   $value =~ m/"([^"]+)"/;
 \   $file  = $1;
 \   next if ($file =~ /No Name/);
 \   ($bfile = $file) =~ s!^.*/_?!!;
 \   $slist{$bfile} = $file;
 \ }
 \ my $cmd = "mate";
 \ for $bfile (sort keys %slist) {
 \   $cmd .= " $slist{$bfile}";
 \ }
 \ system($cmd);
 \ VIM::Msg("OK - $cmd");
 \ }
 \ <CR>

autocmd FileType ruby compiler ruby

set nocompatible      " We're running Vim, not Vi!
syntax on             " Enable syntax highlighting
filetype on           " Enable filetype detection
filetype indent on    " Enable filetype-specific indenting
filetype plugin on    " Enable filetype-specific plugins

let g:miniBufExplMapWindowNavVim = 1 
let g:miniBufExplMapWindowNavArrows = 1 
let g:miniBufExplMapCTabSwitchBufs = 1
let g:miniBufExplModSelTarget = 1 

" MiniBufExpl Colors
hi MBENormal               guifg=#808080 guibg=fg
hi MBEChanged              guifg=#CD5907 guibg=fg
hi MBEVisibleNormal        guifg=#5DC2D6 guibg=fg
hi MBEVisibleChanged       guifg=#F1266F guibg=fg
hi MBEVisibleActiveNormal  guifg=#A6DB29 guibg=fg
hi MBEVisibleActiveChanged guifg=#F1266F guibg=fg

let g:miniBufExplSortBy = "mru"

" Saving/restore controlspace workspace
let g:CtrlSpaceLoadLastWorkspaceOnStart = 1
let g:CtrlSpaceSaveWorkspaceOnSwitch = 1
let g:CtrlSpaceSaveWorkspaceOnExit = 1
set hidden 

set noincsearch
