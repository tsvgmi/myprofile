if exists("loaded_mthelper")
  finish
endif
let loaded_mthelper = 1

function! FontAdjust(offset)
  if !exists("s:gfontsize")
    let s:gfontsize = substitute(&guifont, '^.* ', "", "")
    let s:gfontname = substitute(&guifont, ' [0-9]\{1,}$', "", "")
  endif
  if s:gfontsize <= 0
    let s:gfontsize = 10
  end
  let s:gfontsize = s:gfontsize + a:offset
  if s:gfontsize < 8
    let s:gfontsize = 8
  end
  let guifont  = s:gfontname . " " . s:gfontsize
  let &guifont = guifont
  echo guifont
endfunction
