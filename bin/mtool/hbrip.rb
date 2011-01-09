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

class HbRip
  extendCli __FILE__

  def initialize(source, name = nil)
    @isource = source
    @name    = name || \
        File.basename(@isource.sub(/VIDEO_TS$/, '')).gsub(/[^A-Z0-9_]/i, '_')
    get_content
  end

  def get_content
    dfile = "#{@name}.yml"
    if !HbRip.getOption(:force) && test(?f, dfile)
      @data    = YAML.load_file(dfile)
    else
      Plog.info "Getting content from #{@name}"
      cmd     = "HandBrakeCLI -i '#{@isource}' --title 0"
      p cmd
      content = `#{cmd} 2>&1`
      tracks   = []
      chapters = []
      badchaps = []
      title    = ""
      size     = ""
      content.split("\n").each do |line|
        if line =~ /^\+ title (\d+)/
          #puts "TITLE: #{line}"
          title = $1
        elsif line =~ /^  \+ size: (\S+),/
          #puts "SIZE: #{line}"
          size = $1
        elsif line =~ /^    \+ (\d+): cells.*duration (\S+)/
          #puts "CELLS: #{line}"
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
        :name  => @name,
        :input => @isource,
        :audio => tracks,
        :albumn => nil,
        :artist => nil,
        :bitrate => nil,
        :size  => size,
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
  end

  def rip_all
    encopt  = HbRip.encode_option('highdvd')
    @data[:chapters].select do |title, chapter, duration|
      duration > "00:01:00"
    end.each do |title, chapter, duration|
      _rip_chapter(chapter, title, encopt)
    end
  end

  def rip_dvd
    encopt  = HbRip.encode_option('highdvd')
    tsize   = {}
    @data[:chapters].select do |title, chapter, duration|
      duration > "00:01:00"
    end.each do |title, chapter, duration|
      puts "T: #{title} C: #{chapter} D: #{duration}"
      seconds = 0
      duration.split(/:/).each do |f|
        seconds = seconds*60 + f.to_i
      end
      tsize[title] ||= 0
      tsize[title] += seconds
    end
    p tsize
    maxtitle, duration = tsize.max
    _rip_chapter(0, maxtitle.to_i, encopt)
  end

  private
  def output_file(title, chapter, name = nil, artist = nil)
    otype = HbRip.getOption(:otype) || "mkv"
    if !name
      "#{@data[:name]}-#{title}-#{chapter}.#{otype}"
    else
      albumn = @data[:albumn]
      artist ||= @data[:artist]
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
    elsif (title != 0)
      "HandBrakeCLI --title #{title} #{encopt}"
    else
      "HandBrakeCLI #{encopt}"
    end
    HbRip.run_handbrake(cmd, @data[:input], ofile, "#{@data[:name]}.err")
  end

  public
  def rename_files
    if (albumn = @data[:albumn]) == nil
      p @data
      Plog.warn "#{@name}: no album data defined."
      return
    end
    artist = @data[:artist]
    @data[:chapters].each do |t, c, d, name, artist|
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
    title  ||= @data[:chapters][0][0]
    rchapters = []
    chapters.each do |arange|
      if arange =~ /-/
        rstart, rend = arange.split(/-/)
        rchapters.concat((rstart..rend).to_a)
      else
        rchapters << arange
      end
    end
    encopt  = HbRip.encode_option('highdvd')
    rchapters.each do |achapt|
      _rip_chapter(achapt, title, encopt)
    end
  end

  def self.to_divx(srcfile)
    encopt  = encode_option('divx')
    ofile   = srcfile.gsub(/\s+/, '').sub(/\..*$/, '.mp4')
    errfile = srcfile.gsub(/\s+/, '').sub(/\..*$/, '.err')
    if !getOption(:force) && test(?f, ofile)
      Plog.info "#{ofile} exists.  Skip"
      return
    end
    cmd = "HandBrakeCLI #{encopt}"
    run_handbrake(cmd, srcfile, ofile, errfile)
  end

  def self.encode_option(enctype = 'highdvd')
    profile = getOption(:profile) || enctype
    config  = YAML.load_file("#{ENV['HOME']}/.tool/hbrip.conf")
    # The baseline
    encopt  = "-b 4000"

    # The config
    if econfig = config[profile]
      encopt += " #{econfig}"
    end

    # The override
    if brate = getOption(:brate)
      encopt += " -b #{brate}"
    end
    encopt
  end

  def self.run_handbrake(cmd, sfile, ofile, errfile)
    if test(?f, errfile)
      FileUtils.mv(errfile, "#{errfile}.old", :force=>true, :verbose=>true)
    end
    Pf.system("#{cmd} -i '#{sfile}' -o 'tmp-#{ofile}' 2>#{errfile}", 1)
    FileUtils.move("tmp-#{ofile}", ofile, :verbose=>true, :force=>true)
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
    new(input, getOption(:name))
  end
end

if (__FILE__ == $0)
  HbRip.handleCli(
                  ['--brate',   '-b', 1],
                  ['--force',   '-f', 0],
                  ['--input',   '-i', 1],
                  ['--name',    '-n', 1],
                  ['--otype',   '-o', 1],
                  ['--profile', '-p', 1])
end

