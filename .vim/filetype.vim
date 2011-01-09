augroup filetypedetect
au! BufRead,BufNewFile *.xml		set filetype=xml
au! BufRead,BufNewFile *.rhtml		set filetype=ruby
au! BufRead,BufNewFile *.lib		set filetype=tcl
au! BufRead,BufNewFile *.haml		set filetype=ruby
au! BufRead,BufNewFile *.wiki set filetype=wikipedia
au! BufRead,BufNewFile *.wikipedia.org* set filetype=wikipedia
augroup END

