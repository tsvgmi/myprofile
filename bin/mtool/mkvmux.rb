#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        vnc.rb
# $Id: lyscanner.rb 6 2010-11-26 10:59:34Z tvuong $
#---------------------------------------------------------------------------
#+++
require File.dirname(__FILE__) + "/../../etc/toolenv"
require 'fileutils'
require 'mtool/core'

class VideoFile
  def initialize(vfile, options = {})
    @vfile   = vfile
    @bname   = @vfile.sub(/\.(avi|mp4)$/, '')
    @options = options
    # Make this instance var so it survive during lifetime of Videofile
    @subfile = nil
  end

  def mkv_file
    odir = @options[:odir] || "."
    "#{odir}/#{@bname}.mkv"
  end

  def subtitle_file
    require 'tempfile'

    ['srt', 'eng.srt', 'idx'].each do |sub|
      subfile = "#{@bname}.#{sub}"
      if test(?f, subfile)
        if sub == "srt"
          @subfile = Tempfile.new("srt")
          File.read(subfile).split("\n").each do |l|
            @subfile.puts l + " "
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
      (File.size(output)*1.0 >= (File.size(input)*0.90))
      Plog.info "File generated to #{output} successfully"
      FileUtils.move(input, "#{input}.bak", :verbose=>true)
      others.each do |afile|
        FileUtils.move(afile, "#{afile}.bak", :verbose=>true)
      end
      true
    else
      Plog.warn "Error generating #{output}.  Size is too small"
      false
    end
  end

  def self.join_multi(ptn = "")
    wset = {}
    cmd  = "find . -name '*#{ptn}*cd*' | sort"
    `#{cmd}`.split("\n").each do |afile|
      next unless afile =~ /\.(avi|mp4|mkv)$/
      bname = File.dirname(afile) + "/" +
              File.basename(afile).gsub(/-?cd\d+/, '')
      p afile
      wset[bname] ||= []
      wset[bname] << afile
    end
    wset.each do |ofile, components|
      file0  = components.shift
      cplist = "'#{file0}'"
      components.each do |acomp|
        cplist << " '+#{acomp}'"
      end
      cmd = "mkvmerge --default-language en -o '#{ofile}' #{cplist}"
      Pf.system(cmd, 1)
      check_and_move(file0, ofile, *components)
    end
    true
  end

  def self.merge_subtitle(ptn = "")
    cmd = "find . -name '*#{ptn}*' | sort"
    `#{cmd}`.split("\n").each do |afile|
      next unless afile =~ /\.(avi|mp4)$/
      video = VideoFile.new(afile, getOption)
      ofile = video.mkv_file
      if test(?f, ofile)
        Plog.warn "MKV file found for #{afile}. skip"
        next
      end
      unless subfile = video.subtitle_file
        Plog.warn "Subtitle file for #{afile} not found.  Skip"
        next
      end
      cmd = "mkvmerge --default-language en -o '#{ofile}' '#{afile}' '#{subfile}'"
      Pf.system(cmd, 1)
      check_and_move(afile, ofile, subfile)
    end
    true
  end

end

if (__FILE__ == $0)
  MKVMux.handleCli(
    ['--odir', '-d', 1]
  )
end

