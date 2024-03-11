"######################################################################
" File:        /home/tvuong/.config/nvim/init.vim
" Author:      tvuong
" Created:     2024-03-12 10:03:09 -0700
" Copyright (c) Thien H. Vuong
" Description:
" Key Mapping Limitation:
"   vim maybe starting behind other apps which intercept keys before it
"   get to it.  In particular
"   - Windows based terminal: <C-c><, C-v>, <C-1>-<C-9>
"   - Tmux: <M-1>-<M-9>
"######################################################################

set nocompatible              " be iMproved, required
filetype off                  " required

"-- Self maintenance first --
if has("nvim")
  if has("unix")
    let g:config_path="~/.config/nvim"
  else
    let g:config_path="~/AppData/Local/nvim"
  endif
  let g:init_file=g:config_path . "/init.vim"
  let g:nv_init=g:config_path . "/init.nvim"
else
  let g:init_file="~/.vimrc"
endif

autocmd!
execute 'autocmd! BufWritePost ' . g:init_file . ' source ' . g:init_file

function! SourceIfExists(file)
  if filereadable(expand(a:file))
    exe 'source' a:file
  endif
endfunction

map ,vv :execute "edit "   . g:init_file<CR>
map ,vs :execute "source " . g:init_file<CR>

"-- Plugins --
" I cannot autoload this somehow, so it must be sourced manually
source ~/.vim/autoload/plug.vim
call plug#begin('~/.vim/plugged')

" Basic editing
Plug 'tpope/vim-surround'
Plug 'zefei/vim-wintabs'
"Plug 'preservim/nerdtree'

" Language support
Plug 'pangloss/vim-javascript'
Plug 'leafgarland/typescript-vim'
Plug 'maxmellon/vim-jsx-pretty'
Plug 'jparise/vim-graphql'

" This must be here since plugin block can only be defined once
if has("nvim")
  Plug 'neoclide/coc.nvim', {'branch': 'release'}
  Plug 'glacambre/firenvim', {'do': {_ -> firenvim#install(0)}}
endif
call plug#end()

filetype plugin on
filetype plugin indent on

" ---------------------------------------------------
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

" Map to emtux split window sequence.  Tmux also use C-E to split window, so we " use C-W in that case
if empty($TMUX)
  map <C-E>-  <C-W>s
  map <C-E>\| <C-W>v
  map <C-E>c  <C-W>c
endif
map <C-W>-  <C-W>s
map <C-W>\| <C-W>v

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

function! MapMeta(mkey, rhs)
  let l:skey = "<M-" . a:mkey . ">"
  execute 'nmap' l:skey a:rhs
  execute 'imap' l:skey '<C-o>' . a:rhs
  
  " This should check for tmux, but I also enable so have the
  " same key pattern for but tmux and non (easy to remember_

  let l:tmkey = "<leader>" . a:mkey
  execute 'nmap' l:tmkey a:rhs
  execute 'imap' l:tmkey '<C-o>' . a:rhs
endfunction

call MapMeta('b', ':buffers<CR>')
call MapMeta('t', ':tj /')

set wmh=0

"--------------------------------------- Quick switching of buffers ---
" Maximize and split the window
map 	 <Leader>- :only\|split<CR>

"<A-C> Indented shell comment start
"-----------------------------------------------------------------------
imap	ã	.<BS>#---  ---<BS><BS><BS>i
map	c	40A <ESC>41\|C#<Space>

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

"set listchars=tab:»­,trail:­
highlight NonText guifg=#ff4444

"For code formatting
set fo=croq
set comments=:#--- 

set uc=0
set autoread
autocmd FocusGained * checktime

set sidescrolloff=4
set foldlevel=10
set foldcolumn=2


" Map alt-z to fold alternate
map <BS>   za
map <C-BS> zM
map <M-BS> zR

map <Up>   gk
map <Down> gj

call MapMeta('1', ':WintabsGo 1<CR>')
call MapMeta('2', ':WintabsGo 2<CR>')
call MapMeta('3', ':WintabsGo 3<CR>')
call MapMeta('4', ':WintabsGo 4<CR>')
call MapMeta('5', ':WintabsGo 5<CR>')
call MapMeta('6', ':WintabsGo 6<CR>')
call MapMeta('7', ':WintabsGo 7<CR>')
call MapMeta('8', ':WintabsGo 8<CR>')
call MapMeta('9', ':WintabsGo 9<CR>')

syntax on

set mouse=a
set mousefocus

highlight Folded guibg=#444444 guifg=#888888

if $VIMCOLOR != ""
  execute "color " . $VIMCOLOR
else
  colorscheme darkblue
  "colorscheme desert
endif
set colorcolumn=82

set hlsearch
highlight Folded guibg=#444444 guifg=#888888
set iskeyword=48-57,_,A-Z,a-z
set tags=tags,TAGS
set number

autocmd FileType ruby   compiler rubocop
autocmd FileType go     setlocal ts=4 sw=4 expandtab! list
autocmd FileType python setlocal ts=2 sw=2 expandtab list foldmethod=indent
autocmd FileType ruby   setlocal ts=2 sw=2 expandtab list norelativenumber nocursorline re=1 foldmethod=manual

syntax on             " Enable syntax highlighting
filetype on           " Enable filetype detection
filetype indent on    " Enable filetype-specific indenting
filetype plugin on    " Enable filetype-specific plugins

set noincsearch

hi Comment guifg=#AAFFAA

set foldmethod=syntax

" register + is primary cut/paste
if has("windows")
  " yank/put support in windows
  map     <C-y>           "+y
  map     <C-p>           "+p
else
  " Only for GUI. For Non-GUI, input is controlled by terminal program
  if has("gui_running")
    "Copy
    nnoremap <C-y> "+y  " Normal (must follow with an operator)
    xnoremap <C-y> "+y  " Visual

    "Paste
    noremap! <C-p> "+p
    inoremap <C-p> <C-r>+
  endif
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

"===== Neovide Customization
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


if has("nvim")
  let g:nv_init=g:config_path . "/init.nvim"
  call SourceIfExists(g:nv_init)

  " This must be here because init.nvim does not reset autocmd
  " so would accumulate this definition
  "
  if !has("unix")
    autocmd BufWritePost * lua fix_mode()
  endif
endif

"echo "Loading " . g:init_file
