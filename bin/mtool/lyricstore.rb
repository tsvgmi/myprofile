#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        lyricstore.rb
# Date:        Sat Mar 30 21:12:38 -0700 2013
# $Id$
#---------------------------------------------------------------------------
#++
require 'fileutils'
require 'yaml'
require 'mtool/lyricsource'
require 'mtool/core'

class LyricCache
  def initialize(src, storedir, track, options = {})
    require 'mtool/lyricsource'

    @app      = ITune::ITuneApp.app
    @storedir = storedir
    @track    = track
    @options  = options
    @source   = src
    @kname    = @track.name_clean

    unless test(?d, storedir)
      FileUtils.mkdir_p(storedir, :verbose=>true)
    end

    @lysource = LyricSource.get(@source, @options)
  end

  private
  def wfilename(composer = nil)
    komposer = ITune::ITuneTrack.name_clean(composer || @track[:composer])
    if !komposer || komposer.empty?
      komposer = "unknown"
    end
    _wfilename = "#{@storedir}/#{komposer}/#{@kname}.2txt"
    unless test(?d, File.dirname(_wfilename))
      FileUtils.mkpath(File.dirname(_wfilename))
    end
    _wfilename
  end

  def write_to_cache(content)
    cachefile = wfilename(content[:composer].first)
    if content
      fod = File.open(cachefile, "w")
      fod.puts(content.to_yaml)
      fod.close
      Plog.info "Writing #{@track.name} to #{cachefile}"
    else
      if test(?f, cachefile)
        FileUtils.remove(cachefile, :force=>true, :verbose=>true)
      end
    end
  end

  public
  def get_lyric
    cachefile = wfilename
    if @options[:force] || !test(?f, cachefile)
      return download_lyric
    else
      Plog.debug "Loading from #{cachefile}"
      return YAML.load_file(cachefile)
    end
  end

  def download_lyric
    @track.reveal
    if content = @lysource.auto_get(@track)
      write_to_cache(content)
    end
    return content
  end

  def track_to_cache
    unless @options[:force]
      wfile = self.wfilename
      return if test(?f, wfile)
    end
    write_to_cache({
      :content  => @track[:lyrics],
      :artist   => [@track[:artist]],
      :composer => [@track[:composer]]
    })
  end

  def clear_lyric
    Plog.info "#{@kname}. Clearing lyrics"
    @track.lyrics  = ""
    @track.comment = ""
    write_to_cache(nil)
    return true
  end

  def edit(edfile = nil, wait = true)
    if @options[:store]
      wset = [get_value, @track.lyrics]
    else
      wset = [@track.lyrics, get_value]
    end

    lyrics = nil
    wset.each do |alyrics|
      unless alyrics.strip.empty?
        lyrics = alyrics.strip
        break
      end
    end

    unless lyrics
      Plog.debug "No lyrics found for #{@track.name} to edit"
      return false
    end

    # Cache it
    if get_value.empty?
      set_value(lyrics)
    end

    unless edfile
      # Need to keep the tmp file around, or it get wiped
      @fod = Tempfile.new("it")
      @fod.puts lyrics
      @fod.close
      @song_path = @fod.path
    else
      fod = File.open(edfile, "w")
      fod.puts lyrics
      fod.close
      @song_path = edfile
    end

    @start_time = Time.now
    ITuneHelper.notify "Editing lyrics for #{@track.name}"
    cmd = @options[:editor] ? "open -a #{@options[:editor]}" : "open"
    unless wait
      Pf.system("#{cmd} #{@song_path}", 1)
    else
      Pf.system("#{cmd} -FnWt #{@song_path}", 1)
      check_and_update
    end
    true
  end

  def check_and_update
    if File.mtime(@song_path) > @start_time
      content = File.read(@song_path)
      ITuneHelper.notify "Setting lyrics for #{@track.name} into track"
      self.set_value(content)
      if content.strip.empty?
        clear_track
      else
        store_to_track(:force=>true)
      end
      @start_time = Time.now
    end
    true
  end

  # Just wait around for track change and
  def self.edit_server(exdir = "./lyrics", options = {})
    require 'tempfile'

    curname, edsong = nil, nil
    folder   = ITuneFolder.new("play", options)
    tmpfile  = Tempfile.new("it")
    while true
      if btrack = folder.get_tracks(true).first
        if !curname || (btrack.name != curname)
          Plog.debug "Detect track change to '#{btrack.name}'"
          curname = btrack.name
          chksong = new("console", exdir, btrack, options)
          if chksong.edit(tmpfile.path, false)
            edsong = chksong
          end
        end
      end
      _edcheck([edsong], options)
    end
    true
  end

  def self._edcheck(edsongs, options)
    interval = (options[:interval] || 5).to_i
    Plog.debug("Waiting for edit ...")
    sleep(interval)
    edsongs.each do |edsong|
      edsong.check_and_update if edsong
    end
  end
end

