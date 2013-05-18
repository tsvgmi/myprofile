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

  # Pull the lyrics from mp3, put in an editor, monitor editing and save back
  # if changes are deteced
  def edit(edfile = nil, wait = true)
    unless lyrics = @track.lyrics
      Plog.debug "No lyrics found for #{@track.name} to edit"
      return false
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
    ITune::ITuneHelper.notify "Editing lyrics for #{@track.name}"
    cmd = @options[:editor] ? "open -a #{@options[:editor]}" : "open"
    unless wait
      Pf.system("#{cmd} #{@song_path}", 1)
    else
      Pf.system("#{cmd} -FnWt #{@song_path}", 1)
      check_and_update
    end
    show_in_browser(@song_path)
    true
  end
end

