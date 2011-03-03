#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        hbrip.rb
# Date:        Wed Nov 07 09:23:03 PST 2007
# $Id: hbrip.rb 11 2011-01-01 21:01:11Z tvuong $
#---------------------------------------------------------------------------
#+++
require File.dirname(__FILE__) + "/../../etc/toolenv"
require 'fileutils'
require 'mtool/core'
require 'yaml'

class VideoFile
  attr_reader :name, :data

  def initialize(source, options = {})
    @source  = source
    @options = options
    if source =~ /VIDEO_TS$/
      @name = File.basename(source.sub(/VIDEO_TS$/, '')).gsub(/[^A-Z0-9_]/i, '_')
    else
      @name = File.basename(source)
    end
    @name = @name.sub(/\.[^.]+$/, '')
    get_content
  end

  def get_content
    wdir  = @options[:wdir] || "."
    dfile = "#{wdir}/#{@name}.yml"
    if !@options[:force] && test(?f, dfile)
      @data    = YAML.load_file(dfile)
    else
      Plog.info "Getting content from #{@name}"
      cmd     = "HandBrakeCLI -i '#{@source}' --title 0"
      if @options[:debug]
        content = `#{cmd} 2>&1 | tee /dev/tty`
      else
        content = `#{cmd} 2>&1 | tee title.log`
      end
      if content == ""
        raise "Can't get content from #{@name}"
      end
      tracks   = []
      chapters = []
      badchaps = []
      title    = ""
      size     = ""
      bitrate  = nil
      content.split("\n").each do |line|
        if line =~ /^\+ title (\d+)/
          title = $1
        elsif line =~ /^  \+ size: (\S+),/
          size = $1
        elsif line =~ /bitrate: (\d+)/
          bitrate = $1
          p bitrate
        elsif line =~ /bitrate (\d+)/
          bitrate = $1
        elsif line =~ /^    \+ (\d+): cells.*duration (\S+)/
          chapter = $1
          duration = $2
          if duration > "00:01:00"
            chapters << [title, chapter, duration]
          else
            badchaps << [title, chapter, duration]
          end
        elsif line =~ /^    \+ (\d+),.*Hz/
          tracks << line.strip
        end
      end
      @data = {
        :name        => @name,
        :input       => @source,
        :audio       => tracks,
        :albumn      => nil,
        :artist      => nil,
        :bitrate     => bitrate,
        :size        => size,
        :chapters    => chapters,
        :badchapters => badchaps
      }
      open(dfile, "w") do |fod|
        fod.puts <<EOI
#
# Please customize - albumn, artist (optional), and bitrate (4000k defaults)
# Add in song and artist on 4th field of chapter (separated by '-')
# Example:
# - - "1"
#   - "1"
#   - "00:04:46"
#   - Mua Thu Cho Em - Le Huynh
# ------
EOI
        fod.puts @data.to_yaml
      end
    end
    @data
  end

  def encode_option(profile)
    config = YAML.load_file("#{ENV['HOME']}/.tool/hbrip.conf")
    brate  = (@data[:bitrate] || 2000).to_i
    if mrate = @options[:mrate]
      if brate > mrate.to_i
        brate = mrate.to_i
        end
    end
    encopt = "-b #{brate}"
    if econfig = config[profile]
      encopt += " #{econfig}"
    end

    # The override
    if brate = @options[:brate]
      encopt += " -b #{brate}"
    end
    encopt
  end

  def to_divx
    encopt  = encode_option('divx')
    ofile   = @source.sub(/\.[^.]+$/, '.mp4')
    if @source == ofile
      raise "Cannot re-encode to the same file"
    end
    if !@options[:force] && test(?f, ofile)
      Plog.info "#{ofile} exists.  Skip"
      return
    end
    cmd = "HandBrakeCLI #{encopt}"
    HbRip.run_handbrake(cmd, @source, ofile)
  end

  def method_missing(method, *argv)
    if argv.size == 0
      @data[method]
    else
      raise "Unknown method: #{method} - #{argv}"
    end
  end
end

class HbRip
  extendCli __FILE__

  def initialize(source)
    @video = VideoFile.new(source, HbRip.getOption)
  end

  def rip_all
    encopt  = @video.encode_option('highdvd')
    @video.chapters.select do |title, chapter, duration|
      duration > "00:01:00"
    end.each do |title, chapter, duration|
      _rip_chapter(chapter, title, encopt)
    end
  end

  def rip_dvd(maxtitle = -1)
    encopt  = @video.encode_option('highdvd')
    _rip_chapter(0,  maxtitle.to_i, encopt)
  end

  private
  def output_file(title, chapter, name = nil, artist = nil)
    otype = HbRip.getOption(:otype) || "mkv"
    if !name
      "#{@video.name}-#{title}-#{chapter}.#{otype}"
    else
      albumn = @video.albumn
      artist ||= @video.artist
      unless albumn
        EmLog.warn "No album data defined.  Add it into yml file"
        return nil
      end
      if artist
        "#{name} - #{artist} - #{albumn}.#{otype}"
      else
        "#{name} - #{albumn}.#{otype}"
      end
    end
  end

  def _rip_chapter(chapter, title, encopt)
    ofile   = output_file(title, chapter)
    if !HbRip.getOption(:force) && test(?f, ofile)
      Plog.info "#{ofile} exists.  Skip"
      return
    end
    cmd = if (chapter != 0) && (title != 0)
      "HandBrakeCLI --title #{title} --chapter #{chapter} #{encopt}"
    elsif (title < 0)
      "HandBrakeCLI --longest #{encopt}"
    elsif (title != 0)
      "HandBrakeCLI --title #{title} #{encopt}"
    else
      "HandBrakeCLI #{encopt}"
    end
    HbRip.run_handbrake(cmd, @video.input, ofile)
  end

  public
  def rename_files
    if (albumn = @video.albumn) == nil
      Plog.warn "#{@video.name}: no album data defined."
      return
    end
    artist = @video.artist
    @video.chapters.each do |t, c, d, name, artist|
      ofile = output_file(t, c)
      next unless test(?f, ofile)
      if !name
        Plog.info "No name defined for #{t}:#{c}"
        next
      end
      if (nfile = output_file(t, c, name, artist)) == nil
        next
      end
      FileUtils.mv(ofile, nfile, :verbose=>true)
    end
    true
  end

  # To support cmdline
  def rip_chapter(*chapters)
    title  ||= @video.chapters[0][0]
    rchapters = []
    chapters.each do |arange|
      if arange =~ /-/
        rstart, rend = arange.split(/-/)
        rchapters.concat((rstart..rend).to_a)
      else
        rchapters << arange
      end
    end
    encopt  = @video.encode_option('highdvd')
    rchapters.each do |achapt|
      _rip_chapter(achapt, title, encopt)
    end
  end

  def self.to_divx(files)
    options = getOption
    files.each do |afile|
      VideoFile.new(afile, options).to_divx
    end
    true
  end

  def self.to_divx_for_types(*types)
    opt = cliOptBuild
    types.each do |atype|
      `find . -name '*#{atype}'`.split("\n").each do |afile|
        cmd = "hbrip.rb #{opt} to_divx '#{afile}'"
        Pf.system(cmd, 1)
        break
      end
    end
  end

  def self.run_handbrake(cmd, sfile, ofile)
    wdir      = getOption(:wdir) || "/tmp"
    errfile   = wdir + "/" + File.basename(ofile).sub(/\.[^.]+$/, '.err')
    tmp_ofile = wdir + "/" + File.basename(ofile)
    if test(?f, errfile)
      FileUtils.mv(errfile, "#{errfile}.old", :force=>true, :verbose=>true)
    end
    if !Pf.system("#{cmd} -i '#{sfile}' -o '#{tmp_ofile}' 2>'#{errfile}'", 1) ||
       !test(?f, "#{tmp_ofile}")
      STDERR.puts File.read(errfile)
      growl_notify "Handbrake error for #{File.basename(ofile)}"
      return false
    end
    FileUtils.move("#{tmp_ofile}", ofile, :verbose=>true, :force=>true)
    growl_notify "Handbrake complete for #{File.basename(ofile)}"
    true
  end

  def self.growl_notify(msg)
    if getOption(:growl)
      Pf.system "growlnotify --sticky --appIcon Handbrake --message '#{msg}' 2>/dev/null"
    end
  end

  def self.cliNew
    unless input = getOption(:input)
      vlist = Dir.glob("/Volumes/*/VIDEO_TS")
      if vlist.size <= 0
        Plog.error "No DVD volume found"
        exit(1)
      end
      input = vlist.first
    end
    new(input)
  end
end

if (__FILE__ == $0)
  HbRip.handleCli(
                  ['--brate',   '-b', 1],
                  ['--debug',   '-d', 0],
                  ['--force',   '-f', 0],
                  ['--growl',   '-g', 0],
                  ['--input',   '-i', 1],
                  ['--mrate',   '-m', 1],
                  ['--otype',   '-o', 1],
                  ['--profile', '-p', 1],
                  ['--wdir',    '-w', 1])
end

