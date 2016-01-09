#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        vnc.rb
# $Id: lyscanner.rb 6 2010-11-26 10:59:34Z tvuong $
#---------------------------------------------------------------------------
#+++
require File.dirname(__FILE__) + "/../../etc/toolenv"
require 'fileutils'
require 'mtool/core'
require 'iconv'
require 'find'

VideoExt = Regexp.new(/\.(avi|divx|mp4|mkv|flv)$/)

class VideoFile
  def initialize(vfile, options = {})
    @vfile   = vfile
    @bname   = @vfile.sub(VideoExt, '')
    @options = options
    # Make this instance var so it survive during lifetime of Videofile
    @subfile = nil
  end

  def mkv_file
    odir = @options[:odir] || "."
    unless test(?d, odir)
      FileUtils.mkpath(odir, verbose:true)
    end
    "#{odir}/#{@bname}.mkv"
  end

  def subtitle_file
    require 'tempfile'

    ic = Iconv.new('UTF-8//IGNORE', 'UTF-8')

    ['srt', 'eng.srt', 'idx'].each do |sub|
      subfile = "#{@bname}.#{sub}"
      if test(?f, subfile)
        if sub =~ /srt$/
          @subfile = Tempfile.new("srt")
          vcontent = ic.iconv(File.read(subfile) + ' ')[0..-2]
          vcontent.split("\n").each do |l|
            @subfile.puts l.chomp + " "
          end
          @subfile.close
          return @subfile.path
        else
          return subfile
        end
      end
    end
    nil
  end
end

class MKVMux
  extendCli __FILE__

  def self.check_and_move(input, output, *others)
    if test(?f, output) &&
      (File.size(output)*1.0 >= (File.size(input)*0.80))
      Plog.info "File generated to #{output} successfully"
      FileUtils.move(input, "#{input}.bak", verbose:true)
      others.each do |afile|
        FileUtils.move(afile, "#{afile}.bak", verbose:true)
      end
      if output =~ /\.new$/
        FileUtils.move(output, output.sub(/\.new$/, ''), verbose:true)
      end
      true
    else
      Plog.warn "Error generating #{output}.  Size is too small"
      false
    end
  end

  def self.join_multi(ptn = "")
    wset = {}
    cmd  = "find . -name '*#{ptn}*'"
    `#{cmd}`.split("\n").grep(/(cd|dvd)/i).sort.each do |afile|
      next unless afile =~ /\.(avi|divx|mp4|mkv)$/
      bname = File.dirname(afile) + "/" +
              File.basename(afile).gsub(/[-_\.]?(cd|dvd)\d+/i, '')
      wset[bname] ||= []
      wset[bname] << afile
    end
    wset.sort.each do |ofile, components|
      file0  = components.shift
      cplist = "'#{file0}'"
      components.each do |acomp|
        cplist << " '+#{acomp}'"
      end
      cmd = "mkvmerge --default-language en -o '#{ofile}.new' #{cplist}"
      Pf.system(cmd, 1)
      check_and_move(file0, "#{ofile}.new", *components)
    end
    true
  end

  def self.merge_subtitle(mdir=".")
    options = getOption
    ptn     = options[:ptn] || ""
    cmd     = "find #{mdir} -name '*#{ptn}*'"
    `#{cmd}`.split("\n").sort.each do |afile|
      next unless VideoExt.match(afile)
      video  = VideoFile.new(afile, options)
      ofile  = video.mkv_file
      afile2 = afile.gsub(/'/, "\\\\'")
      if test(?f, ofile)
        has_subtitle = `mkvinfo '#{afile2}' | egrep subtitles`
        if !has_subtitle.empty? && !options[:force]
          Plog.warn "MKV file with subtitle found for #{afile}. skip"
          next
        end
      end
      unless subfile = video.subtitle_file
        Plog.warn "Subtitle file for #{afile} not found.  Skip"
        next
      end
      ofile2   = ofile.gsub(/'/, "\\\\'")
      STDERR.puts({ofile:ofile, ofile2:ofile2}.inspect)
      cmd = "mkvmerge --default-language en -o '#{ofile2}.new' '#{afile2}' '#{subfile}'"
      if options[:dryrun]
        Plog.info(cmd)
      else
        Pf.system(cmd, 1)
        check_and_move(afile, "#{ofile}.new", subfile)
      end
    end
    true
  end

  KillPtn = Regexp.new(/(-KILLERS)?\[ettv\]|-GECKOS\[rarbg\]|(juggs|sam|xvid)\[ETRG\]|\[AC3\]|\[VTV\]|\[HIOb\]|ShAaNiG.com|-\s*(2hd|3lt0n|aqos|asap|bajskorv|bida|bito|cm8|dtech|ebx|encodeking|etrg|evo|excellence|fanta|fum|exvid|fingerblast|geckos|high|invincible|jyk|killers|kyr|legi0n|lol|maxspeed|mafiaking|micromkv|millenium|msd|p2p|playnow|psa|ptpower|qaac|rarbg|reenc|thgf|vicky)|(www.torrenting.com - )|www.torentz.3xforum.ro|(ganool|yify|juggs|ac3 titan|hevc|no1knows||reenc|repack|takiawase|\d+MB|web-dl)|(.2CH.x265.HEVC|.HDTV.HEVC.x265-RMTeam)/i)

  def self._clean_name(fname)
    dir, file = File.split(fname)
    nfile = file.sub(KillPtn, '').gsub(/\.+/, '.').sub(/-$/, '').
        sub(/\[.*\]\s*/, '')
    "#{dir}/#{nfile.strip}"
  end

  def self.clean_dir
    dir = "."
    options = getOption

    Find.find(dir).select { |f|
      (f !~ /Downloading/) && test(?d, f) && (f =~ /\//)
    }.each do |d|
      if (nd = _clean_name(d)) != d
        puts({d:d, nd:nd}.inspect)
        unless options[:dryrun]
          FileUtils.move(d, nd, verbose:true)
        end
      end
    end

    Find.find(dir).select do |f|
      test(?f, f) && (f =~ /\//) && (f !~ /.part$/)
    end.each do |f|
      case f
      when /\.xx-srt$/
        bfile = $`
        if test(?f, bfile + ".mkv")
          if options[:dryrun]
            p f
          else
            FileUtils.remove(f, verbose:true)
          end
          next
        end
      when /\.(bak|nfo|txt)$/
        if options[:dryrun]
          p f
        else
          FileUtils.remove(f, verbose:true)
        end
        next
      end
      if (nfile = _clean_name(f)) != f
        puts({f:f, nfile:nfile}.inspect)
        unless options[:dryrun]
          FileUtils.move(f, nfile, verbose:true)
        end
      end
    end
    true
  end

  def self._movefile(src, dest, options={})
    if options[:dryrun]
      puts({src:src, dest:dest}.inspect)
    else
      FileUtils.move(src, dest, verbose:true)
    end
  end

  def self._move_to_season_dir(sfile, ddir, options={})
    dfile = nil
    if sfile =~ /s(\d+)e\d+/i
      ddir += "/Season #{$1.to_i}"
      unless test(?d, ddir)
        FileUtils.mkdir_p(ddir)
      end
    elsif sfile =~ /\.(\d{1,2})(\d\d)\./
      fp, lp, season, episode = $`, $', $1.to_i, $2
      season_s = "%02d" % [season]
      ddir += "/Season #{season}"
      s2file = "#{fp}.S#{season_s}E#{episode}.#{lp}"
      unless test(?d, ddir)
        FileUtils.mkdir_p(ddir)
      end
      dfile = "#{ddir}/#{s2file}"
    end
    _movefile(sfile, dfile || ddir, options)
  end

  def self.move_to_media_dir(ptn=nil)
    #mediadir = "/Volumes/My_Book/TV"
    #mediadir = "/Volumes/WD_My_Book_1140_41/TV"
    #mediadir = "/Volumes/share_1/TV"
    mediadir = "/mnt/share_1/TV"
    dir      = "."
    fptn     = {}
    Plog.info "Getting names for files matching #{ptn}"
    Dir.glob("#{mediadir}/*").each do |f|
      d, file = File.split(f)
      fptn[f] = Regexp.new(/#{file.gsub(' ', '.')}/i)
    end
    options = getOption
    files = Find.find(dir).select do |f|
      if test(?f, f)
        (f =~ /\//) && (f !~ /(DS_Store|\.part)/o) &&
                (!ptn || f =~ /#{ptn}/io)
      else
        false
      end
    end
    files.each do |f|
      fptn.each do |dir, ptn|
        next unless ptn.match(f)
        _move_to_season_dir(f, dir, options)
      end
    end
    true
  end
end

if (__FILE__ == $0)
  MKVMux.handleCli(
    ['--dryrun', '-n', 0],
    ['--force',  '-f', 0],
    ['--odir',   '-d', 1]
  )
end

