#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        shhelper.rb
# $Id: shhelper.rb 127 2009-10-26 06:22:10Z thien $
#---------------------------------------------------------------------------
#+++
require File.dirname(__FILE__) + "/../../etc/toolenv"
require 'pathname'
require 'mtool/core'

# Collection of simple methods to help using interactive shell.
class ShHelper
  extendCli __FILE__

  # Cutting list of columns (start from 0) from stdin and write to stdout
  def self.fcut(*cols)
    icols = cols.map {|is| is.to_i}
    while gets
      fields = $_.split
    end
  end

  # Substitue file name patterm 'from' to 'to'
  def self.substName(from, to, *flist)
    #puts "Changing from #{from} to #{to} for #{flist.join(' ')}"
    flist.each do |afile|
      #puts "Found #{afile}"
      dfile = afile.sub(/#{from}/, to)
      #puts "Change to #{dfile}"
      if dfile != afile
        Plog.info "Renaming #{afile} to #{dfile}"
        File.rename(afile, dfile)
      end
    end
    nil
  end

  public
# Get/Set the VIM font for the current display
  def self.vimFont(fontname = nil)
    config  = YmlConfig.new(Pf.userCfPath("vimfonts.yml"))
    display = ENV['DISPLAY']
    key     = case display
    when /localhost:[1-9]/
      rhost = ENV['SSH_CLIENT'].split[0]
      Pf.hostname(rhost)
    when /^(localhost)?:0/
      hostname(true)
    when /^:/
      hostname(true)
    when /^\/tmp\/launch/
      "macdisplay"
    else
      if display
        display.sub(/:.*$/, '').sub(/\..*$/, '')
      else
        ""
      end
    end
    if fontname
      config[key] = fontname
      config.save
    end
    if config[key]
      font = config[key].gsub(/ /, "\\ ")
      "export VIMFONT='#{font}'"
    else
      "export VIMFONT='fixed'"
    end
  end

  # Generate the function prototype of the file (to be included in
  # header file.  It uses cproto to generate the prototype then
  # cleanup the output.  It uses make to figure out the argument to
  # pass to cproto.
  # file:: File to generate the prototype for.  If it is .h file, it
  #        is assumed that the corresponding .c file will contain
  #        the function definition.
  def self.cproto(file)
    require 'etool/vimfilt'

    file   = file.sub(/^\.\//, '')
    cfile  = file.sub(/\.[ch]$/, '.c')
    ofile  = file.sub(/\.[ch]$/, '.o')
    result = []
    raise "Can't find c file: #{cfile}" unless File.exist?(cfile)
    `make -nW #{cfile} #{ofile} 2>/dev/null`.split("\n").each do |l|
      next unless l =~ /#{cfile}/
      l = l.sub(/-c\s+/, '').sub(/-o\s+\S+/, '').sub(/^\S+/, '')
      result = `cproto -e #{l}`.split("\n").map do |cl|
        cl.sub(/\s+enum enum_errDescrValues/, ' MSTATUS')
      end
      result.shift
    end
    result = result.sort{|a,b|
      fa = a.split[2].gsub(/\*/,'')
      fb = b.split[2].gsub(/\*/,'')
      fa <=> fb
    }
    TextFilter.wrap(TextFilter.alignColumn(result, 2), 78, 24)
  end

  def self.indent(file)
    require 'etool/vimfilt'

    filterFile(file) do |input|
      TextFilter.indent(input)
    end
  end

  def self.mk_autoload(ofile, *files)
    File.open(ofile, "w") do |fod|
      fod.puts <<EOF
function __loading_ {
  typeset file=$1 func=$2; shift 2

  #echo "+Loading $func from $file" >&2
  unset -f $func
  . $file
  export -f $func
  $func "$@"
}
export -f __loading_
EOF
      fset      = {}
      tooldir   = File.expand_path(ENV['EM_TOOL_DIR'])
      emtooldir = ENV['EM_TOOL_DIR'] ?
                  File.expand_path(ENV['EM_TOOL_DIR']) : nil
      files.each do |file|
        file  = File.expand_path(file)
        Plog.info "Processing #{file}"
        File.grep(file, /^\s*function\s/).each do |l|
          f = l.split[1]
          fset[f] = file
        end
      end
      fset.keys.sort.each do |f|
        file = fset[f]
        # The auto is kind of a hack for now b/c of local deployment
        wfile = file.sub(/(\/auto)?#{tooldir}(\.hg)?/, '$EM_TOOL_DIR')
        if emtooldir
          wfile.sub!(/#{emtooldir}/, '$EM_TOOL_DIR')
        end
        fod.puts <<EOF
function #{f} {
  __loading_ #{wfile} #{f} "$@"
}
export -f #{f}
EOF
      end
      true
    end
  end

  def self.script2pod(file)
    script  = File.read(file).split("\n")

    inlines = []
    collect = false
    script.each do |l|
      if collect
        if l =~ /^#=end/
          inlines << "=back"
          collect = false
        else
          if l =~ /^#/
            case l
            when /^#\s?:\s*/
              inlines << "=item #{$'}"
            when /^#=\s*([A-Z])/
              inlines << "=head1 #{$1}#{$'}"
            when /^#==\s*([A-Z])/
              inlines << "=head2 #{$1}#{$'}"
            else
              inlines << l.sub(/^#\s?/, "")
            end
          end
        end
      else
        case l
        when /^#=begin/
          collect = true
          inlines << "=over"
        when /^#\s*@Use:\s*/
          inlines << "=head2 #{$'}"
        when /^#\s*@Desr?:\s*/
          inlines.concat(["=over", $', "=back"])
        end
      end
    end

    here     = 0
    endblock = []
    script.each do |l|
      if l =~ /^=head/
        endblock = script[here..-1]
        break
      elsif l =~ /^=begin/
        endblock = script[here+1..-1]
        break
      end
      here += 1
    end

    istag, isblank = false, false, false
    (endblock + inlines).each do |l|
      if l =~ /^(=+)([A-Z])/
        l = "=head#{$1.length} #{$2}#{$'}"
      end
      if istag
        if (l !~ /^\s*$/)
          puts ""
          isblank = true
        end
        istag = false
      end
      if l =~ /^=/
        istag = true
      end
      puts "" if (istag && !isblank)
      isblank = (l =~ /^\s*$/)
      puts l
    end
    true
  end

  class << self
    private
    # A generic file filter function.
    def filterFile(file)
      input  = File.read(file)
      output = yield(input)
      if input == output
        Plog.info("File does not change.  Skip")
        return false
      end
      File.unlink("#{file}.bak") if File.exist?("#{file}.old")
      File.rename(file, "#{file}.bak")
      File.catto(file, output)
      Plog.info("Format to #{file}.  Original is in #{file}.old")
      true
    end
  end
end

if (__FILE__ == $0)
  ShHelper.handleCli
end

=begin
=end
