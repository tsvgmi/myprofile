" == START OF VUNDLE ===
set nocompatible              " be iMproved, required
filetype off                  " required

set rtp+=~/.vim/bundle/Vundle.vim

call vundle#begin()
Plugin 'https://github.com/zefei/vim-wintabs'
Plugin 'https://github.com/preservim/nerdtree'
call vundle#end()

filetype plugin on
filetype plugin indent on

" ===================================================
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

" Map to emtux split window sequence.  This won't work if vim is running under emtmux
map <C-E>-  <C-W>s
map <C-E>\| <C-W>v
map <C-E>d  <C-W>c

"
" DOS keyboard mapping for cursor keys
"
imap <ESC>OA  <Up>
imap <ESC>OD  <Left>
imap <ESC>OC  <Right>
imap <ESC>OB  <Down>
imap <ESC>[5~ <PageUp>
imap <ESC>[6~ <PageDown>

" Disable slow process in network volume
autocmd BufReadPre //* :NoMatchParen

"--------------------------------------------- So it behaves like crisp ---
"<F7>	Begin of macro (must use 'q' to terminate macro)
"<F8>	Playback of macro
"<F5>	Search
"<F6>	Replace
"<A-N>	Next buffer
"<A-P>	Previous buffer
"<A-B>	List uffers
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

set ttyfast
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

if has("unix")
  let g:init_file="~/.config/nvim/init.vim"
else
  let g:init_file="~/AppData/Local/nvim/init.vim"
endif

autocmd!
execute 'autocmd BufWritePost ' . g:init_file . ' source ' . g:init_file

set uc=0
set autoread

set sidescrolloff=4
set foldlevel=10
set foldcolumn=2

function! WslWrap(command)
  execute '!wsl bash ~/winbin/wslwrap ' . a:command
endfunction

function! VimFilt(cmd) range
  execute a:firstline . ',' . a:lastline . '!wsl ~/winbin/wslwrap vimfilt.rb ' . a:cmd
endfunction

map  ,fH  0r!wsl ~/winbin/wslwrap vimfilt.rb file_template '%:p'<CR>
map  ,#   $50a 51\|C#
vmap ,a1c :call VimFilt("align_column 1")<CR>
vmap ,a2c :call VimFilt("align_column 2")<CR>
vmap ,a3c :call VimFilt("align_column 3")<CR>
vmap ,a3c :call VimFilt("align_column 4")<CR>
vmap ,ac  :call VimFilt("align_column")<CR>
vmap ,ae  :call VimFilt("align_equal")<CR>
vmap ,cb  :call VimFilt("cbar")<CR>
vmap ,cf  :call VimFilt("fmt_cmt")<CR>
vmap ,fh  :call VimFilt("func_header")<CR>
vmap ,fG  :call VimFilt("gen_use '%:p'")<CR>

" Open current file in new window
map <C-N> :!gvim %<CR><CR>:bd<CR>

" Map alt-z to fold alternate
map <BS>   za
map <C-BS> zM
map <M-BS> zR

map <Up>   gk
map <Down> gj

function! MapBoth(keys, rhs)
  execute 'nmap' a:keys a:rhs
  execute 'imap' a:keys '<C-o>' . a:rhs
endfunction

" Tab selection mapping
call MapBoth('<M-1>', ':WintabsGo 1<CR>')
call MapBoth('<M-2>', ':WintabsGo 2<CR>')
call MapBoth('<M-3>', ':WintabsGo 3<CR>')
call MapBoth('<M-4>', ':WintabsGo 4<CR>')
call MapBoth('<M-5>', ':WintabsGo 5<CR>')
call MapBoth('<M-6>', ':WintabsGo 6<CR>')
call MapBoth('<M-7>', ':WintabsGo 7<CR>')
call MapBoth('<M-8>', ':WintabsGo 8<CR>')
call MapBoth('<M-9>', ':WintabsGo 9<CR>')

syntax on

set mouse=a
set mousefocus

highlight Folded guibg=#444444 guifg=#888888

if $VIMCOLOR != ""
  execute "color " . $VIMCOLOR
else
  colorscheme darkblue
endif
set colorcolumn=82

set hlsearch
highlight Folded guibg=#444444 guifg=#888888
set iskeyword=48-57,_,A-Z,a-z
set tags=tags,TAGS
set number

autocmd FileType ruby   compiler ruby
autocmd FileType go     setlocal ts=4 sw=4 expandtab! list
autocmd FileType python setlocal ts=2 sw=2 expandtab list foldmethod=indent
autocmd FileType ruby   setlocal ts=2 sw=2 expandtab list norelativenumber nocursorline re=1 foldmethod=manual

syntax on             " Enable syntax highlighting
filetype on           " Enable filetype detection
filetype indent on    " Enable filetype-specific indenting
filetype plugin on    " Enable filetype-specific plugins

set noincsearch

"let ruby_fold = 1
"let ruby_foldable_groups = 'def class module for if case'
"let ruby_minlines = 100

"let g:is_bash = 1
"let g:sh_fold_enabled = 1

hi Comment guifg=#AAFFAA

set foldmethod=syntax
set directory^=$HOME/tmp
set backupdir^=$HOME/tmp

if has("gui_running")
  " Copy
  nnoremap <C-c> "+y  " Normal (must follow with an operator)
  xnoremap <C-c> "+y  " Visual

  " Paste
  "nnoremap <C-v> "+p  " Normal
  noremap! <C-v> <C-r>+
  inoremap <C-v> <C-r>+
endif

" Mapping for Wintabs
map <C-H> <Plug>(wintabs_previous)
map <C-L> <Plug>(wintabs_next)
map <C-T>c <Plug>(wintabs_close)
map <C-T>u <Plug>(wintabs_undo)
map <C-T>o <Plug>(wintabs_only)
map <C-W>c <Plug>(wintabs_close_window)
map <C-W>o <Plug>(wintabs_only_window)
command! Tabc WintabsCloseVimtab
command! Tabo WintabsOnlyVimtab

if exists("g:NERDTreeDirArrowExpandable")
  nnoremap <C-n> :NERDTree<CR>
  nnoremap <C-t> :NERDTreeToggle<CR>
  command! -nargs=1 Sdir %bd | cd ../<args> | NERDTree | wincmd p
else
  command! -nargs=1 Sdir %bd | cd ../<args>
endif

" Neovide Customization
if exists("g:neovide")
  let g:neovide_transparency = 0.8
  let g:neovide_hide_mouse_when_typing = v:true
  set guifont=CaskaydiaCove\ Nerd\ Font\ Mono,Consolas,Lucida\ Console:h10
  let s:fontscale = 1.0
  function! AdjustFontSize(amount)
    let s:fontscale = s:fontscale + (a:amount/10.0)
    let g:neovide_scale_factor = s:fontscale
  endfunction
else
  let s:fontname = "CaskaydiaCove\\ Nerd\\ Font\\ Mono"
  let s:fontsize = 10
  :execute "set guifont=" . s:fontname . ":h" . s:fontsize
  function! AdjustFontSize(amount)
    let s:fontsize = s:fontsize+a:amount
    :execute "set guifont=" . s:fontname . ":h" . s:fontsize
  endfunction
endif
noremap <C-=> :call AdjustFontSize(1)<CR>
noremap <C--> :call AdjustFontSize(-1)<CR>

" If current file is on WSL FS, exbit is cleared.  So we have to reset
" blindly for now
autocmd BufWritePost * call WslWrap("chmod +x '%:p'")

map ,vv :execute "edit "   . stdpath('config') . "/init.vim"<CR>
map ,vs :execute "source " . stdpath('config') . "/init.vim"<CR>

echo "Init file loaded from " . stdpath('config')
