" == START OF VUNDLE ===
set nocompatible              " be iMproved, required
filetype off                  " required

"-- Self maintenance first --
if has("nvim")
  if has("unix")
    let g:init_file="~/.config/nvim/init.vim"
  else
    let g:init_file="~/AppData/Local/nvim/init.vim"
  endif
else
  let g:init_file="~/.vimrc"
endif
let g:config_dir="~/.vim"

autocmd!
execute 'autocmd BufWritePost ' . g:init_file . ' source ' . g:init_file
map ,vv :execute "edit "   . g:init_file<CR>
map ,vs :execute "source " . g:init_file<CR>

"set rtp+=~/.vim/autoload
"set rtp+=~/.vim/autoload,~/.vim/bundle/Vundle.vim

"-- Plugins --
" I cannot autoload this somehow, so it must be sourced manually
source ~/.vim/autoload/plug.vim
call plug#begin('~/.vim/plugged')
Plug 'tpope/vim-surround'
Plug 'zefei/vim-wintabs'

Plug 'preservim/nerdtree'

" Development/Coding
Plug 'leafgarland/typescript-vim'
Plug 'maxmellon/vim-jsx-pretty'
Plug 'pangloss/vim-javascript'
Plug 'jparise/vim-graphql'

if has("nvim")
  Plug 'neoclide/coc.nvim', {'branch': 'release'}
  if has("unix") <= 0
    Plug 'glacambre/firenvim', {'do': {_ -> firenvim#install(0)}}
  end
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
else
  map <C-W>-  <C-W>s
  map <C-W>\| <C-W>v
endif

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

if has("nvim")
"============================================================
lua << EOF
function _G.has(feature)
  return vim.api.nvim_eval("has('" .. feature .. "')")
end

-- Build range prefix for vim command
function _G._ranger(with_range)
  local firstline, lastline, result

  if with_range == 0 then
    return "0r"
  elseif with_range == 9 then
    return "0r"
  elseif with_range == 1 then
    firstline = vim.api.nvim_buf_get_mark(0, "<")[1]
    lastline  = vim.api.nvim_buf_get_mark(0, ">")[1]
    return string.format("%d,%d", firstline, lastline)
  end
  return ""
end

-- Run an external Linux command
function _G._wslprefix(with_range)
  local result, cwd
  result = _ranger(with_range) .. "!"
  if has("unix") <= 0 then
    cwd    = vim.fn.getcwd()
    result = result .. "wsl ~/winbin/wslwrapd '" .. cwd .. "' "
  end
  return result
end

-- Run an external Linux command after switching to local dir
function _G.wsl(command)
  vim.cmd(_wslprefix() .. command)
end

function _G.gen_use()
  vimfilt("gen_use '%:p'")
end

function _G.rubocop(flag)
  flag = flag and flag or "a"
  vim.cmd(_wslprefix() .. "rubocop -" .. flag .. ' ' .. "'%:p'")
end

function _G.mktags()
  vim.cmd(_wslprefix() .. "devtool mktags")
end

-- New editor window on same file
function _G.new_editor()
  vim.cmd(_wslprefix() .. "neovide '%:p'")
end

-- Run the external filter vimfilt.rb for range
function _G.vimfilt(args)
  vim.cmd(_wslprefix(1) .. "vimfilt.rb " .. args)
end

EOF

map  ,fH  :lua vim.cmd(_wslprefix(0) .. "vimfilt.rb file_template '%:p'")<CR>
map  ,#   $50a 51\|C#
vmap ,a1c :lua vimfilt("align_column 1")<CR>
vmap ,a2c :lua vimfilt("align_column 2")<CR>
vmap ,a3c :lua vimfilt("align_column 3")<CR>
vmap ,a3c :lua vimfilt("align_column 4")<CR>
vmap ,ac  :lua vimfilt("align_column")<CR>
vmap ,ae  :lua vimfilt("align_equal")<CR>
vmap ,cb  :lua vimfilt("cbar")<CR>
vmap ,cf  :lua vimfilt("fmt_cmt")<CR>
vmap ,fh  :lua vimfilt("func_header")<CR>

endif

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

if has("windows")
  " yank/put support in windows
  map     <C-c>           "+y
  map     <C-P>           "+p
else
  " Only for GUI. For Non-GUI, input is controlled by terminal program
  if has("gui_running")
    "Copy
    nnoremap <C-c> "+y  " Normal (must follow with an operator)
    xnoremap <C-c> "+y  " Visual

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

augroup MyVimEnter
  autocmd!
  autocmd VimEnter * if exists("g:NERDTree")
  autocmd VimEnter *   nnoremap <C-n> :NERDTree<CR>
  autocmd VimEnter *   nnoremap <C-d> :NERDTreeToggle<CR>
  autocmd VimEnter *   command! -nargs=1 Sdir %bd | cd ../<args> | NERDTree | wincmd p
  autocmd VimEnter * endif
augroup END

" If current file is on WSL FS, exec bit is cleared.  So we have to reset
" blindly for now
if has("nvim") && !has("unix")
  lua << EOF
    -- Windows based edit will remove the exec bit on WSL.  Have to fix it
    function _G.fix_mode()
      local path = vim.fn.expand('%:p')
      local fext = path:match("^.+%.(.*)$")
      if path:find('wsl.localhost') and
            \ (fext == '' or fext == 'rb') then
        wsl("chmod +x '" .. path .. "'")
      end
    end
EOF

  autocmd BufWritePost * lua fix_mode()
endif

if match(&runtimepath, 'coc') != -1
  " Coc extensions
  let g:coc_global_extensions = ['coc-tsserver']

  " Remap keys for applying codeAction to the current line.
  nmap <leader>ac  <Plug>(coc-codeaction)
  " Apply AutoFix to problem on the current line.
  nmap <leader>qf  <Plug>(coc-fix-current)

  " GoTo code navigation.
  nmap <silent> gd <Plug>(coc-definition)
  nmap <silent> gy <Plug>(coc-type-definition)
  nmap <silent> gi <Plug>(coc-implementation)
  nmap <silent> gr <Plug>(coc-references)
endif

lua << EOF
  vim.g.firenvim_config = {
      globalSettings = { alt = "all" },
      localSettings = {
          [".*"] = {
              cmdline  = "neovim",
              content  = "text",
              priority = 0,
              selector = "textarea",
              takeover = "never"
          }
      }
  }
EOF

"echo "Init file loaded from " . g:init_file

