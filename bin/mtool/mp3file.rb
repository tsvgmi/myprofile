#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        webpass.rb
# Date:        Wed Nov 07 09:23:03 PST 2007
# $Id: mp3file.rb 6 2010-11-26 10:59:34Z tvuong $
#---------------------------------------------------------------------------
#+++
require File.dirname(__FILE__) + "/../../etc/toolenv"
require 'mtool/core'

class Mp4File
  def initialize(file, options = {})
    require 'mp4info'

    @options = options
    @mp4info = MP4Info.open(file)
  end

  def method_missing(symbol, *args)
    @mp4info.send(symbol, *args)
  end

  def get_image
    unless @mp4info
      return [nil, nil]
    end
    #puts @mp4info.to_yaml
    if imgdata = @mp4info.COVR
      ["xxx", imgdata]
    else
      [nil, nil]
    end
  end
end

class Mp3File
  def initialize(file, options = {})
    require 'mp3info'

    @options = options
    begin
      @mp3info = Mp3Info.open(file, :encoding => 'utf-8')
    rescue Mp3InfoError => errmsg
      p errmsg
    end
  end

  def method_missing(symbol, *args)
    @mp3info.send(symbol, *args)
  end

  def get_image
    unless @mp3info
      return [nil, nil]
    end
    #puts @mp3info.to_yaml
    if imgdata = @mp3info.tag2['APIC']
      if imgdata =~ /image\/([a-zA-Z0-9_]+)/
        itype = $1.downcase
        hdrsize = itype.size + 10
        [itype, imgdata[hdrsize..-1]]
      else
        ["xxx", imgdata]
      end
    elsif imgdata = @mp3info.tag2['PIC']
      if imgdata.class == Array
        imgdata = imgdata.first
      end
      itype   = imgdata[1..3].downcase
      hdrsize = 6
      [itype, imgdata[hdrsize..-1]]
    else
      [nil, nil]
    end
  end
end

class Mp3Shell
  extendCli __FILE__

  def initialize(file, options = nil)
    @file    = file
    @options = options || Mp3Shell.getOption || {}
    case file
    when /\.m4a$/
      @info = Mp4File.new(file, @options)
    else
      @info = Mp3File.new(file, @options)
    end
  end

  def mk_thumbnail(ofile, size)
    itype, image = @info.get_image
    unless itype
      Plog.info "No image found for #{@file}" if @options[:verbose]
      return false
    end
    dfile = "tempout.#{itype}"
    open(dfile, "w") do |fod|
      fod.write(image)
    end
    Pf.system("convert '#{dfile}' -adaptive-resize #{size} '#{ofile}'",
        @options[:verbose])
    FileUtils.remove(dfile, :verbose=>true)
    true
  end

  def self.set_properties(*files)
    files.each do |afile|
      bname = File.basename(afile).sub(/\..mp3$/, '')
      track, title, artist = bname.split(/\s*[-\.]\s*/)
      next unless artist
      if title =~ /\s*\(/
        title = $`
        composer = $'.sub(/\).*$/, '')
      else
        composer = nil
      end
      Plog.info "#{title} - #{artist} - #{composer} - #{track}"
      mp3file = Mp3File.new(afile)
      if mp3file.tag.title != title
        mp3file.tag.title    = title
        mp3file.tag.artist   = artist
        mp3file.tag.track    = track.to_i
        if composer
          mp3file.tag.composer   = composer
        end
      end
      mp3file.close
    end
    true
  end
end

if (__FILE__ == $0)
  Mp3Shell.handleCli(
        ['--verbose', '-v', 0])
end

