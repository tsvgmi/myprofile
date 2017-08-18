augroup filetypedetect
au! BufRead,BufNewFile *.xml                 set filetype=xml
au! BufRead,BufNewFile *.rhtml               set filetype=ruby
au! BufRead,BufNewFile *.lib                 set filetype=tcl
au! BufRead,BufNewFile *.haml                set filetype=ruby
au! BufRead,BufNewFile *.wiki                set filetype=wikipedia
au! BufRead,BufNewFile *.wikipedia.org*      set filetype=wikipedia
au! BufNewFile,BufRead *.tjp,*.tji           setf tjp
au! BufNewFile,BufRead *.yml.clerb,*.yml.erb set filetype=yaml
augroup END

