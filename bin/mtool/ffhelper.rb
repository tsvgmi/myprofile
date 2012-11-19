#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        webpass.rb
# Date:        Wed Nov 07 09:23:03 PST 2007
# $Id: ffhelper.rb 6 2010-11-26 10:59:34Z tvuong $
#---------------------------------------------------------------------------
#+++
require File.dirname(__FILE__) + "/../../etc/toolenv"
require 'yaml'
require 'fileutils'
require 'mtool/core'
require 'mtool/mp3file'

class HarvestFile
  def initialize(sfile)
    @sfile = sfile
    @ssize = 0
  end

  def has_changed?
    newsize = File.size(@sfile)
    if newsize != @ssize
      #Plog.info "#{@sfile} chages from #{@ssize} to #{newsize}"
      STDERR.print "F"
      STDERR.flush
      @ssize = newsize
      return true
    end
    Plog.info "#{@sfile} stays at #{@ssize}"
    return false
  end

  @@wlist = {}
  def self.check_files(files)
    files.each do |afile|
      unless @@wlist[afile]
        @@wlist[afile] = self.new(afile)
      end
      unless @@wlist[afile].has_changed?
        yield afile
      end
    end
  end
end

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


  def self.get_typedname(ddir, ftype)
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

  def self.set_dname(file, description)
    title, artist, album = description.split(/\s*-\s*/)
    m3info = Mp3File.new(file)
    m3info.tag.title  = title.gsub(/\'/, '')
    m3info.tag.artist = artist if artist
    m3info.tag.album  = album  if album
    m3info.close
    if title && artist
      dfile = "#{title}-#{artist}.mp3"
    else
      dfile = "#{title}.mp3"
    end
    if dfile != file
      FileUtils.move(file, dfile, :verbose=>true)
    end
  end

  def self.get_dname(ddir, file, ftype)
    if ftype == 'mp3'
      m3info = Mp3File.new(file)
      fname   = m3info.tag['title']
      artist  = m3info.tag['artist'] || 'unknown'
      brate   = m3info.bitrate
      ddir = "#{ddir}/#{artist}"
      unless test(?d, ddir)
        FileUtils.mkdir_p(ddir)
      end
      return "#{ddir}/#{fname.strip}-#{brate}.#{ftype}"
    end
    get_typedname(ddir, ftype)
  end

  def self._harvest(scandir, ftypes)
    here = Dir.pwd
    Dir.chdir(scandir) do
      fcount = 0
      # First time, just keep track of file and size
      ftypes.each do |ftype|
        ptn    = FilePtn[ftype]
        unless ptn
          Plog.error "File type #{ftype} not supported - need identification"
          next
        end
        fsizes = {}
        flist  = `find . -type f | xargs file`.split("\n")
        next if flist.empty?
        flist = flist.grep(/#{ptn}/).map do |line|
          line.chomp.sub(/:.*$/, '')
        end
        HarvestFile.check_files(flist) do |file|
          dfile = get_dname(here, file, ftype)
          next unless dfile
          if getOption(:copy)
            FileUtils.cp(file, dfile, :verbose=>true)
          else
            Plog.info "Moving #{file} to #{dfile}"
            begin
              FileUtils.move(file, dfile)
              send_notifier "#{File.basename(dfile)} collected"
            rescue ArgumentError
              dfile = get_typedname(here, ftype)
              FileUtils.move(file, dfile)
              send_notifier "#{File.basename(dfile)} collected"
            rescue => errmsg
              p errmsg
            end
          end
        end
      end
    end
  end

  def self.send_notifier(msg)
    Pf.system "terminal-notifier -message '#{msg}' -title 'Firefox' -open #{Dir.pwd} 2>/dev/null"
  end

  def self.harvest(scandir, *ftypes)
    if getOption(:server)
      while true
        _harvest(scandir, ftypes)
        STDERR.print "."
        STDERR.flush
        sleep(5)
      end
    else
      _harvest(scandir, ftypes)
    end
  end
end

if (__FILE__ == $0)
  FirefoxHelper.handleCli(
        ['--copy',   '-k', 0],
        ['--notify', '-n', 0],
        ['--server', '-s', 0],
        ['--wait',   '-w', 1]
  )
end


