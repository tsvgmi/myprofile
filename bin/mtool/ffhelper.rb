#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        webpass.rb
# Date:        Wed Nov 07 09:23:03 PST 2007
# $Id: ffhelper.rb 6 2010-11-26 10:59:34Z tvuong $
#---------------------------------------------------------------------------
#+++
require File.dirname(__FILE__) + "/../../etc/toolenv"
require 'yaml'
require 'mtool/core'
require 'mtool/mp3file'

class FirefoxHelper
  extendCli __FILE__

  FilePtn = {
    'mp3' => "Audio file|MPEG ADTS",
    'mp4' => "MPEG v4",
    'flv' => "Macromedia Flash data",
    'jpg' => "JPEG image data",
    'gif' => "GIF image data",
    'png' => "PNG image",
    'mid' => "MIDI data",
    'gz'  => "gzip compressed data"
  }


  def self.get_dname(ddir, file, ftype)
    if ftype == 'mp3'
      m3info = Mp3File.new(file)
      p m3info.tag
      fname  = m3info.tag['title']
      if fname
        return "#{ddir}/#{fname.strip}.#{ftype}"
      end
    end
    dfile = nil
    count = 0
    while true
      dfile = "#{ddir}/#{ftype}-#{count}.#{ftype}"
      unless test(?f, dfile)
        return dfile
      end
      count += 1
    end
    nil
  end

  def self._harvest(scandir, ftypes)
    require 'fileutils'

    here = Dir.pwd
    Dir.chdir(scandir) do
      fsets  = {}
      fcount = 0
      # First time, just keep track of file and size
      ftypes.each do |ftype|
        ptn    = FilePtn[ftype]
        fsizes = {}
        flist  = `find . -type f`.split("\n")
        if !flist.empty?
          flist.grep(/#{ptn}/).each do |line|
            #p line
            file = line.chomp.sub(/:.*$/, '')
            begin
              fsizes[file] = File.size(file)
              fcount += 1
            rescue Exception => errmsg
              p errmsg
            end
          end
          fsets[ftype] = fsizes
        end
      end
      if fcount <= 0
        Plog.info "No files to collect"
        return true
      end
      puts fsets.to_yaml

      interval = (getOption(:wait) || 3).to_i
      Plog.info "Wait #{interval}s for change to stop"
      sleep(interval)

      # After wake up, check to see if file change size and skip
      mcount  = 0
      pending = 0
      ftypes.each do |ftype|
        fsets[ftype].each do |file, size|
          begin
            newsize = File.size(file)
          rescue Exception => errmsg
            p errmsg
            next
          end
          if newsize == size
            dfile = get_dname(here, file, ftype)
            next unless dfile
            if getOption(:copy)
              FileUtils.cp(file, dfile, :verbose=>true)
            else
              FileUtils.move(file, dfile, :verbose=>true)
            end
            mcount += 1
          else
            Plog.info "#{file}: #{newsize} bytes.  Skip"
            pending += 1
          end
        end
      end
      return (pending <= 0)
    end
    true
  end

  def self.harvest(scandir, *ftypes)
    if getOption(:server)
      while true
        if _harvest(scandir, ftypes)
          sleep(5)
        end
      end
    else
      _harvest(scandir, ftypes)
    end
  end
end

if (__FILE__ == $0)
  FirefoxHelper.handleCli(
        ['--copy',   '-k', 0],
        ['--server', '-s', 0],
        ['--wait',   '-w', 1]
  )
end


