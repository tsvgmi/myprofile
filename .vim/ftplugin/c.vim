"
" Specific definition for C files
setlocal shiftwidth=4
setlocal expandtab

command! -range CtypeComment <line1>,<line2>!trun vimfilt.rb % ctypeComment

vmap <buffer> <LocalLeader>cC	:CtypeComment<CR>

noremap <buffer> <LocalLeader>cc	$40a <Esc>41\|C/* */<Esc>hhi 
noremap <buffer> <LocalLeader>db	v/^}<CR>!addDbug<CR>
