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
require 'tempfile'
require 'mtool/core'
require 'mtool/mp3file'

class HarvestFile
  def initialize(sfile, ftype, options = {})
    @sfile   = sfile
    @ftype   = ftype
    @options = options
    @ssize   = 0
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

  def get_dest_name(ddir)
    if @ftype == 'mp3'
      m3info = Mp3File.new(@sfile)
      puts m3info.to_yaml if @options[:verbose]
      fname  = m3info.tag['title']
      artist = m3info.tag['artist'] || 'unknown'
      artist = artist.sub(/,.*$/, '')
      album  = m3info.tag['album'] || 'unknown'
      brate  = m3info.bitrate
      ddir   = "#{ddir}/#{artist}/#{album}"
      return "#{ddir}/#{fname.strip}-#{brate}.#{@ftype}"
    else
      count = 0
      while true
        dfile = "#{ddir}/#{@ftype}-#{count}.#{@ftype}"
        unless test(?f, dfile)
          return dfile
        end
        count += 1
      end
    end
    return nil
  end

  def self_organize
    here = @options[:destdir] || Dir.pwd
    dfile = get_dest_name(here)
    next unless dfile
    unless test(?d, File.dirname(dfile))
      FileUtils.mkdir_p(File.dirname(dfile))
    end
    if @options[:copy]
      FileUtils.cp(@sfile, dfile, :verbose=>true)
    else
      Plog.info "Moving #{@sfile} to #{dfile}"
      begin
        FileUtils.move(@sfile, dfile)
        self.class.send_notifier "#{File.basename(dfile)} collected"
      rescue => errmsg
        p errmsg
      end
    end
  end

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

  @@filetypes = {}
  def self.find_matching_files(ftype, options = {})
    unless FilePtn[ftype]
      raise "File type #{ftype} not supported - need identification"
    end

    current_files = `find . -type f`.split("\n")
    cache_list    = @@filetypes.keys
    new_list      = current_files - cache_list
    
    purged_list = cache_list - current_files
    if purged_list.size > 0
      purged_list.each do |afile|
        @@filetypes.delete(afile)
      end
    end

    Plog.info "Found #{new_list.size} files" if options[:verbose]
    tmpf      = Tempfile.new("ffhelper")
    tmpf.puts(new_list.join("\n"))
    tmpf.close

    `cat #{tmpf.path} | xargs file`.split("\n").each do |line|
      file, type = line.split(/:\s+/, 2)
      @@filetypes[file] = type
    end

    flist = current_files.select do |afile|
      @@filetypes[afile] =~ /#{FilePtn[ftype]}/
    end

    flist
  end

  def self.send_notifier(msg)
    Pf.system "terminal-notifier -message '#{msg}' -title 'Firefox' -open #{Dir.pwd} 2>/dev/null"
  end

  @@wlist = {}
  def self.check_files(ftype, files, options = {})
    files.each do |afile|
      unless wfile = @@wlist[afile]
        wfile = @@wlist[afile] = self.new(afile, ftype, options)
      end
      unless wfile.has_changed?
        wfile.self_organize
      end
    end
  end
end

class FirefoxHelper
  extendCli __FILE__

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

  def self._harvest(scandir, ftypes)
    options = getOption
    options[:destdir] ||= Dir.pwd
    Dir.chdir(scandir) do
      ftypes.each do |ftype|
        fsizes = {}
        flist  = HarvestFile.find_matching_files(ftype, options)
        HarvestFile.check_files(ftype, flist, options)
      end
    end
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

  def self.self_organize(ftype)
    Dir.glob("*.#{ftype}").each do |afile|
      HarvestFile.new(afile, ftype, getOption).self_organize
    end
    true
  end
end

if (__FILE__ == $0)
  FirefoxHelper.handleCli(
        ['--destdir', '-d', 1],
        ['--copy',    '-k', 0],
        ['--notify',  '-n', 0],
        ['--server',  '-s', 0],
        ['--size',    '-S', 1],
        ['--verbose', '-v', 0],
        ['--wait',    '-w', 1]
  )
end


