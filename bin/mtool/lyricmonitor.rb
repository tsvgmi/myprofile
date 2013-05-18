#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        lyricstore.rb
# Date:        Sat Mar 30 21:12:38 -0700 2013
# $Id$
#---------------------------------------------------------------------------
#++
require 'fileutils'
require 'yaml'
require 'tempfile'
require 'mtool/core'
require 'mtool/itunehelp'
require 'mtool/mp3file'

module ITune
  class LyricMonitor
    extendCli __FILE__

    def initialize(itrack, options = {})
      @track     = itrack
      @options   = options
      if options[:edfile]
        @song_path = options[:edfile]
      else
        @fod       = Tempfile.new("mon")
        @song_path = @fod.path
      end
    end

    def edit
      unless lyrics = @track.lyrics
        Plog.debug "No lyrics found for #{@track.name} to edit"
        return false
      end

      File.open(@song_path, "w") do |fod|
        fod.puts(lyrics)
      end

      @start_time = Time.now
      ITuneHelper.notify "Editing lyrics for #{@track.name}"
      cmd = @options[:editor] ? "open -a #{@options[:editor]}" : "open"
      Pf.system("#{cmd} #{@song_path}", 1)
      show_in_browser(@song_path)
      true
    end

    # Check if an edited file is changed and update the track again
    def check_and_update
      if File.mtime(@song_path) > @start_time
        content = File.read(@song_path)
        ITuneHelper.notify "Setting lyrics for #{@track.name} into track"
        if content.strip == ""
          clear_lyric
        else
          set_lyric(content)
        end
        show_in_browser(@song_path)
        @start_time = File.mtime(@song_path)
      end
      true
    end

    # Note: Must past the edit file in argument.  Somehow track is not updated
    # correctly
    def show_in_browser(lfile)
      htfile = "/tmp/lyrics-out.html"
      begin
        mp3info = Mp3Shell.new(@track.location.path)
        awfile = mp3info.get_artwork("/tmp/artwork")
        if awfile && (File.size(awfile) > 1024)
          background = "background: url(#{awfile}) no-repeat center center fixed"
        else
          Plog.info "No image found for #{@track.name}.  Use gradient"
          background = "background-image: -webkit-gradient(linear, left top, right bottom, color-stop(0, #FFFFFF), color-stop(1, #00A3EF))"
        end
      rescue => errmsg
        p errmsg
      end
      File.open(htfile, "w") do |fod|
        fod.puts <<EOF
<html><head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
<title>#{@track.name} - #{@track.artist}</title>
<style type="text/css">
  html { 
    #{background};
    -webkit-background-size: cover;
    -moz-background-size: cover;
    -o-background-size: cover;
    background-size: cover;
  }
  .transbox {
    width:80%;
    margin:10% 10%;
    background-color:#ffffff;
    border:1px solid #888888;
    opacity:0.7;
    filter:alpha(opacity=70); /* For IE8 and earlier */
  }
</style>
</head>
<body><div class=transbox><center>
EOF
        
        fod.puts(File.read(lfile).gsub(/[\r\n]/, "<br/>"))
        fod.puts("</div></center></body></html>")
      end
      Pf.system("open -a Safari #{htfile}", 1)
    end

    def clear_lyric
      Plog.info "#{@track.name}. Clearing lyrics"
      @track.lyrics  = ""
      @track.comment = ""
    end

    def set_lyric(content)
      Plog.info "#{@track.name}. Setting lyrics"
      @track.lyrics  = content
      @track.comment = Time.now.strftime("%y.%m.%d.%H.%M.%S")
    end

    def self.edit_server(options=nil)
      require 'tempfile'

      options ||= getOption
      curname, edsong = nil, nil
      folder   = ITuneFolder.new("play", options)
      interval = (options[:interval] || 5).to_i
      # Use 1 tmpfile for edit, so the editor won't keep open new window
      # whenever the file is switched
      tmpf             = Tempfile.new("edt")
      options[:edfile] = tmpf.path
      while true
        if btrack = folder.get_tracks(true).first
          if !curname || (btrack.name != curname)
            Plog.debug "Detect track change to '#{btrack.name}'"
            curname = btrack.name
            chksong = self.new(btrack, options)
            if chksong.edit
              edsong = chksong
            end
          end
        end
        Plog.debug("Waiting for edit ...")
        sleep(interval)
        _check_for_changes(edsong)
      end
      true
    end

    def self._check_for_changes(*edsongs)
      edsongs.each do |edsong|
        edsong.check_and_update
      end
      check_source_change
    end
  end
end

@@_stime = Time.now
def check_source_change
  if File.mtime(__FILE__) > @@_stime
    Plog.info "Reloading #{__FILE__}"
    $0 = ''
    begin
      @@_stime = Time.now       # In case load failed, and time is not reset
      load __FILE__
    rescue => errmsg
      p errmsg
    end
  end
end

if (__FILE__ == $0)
  ITune::LyricMonitor.handleCli(
        ['--editor',    '-e', 1],
        ['--interval',  '-i', 1],
        ['--verbose',   '-v', 0]
  )
end
