#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        vimfilt.rb
# Date:        Wed Nov 07 09:23:03 PST 2007
# $Id: vimfilt.rb 6 2010-11-26 10:59:34Z tvuong $
#---------------------------------------------------------------------------
#+++
=begin rdoc
=NAME
vimfilt.rb - VIM miscellaneous filter

=SYNOPSIS

=DESCRIPTION
This script implements various vi/vim filter used in development.  This
is preferable to writing filter in VIM scripting language (this works
for other editors as well).  This allows creating common filter script
which could be used with many editors.

=end

require File.dirname(__FILE__) + "/../etc/toolenv"
require 'mtool/core'

# Various text filter processing
class TextFilter
  
  # Align the columns on the block of lines
  # rows::  Data block to align
  # ncols:: Number of columns to line up
  def self.alignColumn(rows, ncols = 9999) 
    colsize = Array.new(20, 0)
    bofs    = -1
    maxcols = 0
    lines   = []
    ncols   = ncols.to_i
    rows.each do |l|
      l.sub!(/(struct|static|volatile|virtual) /, '\1.')
      fields = l.split(nil, ncols+1)
      lines << fields
      if bofs < 0
	if l =~ /^(\s*)/
	  bofs = $1.length
	end
      end
      i = 0
      fields.each do |acol|
        if colsize[i] < acol.length
	  colsize[i] = acol.length
	end
	i += 1
      end
      maxcols = i if (maxcols < i)
    end
    #puts "Colsize = #{colsize.join ' '}"
    pad    = "                    "[0, bofs]
    lines.map do |aline|
      i    = 0
      line = pad
      aline.each do |afield|
        line += "%-#{colsize[i]}s " % afield
	i += 1
      end
      line.sub(/(struct|static|volatile|virtual)\./, '\1 ').rstrip
    end
  end

  # Do the text wrap on the block of data
  # rows::    Data to wrap
  # cols::    Max columns
  # sindent:: 2nd line and subsequent indentation
  def self.wrap(rows, cols=80, sindent = 0)
    spad  = " " * sindent
    cols2 = cols - sindent
    rows.map do |arow|
      match = (arow =~ /^\s*/) ? $& : nil
      arow.gsub!(/\n/," ")
      if match
        cols -= match.length
        arow.gsub!(/.{1,#{cols}}(?:\s|\z)/) { |s| "#{match}#{s}\n#{spad}" }
        arow.sub!(/^#{match}/, '')
      else
        arow.sub!(/.{1,#{cols}}(?:\s|\z)/) { |s| "#{s}\n#{spad}" }
      end
      arow.rstrip
    end
  end

  # Filter to align the equal signs of block.  Make assignment block cleaner
  # rows::    Data to wrap
  def self.alignEqual(rows)
    ofs = 0
    rows.each do |l|
      oline = l.sub(/\s+=\s+/, ' = ')
      if oline =~ /\s+=\s+/
	size = $`.length
	ofs = size if (ofs < size)
      end
    end
    rows.map do |aline|
      if aline =~ /^(.+)\s+=\s+(.+)$/
	"%-#{ofs}s = %s" % [$1.rstrip, $2]
      else
	aline
      end
    end
  end

  # This uses indent with a set of pre-defined options to comply
  # to source code convention.  It also insures the inline
  # documentation is not touched and expands the tabs.
  def self.indent(input)
    require 'tempfile'

    tmpf    = Tempfile.new("vf").path
    File.catto(tmpf, input)
    profile = File.read(Pf.etcDir("indent.pro")).gsub("\n", " ")
    `indent -npro #{profile} <#{tmpf} | expand`
  end
end

class VimFilt
  extendCli __FILE__

  attr_reader	:filename

  def initialize(fname)                                                #{{{2
    @filename = fname
    @brlevel  = 0
  end

  # Read stdin into array
  def readData
    result = []
    while $stdin.gets
      result << $_.chomp
    end
    result
  end

  # Output a long bar
  def cbar
    result = ''
    pad    = "-" * 80
    readData.each do |l|
      if l =~ /^(\s*)#-+\s+(.*)\s+-+$/
	head, cmt = $1, $2
	bsize = 70 - head.size - cmt.size
	l = "%s#%#{bsize}.#{bsize}s %s ---" % [head, pad, cmt]
      end
      puts l
    end
    nil
  end

  def alignEqual
    TextFilter.alignEqual(readData)
  end
  alias ae alignEqual

  # Align all columns (up to ncols)
  def alignColumn(ncols = 9999) 
    TextFilter.alignColumn(readData, ncols)
  end
  alias alcol alignColumn

  private
  def _fmtUseDesc(use, descr)                                          #{{{2
    use = use.sub(/\s+#\{\{\{.*$/, '').sub(/\(\(</,'').sub(/>\)\)/,'')
    return use unless descr
    if (use.length >= 36) || (descr.length >= 38)
      if descr.length >= 38
	return "%-36s\n%-10s%s" % [use, '', descr]
      else
	return "%-36s\n%-41s%s" % [use, '', descr]
      end
    end
    return "%-36s %s" % [use, descr]
  end

  public
  # Generate a function header from current buffer
  def funcHeader                                                       #{{{2
    svlines = readData
    # Make move to JS handler later
    if svlines.join(" ") =~ /^\s*function\s+\((\S+.*)$/
      func = $1.sub(/\s*\(.*$/, '')
      if line =~ /\(([^\)]+)\)/
        args, parms = $1, ''
        args.split(/\s*,\s*/).each do |aparm|
          parms << " * %11s: \n" % [aparm.sub(/\s*=.*$/, '')]
        end
        parms.chomp!
      end
      puts <<EOH
/*************************************************************
*    Function: #{func}
#{parms}
*************************************************************/
#{svlines.join("\n")}
EOH
    elsif svlines.join(" ") =~ /^\s*function\s+(\S+.*)$/
      func = $1.sub(/\s+.*$/, '')
      puts <<EOH
#==========================================================================
# Function:    [#{func}]
# Description: .
# Use:         .
#==========================================================================
#{svlines.join("\n")}
EOH
    end
  end

  # Generate the use text to be added to shell script.  Used to replace
  # the use area of the shell script.
  def genUse(pattern = "-", verbose = false)                           #{{{2
    prog = File.basename(@filename).sub(/^.*@/, '')
    cmds, desc = {}, {}
    ucmt, descr = nil, nil
    File.foreach(@filename) do |aline|
      if aline =~ /#\s*@Use:\s+(.*)$/
	ucmt = $1.sub(/\s+#\{\{\{.*$/, '')
      elsif aline =~ /#\s*@Desc?:\s+(.*)$/
	descr = $1
      elsif (aline =~ /^(  )([a-zA-Z0-9_*.|-]+)\)/)
	oper = $2
	next if oper.length == 1
	if ucmt
	  lcmt = "#{prog} #{ucmt.gsub(/\|/, ':')}"
	  ucmt = nil
	else
	  lcmt = "#{prog} #{oper.gsub(/\|/, ':')}"
	end
	if (pattern == "-") || (lcmt =~ /#{pattern}/)
	  cmds[oper] = lcmt.chomp
	  desc[oper] = descr.chomp if (descr && (descr != ""))
	end
	ucmt = descr = nil
      end
    end
    count = 1
    cmds.keys.sort.each do |acmd|
      next if acmd =~ /^_/
      use, descr = cmds[acmd], desc[acmd]
      use, descr = use.split(/\s*:::\s*/) unless descr
      descr = "[#{descr}]"if descr
      if verbose
        puts("  %2d. %s" % [count, _fmtUseDesc(use, descr)])
        count += 1
      else
	puts "  * #{use}"
      end
    end
    nil
  end

  # Generate the file header templates
  def fileTemplate
    require 'erb'

    result   = ''
    fext     = File.extname(@filename)[1..10]
    tpl_list = ["Template/file-#{fext}.erb",
     "Template/file.erb"]
    tpl_list.each do |tplfile|
      ENV['ERB_ARG'] = "#{filename}"
      if File.readable?(Pf.etcDir(tplfile))
	result = ERB.new(File.read(Pf.etcDir(tplfile))).result
	break
      end
    end
    if result.empty?
      Plog.error "No template found from #{tpl_list.join(' ')}"
    end
    result
  end

# Add a fold marker to the line
  def addFold(cstart='#', cend='')                                     #{{{2
    readData.each do |l|
      line = l.sub(/\s+#{cstart}\{\{.*$/, '')
      if line =~ /^( +)/
	flevel = $1.size/2 + 1
      else
	if (line =~ /^#==/) || (line =~ /@ *Use:/)
	  flevel = 2
	else
	  flevel = 1
	end
      end
      puts("%-70s %s\{\{\{%d%s" % [line, cstart, flevel, cend])
    end
    nil
  end

  # Format a shell command block.  Use the 1st line as the indentation
  # guide and format the rest with it.
  def fmtcmt()
    lines = readData
    if lines[0] =~ /^(\s+)#/
      prefix = $1
    else
      prefix = ""
    end
    width = 76 - prefix.length

    fmtout = IO.popen("fmt -w #{width} | sed 's/^/#{prefix}# /'", "w")
    lines.each do |l|
      fmtout.puts l.sub(/^\s*# ?/, '')
    end
    fmtout.close
    nil
  end

  def fmt_haml()
    fmtout = IO.popen("fmt -cw 72 | sed 's/$/ |/'", "w")
    readData.each do |l|
      fmtout.puts l.sub(/\s*\|$/, '')
    end
    fmtout.close
    nil
  end

  def genTag
    result = []
    `ctags -x #{filename}`.each_line do |l|
      l = l.sub(/singleton method/,'smethod').split[0,3]
      result << l
    end
    result
  end

  def indent
    TextFilter.indent(readData.join("\n"))
  end

  # Custon object instantiation for CLI use
  def self.cliNew
    (ARGV.size > 1) || VimFilt.cliUsage
    file  = ARGV.shift
    ftype = getOption(:type) || File.extname(file)[1..-1]
    if !ftype && (file != "-")
      File.open(file) do |fid|
      aline = fid.gets.chomp
	if (aline =~ /perl/)
	  ftype="pl"
	elsif (aline =~ /tcl/)
	  ftype="tcl"
	end
	break
      end
    end

    if ftype == "rb"
      RubyFilt.new(file)
    elsif (ftype == "tcl") || (ftype == "itcl") || (ftype == "exp")
      TclFilt.new(file)
    elsif ftype =~ /(cgi|pl|pm)/
      PerlFilt.new(file)
    elsif ftype =~ /^[chm]$/
      CFilt.new(file)
    elsif ftype == "js"
      JSFilt.new(file)
    else
      VimFilt.new(file)
    end
  end
end

module PrintFormat                                                     #{{{1
  # Format the file for printout
  def prFormat                                                         #{{{2
    bracket = [
    	['        ', '        ', '+-------'],
    	['+-------', '|       ', '|+------'],
    	['|+------', '||      ', '||+-----'],
    	['||+-----', '|||     ', '|||+----'],
    	['|||+----', '||||    ', '||||+---'],
    	['||||+---', '|||||   ', '|||||+--'],
    	['|||||+--', '||||||  ', '||||||+-'],
    	['||||||+-', '||||||| ', '|||||||+'],
    	['|||||||+', '||||||||', '||||||||']
    ]

    lc, @pc, @pc0, level, olevel, flist = 1, 0, 0, 0, 0, []
    @major, @pbuf, @pbuf0 = '', '', ''
    File.foreach("| expand #{filename}") do |aline|
      change, inc, fname, mod = prScanLine(aline.chomp)
      level += inc

      #-------------------------------- Make sure I stay in the limit ---
      plevel = level
      plevel = 0 if level < 0
      plevel = 8 if level > 8
      if olevel < level
	brk = bracket[plevel][0]
      elsif olevel > level
	brk = bracket[plevel][2]
      else
	brk = bracket[plevel][1]
      end
      oline = "%s%s  %s" % [brk, change ? '>' : ' ', aline]
      if VimFilt.getOption(:enscript) && (fname || mod)
	oline = "\0shade{0.8}#{oline}\0shade{1.0}"
      end

      pageBuffer(oline, level <= @brlevel)

      if fname
	flist << [fname, lc]
      end
      lc += 1
      olevel = level
    end
    print @pbuf0 if @pbuf0 != ''
    print @pbuf  if @pbuf  != ''
    puts

    genTag.each do |key, type, line|
      puts "%-40s %-10s %4d" % [key, type, line]
    end
    nil
  end

  def pageBuffer(oline, breakOk)                                       #{{{2
=begin
--- Method: pageBuffer(oline, breakOk)
    Buffer output into a page and burst it out
*      oline: 
*    breakOk: 
=end
    if breakOk
      if @pbuf != ''
	if (@pc0 + @pc) > 60
	  print @pbuf0, "\014\n"
	  @pbuf0, @pc0 = '', 0
	end
	@pbuf0 << @pbuf
	@pc0 += @pc
	@pbuf, @pc = '', 0
      end
      @pbuf0 << "#{oline}"
      @pc0 += 1
    else
      @pbuf << "#{oline}"
      @pc += 1
      if (@pc > 60)
	if @pbuf0 != ''
	  print @pbuf0, "\014\n"
	  @pbuf0, @pc0 = '', 0
	end
	print @pbuf, "\014\n"
	@pbuf, @pc = '', 0
      end
    end
  end

end

class RubyFilt < VimFilt                                               #{{{1
=begin
--- Class: RubyFilt
=end
  include PrintFormat

  def initialize(fname)                                                #{{{2
    super
    @brlevel   = 1
    @incomment = false
  end

=begin
--- funcHeader
    Generate the function header.  Filter on the declaration block
=end
  def funcHeader
    svlines = readData
    line = svlines.join(" ")
    if line =~ /^\s+def\s+(\S+.*)$/
      func = $1.sub(/ +#.*$/, '')
      if line =~ /\(([^\)]+)\)/
        args, parms = $1, ''
        args.split(/\s*,\s*/).each do |aparm|
          parms << "* %10s: \n" % [aparm.sub(/\s*=.*$/, '')]
        end
        parms.chomp!
      end
      marker = line.strip.sub(/\s*\(.*$/, '').sub(/^(def|class)\s+/, '')
      bar    = "=" * (72 - marker.size)
      puts <<EOH
##{bar} #{marker}
#{svlines.join("\n")}
=begin
--- Method: #{func}
#{parms}
=end
EOH
    elsif line =~ /^\s*(class|module)\s+(\S+)/
      marker = line.strip
      bar    = "=" * (72 - marker.size)
      puts <<EOH
##{bar} #{marker}
#{svlines.join("\n")}
=begin
--- #{$1}: #{$2}
=end
EOH
    elsif line =~ /^\s*module\s+(\S+)/
      puts <<EOH
#{svlines.join("\n")}
=begin
--- Module: #{$1}
=end
EOH
    end
  end

=begin
--- Method: prScanLine(aline)
    Scan a line and returns meaningful info, change, level incr, keyword
*      aline: 
=end
  def prScanLine(aline)                                                #{{{2
    change, level, fname, mod = false, 0, nil, nil

    # Skip the comment block
    if aline =~ /^=begin/
      @incomment = true
      return [change, level, fname, mod]
    elsif @incomment
      if aline !~ /^=end/
	return [change, level, fname, mod]
      end
      @incomment = false
    end

    if aline !~ /^\s*#/
      level += 1 if (aline =~ /^\s*(begin|case|class|def|if|module|unless|while)(\s|$)/)
      level += 1 if (aline =~ /\s(do|\{)(\s|$)/)
      if ((aline =~ /^\s*(elsif|when)\s/) ||
	  (aline =~ /^\s*(else)(\s|$)/))
	change = true
      end
      level -= 1 if (aline =~ /^\s*end(\s|$)/)
      level -= 1 if (aline =~ /\s(\})(\s|$)/)

      if aline =~ /^\s*def\s+([A-Za-z0-9_.]+)/
	fname = $1
	if fname !~ /\./
	  fname = "#{@major}.#{fname}"
	end
      elsif aline =~ /^\s*(class|module)\s+([A-Za-z0-9_.]+)/
	@major = mod = $2
      end
    end
    [change, level, fname, mod]
  end
end

class TclFilt < VimFilt                                                #{{{1
  include PrintFormat

  def prScanLine(aline)                                                #{{{2
=begin
--- Method: prScanLine(aline)
    Scan a line and returns meaningful info, change, level incr, keyword
*      aline: 
=end
    change, level, fname, mod = false, 0, nil, nil
    if aline !~ /^\s*#/
      inc = aline.count("{")
      dec = aline.count("}")
      level = level + inc - dec
      if (inc > 0) && (inc == dec)
	change = true
      end

      if aline =~ /^\s*proc\s+([A-Za-z0-9_]+)/
	fname = $1
      elsif aline =~ /^\s*(part|method)\s+([A-Za-z0-9_]+)/
	fname = "#{@major}.#{$2}"
      elsif aline =~ /^\s*(class|ensemble)\s+([A-Za-z0-9_]+)/
	@major = mod = $2
      end
    end
    [change, level, fname, mod]
  end

  def funcHeader                                                       #{{{2
    bar = "========================================================================"
    readData.each do |line|
      if line =~ /^\s*(class|ensemble)\s+(\S+)/
	type, func = $1, $2
	puts    "#=%72.72s\n" % [bar] <<
		"# %10s: %s\n" % [type, func] <<
		"# %10s: \n" % ["Purpose"] <<
		"#=%72.72s\n" % [bar] << line
      elsif line =~ /^(\s*)(proc|method|part|body|typemethod)\s+(\S+)\s+(.*)$/
	pref, type, func, remain = $1, $2, $3, $4
	parms = ''
	if remain
	  remain.gsub(/[{}]/, '').split.each do |aparm|
	    parms << "#{pref}# %10s: \n" % [aparm]
	  end
	end
	rlen = 72 - pref.length
	puts    "#{pref}#=%#{rlen}.#{rlen}s\n" % [bar] <<
		"#{pref}# %10s: %s\n" % [type, func] <<
		"#{pref}# %10s: \n" % ["Purpose"] <<
		parms <<
		"#{pref}#=%#{rlen}.#{rlen}s\n" % [bar] << line
      elsif line =~ /^(\s*)snit::(method|typemethod)\s+(\S+)\s+(\S+)\s+(.*)$/
	pref, type, main, func, remain = $1, $2, $3, $4, $5
	parms = ''
	if remain
	  remain.gsub(/[{}]/, '').split.each do |aparm|
	    parms << "#{pref}# %10s: \n" % [aparm]
	  end
	end
	rlen = 72 - pref.length
	func =  "#{main}.#{func}"
	puts    "#{pref}#=%#{rlen}.#{rlen}s\n" % [bar] <<
		"#{pref}# %10s: %s\n" % [type, func] <<
		"#{pref}# %10s: \n" % ["Purpose"] <<
		parms <<
		"#{pref}#=%#{rlen}.#{rlen}s\n" % [bar] << line
      else
	puts line
      end
    end
    return nil
  end
end

class CFilt < VimFilt                                                  #{{{1
  def addFold                                                          #{{{2
    super('//')
  end

  def funcHeader
=begin
--- Method: funcHeader
    Generate a function header from current buffer
=end
    svlines = readData
    if svlines.join =~ /^\s*([A-Za-z0-9_]+)\s*\(([^\)]*)[\),]$/
      func = $1
      args = $2.strip.gsub(/\s*,\s*/, ',').split(/,/)
      parms = ''
      args.each do |aparm|
        aparm = aparm.split.last.sub(/^\*+/, '')
        parms << " * %11s: \n" % [aparm.sub(/\s*=.*$/, '')]
      end
      parms.chomp!
    end
    puts <<EOH
/*************************************************************
 *    Function: #{func}
 * Description: .
#{parms}
 *************************************************************/
EOH
    puts svlines.join("\n")
  end

  def ctypeComment
=begin
--- Method: ctypeComment
    Convert the C++ type comment to C type comment
=end
    readData.each do |l|
      if l =~ /^(.*)\/\/(.*)$/
	puts "#{$1}/*#{$2} */"
      else
	puts l
      end
    end
  end
end

#================================================== class JSFilt < VimFilt
class JSFilt < VimFilt
=begin
--- class: JSFilt
=end
  def funcHeader
    svlines = readData
    if svlines.join(' ') =~ /^\s*function\s+(\S+.*)$/
      func = $1.sub(/\s*\(.*$/, '')
      if line =~ /\(([^\)]+)\)/
        args, parms = $1, ''
        args.split(/\s*,\s*/).each do |aparm|
          parms << " * %11s: \n" % [aparm.sub(/\s*=.*$/, '')]
        end
        parms.chomp!
      end
      puts <<EOH
/*************************************************************
 *    Function: #{func}
#{parms}
 *************************************************************/
#{svlines.join("\n")}
EOH
    end
  end
end

#================================================ class PerlFilt < VimFilt
class PerlFilt < VimFilt
=begin
--- class: PerlFilt
=end
  include PrintFormat

=begin
--- funcHeader
    Generate the function header.  Filter on the declaration block
=end
  def funcHeader
    svlines = readData
    line = svlines.join(' ');
    if svlines.join(' ') =~ /^\s*sub\s+(\S+)/
      func = $1
      if line =~ /\(([^\)]+)\)/
        args, parms = $1, ''
        args.split(/\s*,\s*/).each do |aparm|
          parms << "# %11s: \n" % [aparm.sub(/\s*=.*$/, '')]
        end
        parms.chomp!
      end
      puts <<EOH
#######################################################################
# Function:    #{func}
#{parms}
# Description:	
#######################################################################
#{svlines.join("\n")}
EOH
    end
  end

=begin
--- Method: prScanLine(aline)
    Scan a line and returns meaningful info, change, level incr, keyword
*      aline: 
=end
  def prScanLine(aline)
    change, level, fname, mod = false, 0, nil, nil
    if aline !~ /^\s*#/
      level += aline.count("{")
      level -= aline.count("}")
      if ((aline =~ /^\s*elsif\s*\{/) ||
	  (aline =~ /^\s*else\s*\{/))
	change = true
      end

      if aline =~ /^\s*sub\s+([A-Za-z0-9_.]+)/
	fname = $1
	if fname !~ /\./
	  fname = "#{@major}.#{fname}"
	end
      end
    end
    [change, level, fname, mod]
  end
end

if (__FILE__ == $0)
  VimFilt.handleCli(["--enscript", "-e"],
                    ["--type",     "-t"])
end


