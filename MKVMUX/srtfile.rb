#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        vnc.rb
# $Id: lyscanner.rb 6 2010-11-26 10:59:34Z tvuong $
#---------------------------------------------------------------------------
#+++
require File.dirname(__FILE__) + "/../../etc/toolenv"
require 'fileutils'
require 'mtool/core'

VideoExt = Regexp.new(/\.(avi|divx|mp4|mkv|flv)$/)

module SrtTime
  refine String do
    def to_ms
      hr, min, sec, msec = self.split(/[:,]/)
      hr.to_i*3_600_000 + min.to_i*60_000 + sec.to_i*1000 + msec.to_i
    end
  end

  refine Integer do
    def to_time_s
      hr   = self / 3_600_000
      min  = (self / 60_000) % 60
      sec  = (self / 1000) % 60
      msec = self % 1000
      "%02d:%02d:%02d,%03d" % [hr, min, sec, msec]
    end
  end
end

module SrtFile
  class SrtFile
    using SrtTime

    attr_reader :content

    def initialize(ifile, options={})
      require 'yaml'

      #@content = File.read(ifile).split(/\r\n(\r\n)+/m)
      @content = File.read(ifile).gsub(/\r/m, '').split(/\n\n+/m).map{|p|
        count, stime, tmp, etime, dialog = p.strip.split(' ', 5)
        [stime.to_ms, etime.to_ms, dialog]
      }
      #puts @content.to_yaml
    end
    
    def time_shift(offset_ms)
      new_content = []
      offset_ms   = offset_ms.to_i
      @content.each do |stime, etime, dialog|
        #stime = (stime * 0.8).to_i
        #etime = (etime * 0.8).to_i
        new_content << [stime+offset_ms, etime+offset_ms, dialog]
      end
      @content = new_content
      #puts @content.to_yaml
      self
    end

    def write(ofile)
      count = 1
      ofid  = File.open(ofile, "w")
      @content.each do |stime, etime, dialog|
        ofid.puts <<EOF
#{count}
#{stime.to_time_s} -> #{etime.to_time_s}
#{dialog}

EOF
        count += 1
      end
      ofid.close
      Plog.info "#{ofile} written"
      self
    end
  end

  class Main
    extendCli __FILE__

    # offset in ms
    def self.time_shift(ifile, offset, ofile=nil)
      options = getOption
      ofile ||= ifile.sub(/\.srt$/, '-new.srt')
      if odir = options[:odir]
        ofile = File.join(odir, File.basename(ofile))
      end
      if offset =~ /^m/
        offset = $'.to_f * (-1000)
      else
        offset = offset.to_f * 1000
      end
      SrtFile.new(ifile, options).time_shift(offset).write(ofile)
      true
    end
  end
end

if (__FILE__ == $0)
  SrtFile::Main.handleCli(
    ['--backup', '-b', 0],
    ['--dryrun', '-n', 0],
    ['--force',  '-f', 0],
    ['--odir',   '-d', 1]
  )
end

