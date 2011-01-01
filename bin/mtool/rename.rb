#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        webpass.rb
# Date:        Wed Nov 07 09:23:03 PST 2007
# $Id: rename.rb 6 2010-11-26 10:59:34Z tvuong $
#---------------------------------------------------------------------------
#+++
require File.dirname(__FILE__) + "/../../etc/toolenv"
require 'fileutils'
require 'tempfile'
require 'mtool/core'
require 'yaml'
require 'iconv'
require 'find'
require 'active_record'

$: << "#{ENV['HOME']}/kamplayer/webapp/app"

require 'models/song'
require 'models/pl_song'
require 'models/play_list'
require 'models/lyric'

CONNECTION = {
  :adapter  => 'sqlite3',
  :database => "#{ENV['HOME']}/KA/vidkar.db"
}

class ActiveRecord::Base
  def save_wait
    countdown = 5
    while countdown > 0
      countdown -= 1
      begin
        return self.save
      rescue SQLite3::BusyException, ActiveRecord::StatementInvalid
        sleep 1
        Plog.warn "Retry ..."
      end
    end
  end
end

class PlayListCore
  attr_reader :data, :dbrec, :name

  def initialize(name)
    @name = name
    if (rec = PlayList.find(:first, :conditions=>["name=?", name])) == nil
      rec = PlayList.new(:name=>name)
      rec.save_wait
    end
    @dbrec = rec
    refresh
  end

  def concat(yrecs)
    rec = PlSong.find(:first, :select=>"max(play_order)+1 as mporder",
        :conditions=>["play_list_id=?", @dbrec.id])
    if rec
      order = rec.mporder.to_i
    else
      order = 0
    end
    yrecs.each do |yrec|
      @dbrec.pl_songs.create(:play_list_id=>@dbrec.id, :song_id=>yrec.id,
                             :play_order=>order)
      order += 1
    end
  end

  def reset
    @dbrec.pl_songs.clear
    @data = []
  end

  def refresh
    @dbrec = PlayList.find(:first, :conditions=>["name=?", @name],
                :include=>[:songs])
    @data  = @dbrec.songs
  end

  def [](index)
    @data[index]
  end

  def add_songs(mset, is_sort = false)
    mset = if is_sort
      mset.sort_by {|f| f.song + "-" + f.artist}
    else
      mset.sort_by {rand}
    end
    self.concat(mset)
    refresh
    mset
  end

  def gen_m3u(outfile = nil)
    outfile ||= "#{@name}.m3u"
    if @data.size <= 0
      Plog.error "No matching song found"
      return nil
    end
    Song.gen_m3u(outfile, @data)
    outfile
  end

  def fmt_text(aset = nil, pos = 0, curpos = -1, limit = 300)
    if aset
      has_state = false
    else
      aset = @data
      has_state = true
    end
    if aset.size <= 0
      return
    end
    if pos >= aset.size
      pos = aset.size - 1
    end
    pl_songs = has_state ? @dbrec.pl_songs : nil
    puts "Playlist: #{@name} [#{@data.size}]"
    @fmt_type = 1
    case @fmt_type
    when 1
      afmt = "%3d. %s [%d/%3d] %s %s %s %-12.12s: %s - %s"
    else
      afmt = "%3d. %-20.20s - [%1s] %s %s"
    end
    aset[pos..-1].each do |rec|
      case @fmt_type
      when 1
        times = "%2d:%02d" % [rec.duration/60, rec.duration%60]
        prec = [rec.sid, rec.rate, rec.playcount,
                Time.at(rec.lastplayed||0).strftime("%D"),
                Time.at(rec.mtime).strftime("%D"),
                times, rec.artist, rec.song, rec.tag]
      else
        prec = [rec.artist, rec.rate, rec.sid, rec.song]
      end
      if curpos && (curpos == pos)
        fmt = "*#{afmt}"
      else
        if !pl_songs || (pl_songs[pos].state == 0)
          fmt = " #{afmt}"
        else
          fmt = "-#{afmt}"
        end
      end
      prec.unshift(pos)
      puts fmt % prec
      pos += 1
      limit -= 1
      if limit <= 0
        break
      end
    end
  end
  
  def truncate(maxsize)
    # Truncate in db first
    songs = @dbrec.pl_songs
    if songs.size > maxsize
      sofs  = songs.size - maxsize
      Plog.info "Removing #{sofs} records"
      begin
        0.upto(sofs-1).each do |i|
          srec = songs[0]
          songs.delete(srec)
          srec.destroy
        end
      rescue => errmsg
        p errmsg
      end
      refresh
    end
    sofs
  end

  def disable_song(pos)
    Plog.info("Disable #{pos}")
    pos = pos.to_i
    if (pos >= 0) && (pos < @data.size)
      @dbrec.pl_songs[pos].state = 1
      @dbrec.pl_songs[pos].save_wait
    else
      Plog.warn "Invalid position #{pos}"
    end
  end

  def set_curplay(path, do_retry=true)
    rindex = -1
    
    # Must search from the currently so song could appear at multiple location
    startofs = @dbrec.curplay || 0
    if (startofs > 0) && (startofs < @data.size)
      walkset = (startofs..@data.size-1).to_a + (0..startofs-1).to_a
    else
      walkset = (0..@data.size-1).to_a
    end
    p "Searching for #{path} from #{walkset.first} of #{@data.size}"
    walkset.each do |index|
      entry = @data[index]
      if entry.path == path
        rindex = index
        break
      end
    end
    if (rindex >= 0) && (rindex <= @data.size)
      p "Set curplay to #{rindex}"
      @dbrec.curplay = rindex
      @dbrec.save_wait
    else
      p "Out of bound: startofs=#{startofs}, size=#{@data.size}, #{rindex} - ignore"
      refresh
      # Retry it once more
      if do_retry
        set_curplay(path, false)
      end
    end
    rindex
  end

end

class DbAccess
  @@_dbinstance = nil
  def self.instance
    unless @@_dbinstance
      ActiveRecord::Base.establish_connection(CONNECTION)
      @@_dbinstance = ActiveRecord::Base.connection
    end
    @@_dbinstance
  end
end

class KarFile
  attr_reader :sfile, :ext, :cname

  AllowExt = Regexp.new(/^(asf|avi|dat|divx|kar|mp4|mpeg|mpe|mpg|mkv|vob|wmv)$/i)

  def initialize(sfile)
    @sfile = sfile
    bdir, afile = File.split(@sfile)

    #cleanfile = afile.gsub(/_/, ' ').gsub(/\s+/, ' ').strip
    cleanfile = afile.gsub(/\s+/, ' ').strip
    fbreak    = cleanfile.split(/\./)
    @ext      = fbreak.pop
    @cname    = fbreak.join('.')
    @fpath    = Dir.pwd + "/" + @sfile
    @verbose  = RenameHelper.getOption(:verbose)
  end

  def isok?
    @ext && AllowExt.match(@ext)
  end

  def move_to(target)
    if RenameHelper.getOption(:dryrun)
      Plog.info("-- mv '#{@sfile}' '#{target}'")
    else
      FileUtils.move(@sfile, target, :verbose=>@verbose)
    end
  end

  def link_to(target)
    if RenameHelper.getOption(:dryrun)
      Plog.info("-- ln -s '#{@sfile}' '#{target}'")
    else
      if test(?l, target) || test(?e, target)
        FileUtils.remove(target, :verbose=>@verbose)
      end
      FileUtils.symlink(@fpath, target, :verbose=>@verbose)
    end
  end

  def self.translit(str)
    begin
      Iconv.iconv('ASCII//IGNORE//TRANSLIT', 'utf-8', str).to_s
    rescue Iconv::IllegalSequence => errmsg
      str.gsub(/[^&a-z._0-9 -]/i, "").tr(".", "_")
    end
  end

  def self.capitalize(string)
    translit(string).split.map do |word|
      word.capitalize
    end.join(" ")
  end

  def self.scan_dir(ptn, options = {})
    rptn = Regexp.new(/#{ptn}/i)
    here = Dir.pwd
    kflist = []
    if options[:depth]
      scanlist = []
      if options[:fullpath]
        Find.find(Dir.pwd) {|f| scanlist << f}
      else
        Find.find('.') {|f| scanlist << f}
      end
    else
      scanlist = Dir.glob('*')
    end

    scanlist.each do |apath|
      next unless test(?f, apath)
      next unless rptn.match(File.basename(apath))
      kflist << KarFile.new(apath)
    end

    kflist = kflist.sort {|a, b| a.cname <=> b.cname}

    kflist.each do |kfo|
      next unless kfo.isok?
      apath = kfo.sfile
      afile = File.basename(apath)
      dfile = yield(kfo)
      next unless dfile

      if dfile.class != Array
        dfiles = [dfile]
      else
        dfiles = dfile
      end

      dfiles.each do |xdfile|
        dfile = xdfile + "." + kfo.ext
        next if (dfile == afile)
        if test(?f, dfile)
          Plog.warn "#{dfile} exist.  Skip"
          if RenameHelper.getOption(:remove)
            FileUtils.remove(apath, :verbose=>@verbose)
          end
          next
        end
        if options[:dryrun]
          Plog.info "mv '#{apath}' to '#{dfile}'"
        else
          if options[:move]
            kfo.move_to(dfile)
          elsif options[:link]
            kfo.link_to(dfile)
          end
        end
      end
    end
    kflist
  end
end

class RenameHelper
  extendCli __FILE__

  def self.artist_names(artists)
    artists.split(/\s*[&,]\s*/).sort.map do |artist|
      KarFile.capitalize(artist)
    end
  end

  def self.rename_kar(ptn, rtype = "xas")
    KarFile.scan_dir(ptn, :move=>true) do |kfo|
      xtra = nil
      case rtype
      when "xas"
        xtra, art, song = kfo.cname.split(/\s*-\s*/)
      when "xcas"
        xtra, composer, art, song = kfo.cname.split(/\s*-\s*/)
        xtra = "#{composer}, #{xtra}"
      when 'cap'
        song = kfo.cname
        song = song.gsub(/([A-Z])/, ' \1').strip
        xtra = "English"
        art  = ""
      when 'xsa'
        xtra, song, art = kfo.cname.sub(/\s+_/, '_').split(/\s*_\s*/)
      when 'nsa'
        xtra, song, art = kfo.cname.sub(/^(\d+) /, '\1.').
                split(/\s*\.\s*/)
      when 'sa'
        song, art = kfo.cname.split(/\s*\.\s*/)
      else
        raise "Unsupported type: #{rtype}"
      end
      song = song.sub(/\s*\(karaoke\)/i, '')
      if xtra
        "#{song} - #{art} - #{xtra}"
      else
        "#{song} - #{art}"
      end
    end
    true
  end

  def self.rename_ekar(ptn, rtype = "sa")
    KarFile.scan_dir(ptn, :move=>true) do |kfo|
      case rtype
      when "sa"
        song, art = kfo.cname.split(/\s*-\s*/)
      when "as"
        art, song = kfo.cname.split(/\s*-\s*/)
      else
        raise "Unsupported type: #{rtype}"
      end
      song = song.sub(/^Traditional\s+/, '')
      art  = art.sub(/^Airsupply/, 'Air Supply').
        sub(/^Earth Wind and Fire/, 'Earth, Wind & Fire')
      art ||= "Unknown"
      "#{art} - #{song}"
    end
    true
  end

  def self.add_artist(ptn, *artist)
    artist = artist.join(' ')
    KarFile.scan_dir(ptn, :move=>true) do |kfo|
      song, art = kfo.cname.split(/\s*-\s*/)
      if art
        nil
      else
        "#{song} - #{artist}"
      end
    end
  end

  def self.reorg_by_artist(ptn, ddir)
    DbAccess.instance
    verbose = getOption(:verbose)
    KarFile.scan_dir(ptn, :depth=>true, :link=>true) do |kfo|
      if kfo.cname =~ /u sing along/i
        ldir = "#{ddir}/U Sing Along"
        unless test(?d, ldir)
          FileUtils.mkpath(ldir, :verbose=>verbose)
        end
        "#{ldir}/#{kfo.cname}"
      else
        song, art, xtra = kfo.cname.split(/\s*-\s*/)
        if art
          artists = artist_names(art)
          case artists.size 
          when 1
            true
          when 2
            artists << artists.join(' & ')
          else
            artists << "Hop Ca"
          end
          artists.map do |artist|
            ldir = "#{ddir}/#{artist}"
            unless test(?d, ldir)
              FileUtils.mkpath(ldir, :verbose=>verbose)
            end
            "#{ldir}/#{kfo.cname}"
          end
        else
          p kfo.cname
          nil
        end
      end
    end
    true
  end

  # Move files into folders based on 1st char.  Keep the directory small
  # so it is faster to access
  def self.reorg_by_alpha(ptn, ddir = ".")
    DbAccess.instance
    verbose = getOption(:verbose)
    KarFile.scan_dir(ptn, :move=>true) do |kfo|
      song, artist, xtra = kfo.cname.split(/\s*-\s*/)
      fc = KarFile.translit(song)[0,1]
      if fc =~ /[0-9]/
        fc = '0'
      end
      ldir = "#{ddir}/#{fc}"
      unless test(?d, ldir)
        FileUtils.mkpath(ldir, :verbose=>verbose)
      end
      "#{ldir}/#{kfo.cname}"
    end
    true
  end

  def self.renumber(ptn = '.')
    DbAccess.instance
    flist = []
    verbose = getOption(:verbose)
    KarFile.scan_dir(ptn, :depth=>true, :fullpath=>true) do |kfo|
      file = KarFile.capitalize(kfo.cname)
      flist << [file, kfo]
      nil
    end
    Song.transaction do
      Song.find(:all).each do |rec|
        rec.state = 'N'
        rec.save_wait
      end
      flist.sort {|a, b| a[0] <=> b[0]}.each do |file, kfo|
        Song.create_for_file(kfo)
      end
    end
    true
  end

  def self.print_content(*ptns)
    DbAccess.instance
    Song.print(ptns.join(' '))
  end

end

if (__FILE__ == $0)
  RenameHelper.handleCli(
        ['--mplayer', '-m', 0],
        ['--mdir',    '-M', 1],
        ['--dryrun',  '-n', 0],
        ['--outfile', '-o', 1],
        ['--sort',    '-s', 0],
        ['--verbose', '-v', 0]
        )
end

=begin
Schema for song database

# Playlist entry
CREATE TABLE pl_songs  (
  id           integer primary key,
  play_list_id int,
  song_id      int,
  play_order   int,
  state        int default 0
);
CREATE UNIQUE INDEX plsongidx2 on pl_songs(play_list_id,play_order);

# Playlist
CREATE TABLE play_lists (
  id      integer primary key,
  name    varchar(20),
  curplay int,
  state   int default 0
);
CREATE UNIQUE INDEX playlistidx1 on play_lists(name);

# Song DB
CREATE TABLE songs (
  id         integer primary key,
  path       varchar(256),
  song       varchar(60),
  ksel       varchar(8),
  artist     varchar(40),
  mtime      int,
  tag        varchar(80),
  rate       varchar(1),
  playcount  smallint,
  lastplayed int,
  lyrics     varchar(128),
  state      varchar(1),
  size       int,
  cfile      varchar(80),
  duration   int default 0
);
CREATE UNIQUE INDEX songidx1 on songs(path);
=end

