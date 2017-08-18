"set guitablabel=%M%t
set guioptions-=T
set guioptions+=b
color koehler

if $VIMFONT != ""
  execute "set guifont=" . $VIMFONT
"else
  "set guifont=Monaco:h12
endif

amenu 70.100 View.Larger\ Font			:call FontAdjust(1)<CR>
amenu 70.110 View.Smaller\ Font			:call FontAdjust(-1)<CR>

amenu 80.100 Util.&WikiContent			:%!wikitool numberHeading %<CR>
amenu 80.110 Util.Cvs.&Checkin			:!ccvs ci %<CR>
amenu 80.111 Util.Cvs.&Restore\ Old\ Version	:!cvs update -C %<CR>
amenu 80.120 Util.Script.&Run			:!atstool vimrun %<CR>
vmenu 80.120 Util.Script.Re&number\ Steps	!vimfilt.rb % stepRenum<CR>
vmenu 80.130 Util.Format\ Comment		!trun vimfilt.rb % fmtcmt<CR>

amenu 10.111 File.&Print			:!devtool print %<CR>
