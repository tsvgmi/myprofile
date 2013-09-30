#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        vnc.rb
# $Id: lyscanner.rb 6 2010-11-26 10:59:34Z tvuong $
#---------------------------------------------------------------------------
#+++
require File.dirname(__FILE__) + "/../../etc/toolenv"
require 'fileutils'
require 'mtool/core'
require 'iconv'

VideoExt = Regexp.new(/\.(avi|divx|mp4|mkv)$/)

class VideoFile
  def initialize(vfile, options = {})
    @vfile   = vfile
    @bname   = @vfile.sub(VideoExt, '')
    @options = options
    # Make this instance var so it survive during lifetime of Videofile
    @subfile = nil
  end

  def mkv_file
    odir = @options[:odir] || "."
    unless test(?d, odir)
      FileUtils.mkpath(odir, verbose:true)
    end
    "#{odir}/#{@bname}.mkv"
  end

  def subtitle_file
    require 'tempfile'

    ic = Iconv.new('UTF-8//IGNORE', 'UTF-8')

    ['srt', 'eng.srt', 'idx'].each do |sub|
      subfile = "#{@bname}.#{sub}"
      if test(?f, subfile)
        if sub =~ /srt$/
          @subfile = Tempfile.new("srt")
          vcontent = ic.iconv(File.read(subfile) + ' ')[0..-2]
          vcontent.split("\n").each do |l|
            @subfile.puts l.chomp + " "
          end
          @subfile.close
          return @subfile.path
        else
          return subfile
        end
      end
    end
    nil
  end
end

class MKVMux
  extendCli __FILE__

  def self.check_and_move(input, output, *others)
    if test(?f, output) &&
      (File.size(output)*1.0 >= (File.size(input)*0.80))
      Plog.info "File generated to #{output} successfully"
      FileUtils.move(input, "#{input}.bak", verbose:true)
      others.each do |afile|
        FileUtils.move(afile, "#{afile}.bak", verbose:true)
      end
      if output =~ /\.new$/
        FileUtils.move(output, output.sub(/\.new$/, ''), verbose:true)
      end
      true
    else
      Plog.warn "Error generating #{output}.  Size is too small"
      false
    end
  end

  def self.join_multi(ptn = "")
    wset = {}
    cmd  = "find . -name '*#{ptn}*'"
    `#{cmd}`.split("\n").grep(/(cd|dvd)/i).sort.each do |afile|
      next unless afile =~ /\.(avi|divx|mp4|mkv)$/
      bname = File.dirname(afile) + "/" +
              File.basename(afile).gsub(/[-_\.]?(cd|dvd)\d+/i, '')
      wset[bname] ||= []
      wset[bname] << afile
    end
    wset.sort.each do |ofile, components|
      file0  = components.shift
      cplist = "'#{file0}'"
      components.each do |acomp|
        cplist << " '+#{acomp}'"
      end
      cmd = "mkvmerge --default-language en -o '#{ofile}.new' #{cplist}"
      Pf.system(cmd, 1)
      check_and_move(file0, "#{ofile}.new", *components)
    end
    true
  end

  def self.merge_subtitle(ptn = "")
    cmd     = "find . -name '*#{ptn}*'"
    options = getOption
    `#{cmd}`.split("\n").sort.each do |afile|
      next unless VideoExt.match(afile)
      video = VideoFile.new(afile, options)
      ofile = video.mkv_file
      if test(?f, ofile) && !options[:force]
        Plog.warn "MKV file found for #{afile}. skip"
        next
      end
      unless subfile = video.subtitle_file
        Plog.warn "Subtitle file for #{afile} not found.  Skip"
        next
      end
      ofile2   = ofile.gsub(/'/, "\\\\'")
      STDERR.puts({ofile:ofile, ofile2:ofile2}.inspect)
      afile2   = afile.gsub(/'/, "\\\\'")
      cmd = "mkvmerge --default-language en -o '#{ofile2}.new' '#{afile2}' '#{subfile}'"
      if options[:dryrun]
        Plog.info(cmd)
      else
        Pf.system(cmd, 1)
        check_and_move(afile, "#{ofile}.new", subfile)
      end
    end
    true
  end

end

if (__FILE__ == $0)
  MKVMux.handleCli(
    ['--dryrun', '-n', 0],
    ['--force',  '-f', 0],
    ['--odir',   '-d', 1]
  )
end

