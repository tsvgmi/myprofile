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

VideoExt = Regexp.new(/\.(avi|divx|mp4|mkv|flv)$/io)

class VideoFile
  def initialize(vfile, options = {})
    @vfile   = vfile
    @bname   = @vfile.sub(VideoExt, '').gsub("'", '')
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

    ['srt', 'eng.srt', 'en.srt', 'idx'].each do |sub|
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
    options  = getOption
    ptn      = options[:ptn] || ""
    cmd      = "find #{mdir} -name '*#{ptn}*'"
    skiplist = options[:skipfile] ? File.read(options[:skipfile]).split("\n") : []
    `#{cmd}`.split("\n").sort.each do |afile|
      bdir, bfile = File.split(afile)
      next if skiplist.include?(bfile)
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

  KillPtn = [
    Regexp.new(/(-KILLERS)?\[ettv\]|-GECKOS\[rarbg\]|(juggs|sam|xvid)\[ETRG\]|\[AC3\]|\[VTV\]|\[HIOb\]|ShAaNiG.com|-\s*(2hd|3lt0n|aqos|asap|bajskorv|bida|bito|cm8|dtech|ebx|encodeking|etrg|evo|excellence|fanta|fum|exvid|fingerblast|geckos|high|invincible|jyk|killers|kyr|legi0n|lol|maxspeed|mafiaking|micromkv|millenium|msd|p2p|playnow|psa|ptpower|qaac|rarbg|reenc|thgf|vicky)|(www.torrenting.com - )|www.torentz.3xforum.ro|(ganool|juggs|ac3 titan|hevc|no1knows||reenc|repack|takiawase|\d+MB|web-dl)|(.2CH.x265.HEVC|.HDTV.HEVC.x265-RMTeam)/io),
    Regexp.new(/[-\.](alterego|anoxmous|axxo|bdrip|bluray|brrip|dvdscr|evo|etrg|fum|gerhd|h264|hdrip|hdtv-fleet|hevc|hqclub|killers|lol|mkvcage|nezu|organic|proper|rarbg|rmteam|shaanig|tla|uav|vostfr|web-dl|webrip|x264|x265|x\.264|xvid)/io),
    Regexp.new(/[-_\.](\d+MB|720p|aac|ac3|batv|bdrip|bluray|bokutox|btchkek|cm8|crazy4ad|divx|dvdrip|fgt|foxm|haac|hdrip|hdtv|korsub|meteam|rccl|repack|screener|srigga|stuttershit|snd|sujaidr|sva|vyto|w4f|yify|web-convoy|web-strife|reenc-prime|fqm|ctu|2hd)/io),
    Regexp.new(%r{Crazy4TV.com -\s*|720p.*$}io)
  ]

  def self._clean_name(fname)
    dir, file = File.split(fname)
    if (file.start_with?('.') || !file.include?('.'))
      return nil
    end
    *fs, ext  = file.split('.')
    nfile     = fs.join('.')
    if false
      KillPtn.each do |aptn|
        nfile = nfile.sub(aptn, '')
      end
    end
    nfile = nfile.sub(/(19|20)\d{2}.(s\d+e\d+).*$/io, '\\2')
    nfile = nfile.sub(/((19|20)\d{2}\)?).*$/, '\\1')
    nfile = nfile.sub(/(s\d+e\d+).*$/io, '\\1')
    nfile = nfile.gsub(/\.+/, '.').sub(/-$/, '').sub(/\[.*\]\s*/, '').gsub("'", '')
    "#{dir}/#{nfile.strip}.#{ext}"
  end

  def self.flatten_dir(dir='.')
    require 'yaml'

    options = getOption
    dirs    = {}
    `find #{dir}`.split("\n").each do |d|
      next if d =~ /^#{dir}\/TV/
      fd, fb = File.split(d)
      dirs[fd] ||= []
      next if fb =~ /DS_Store/o
      dirs[fd] << fb
    end
    dirs.each do |dir, fs|
      if fs.size > 1
        puts({dir:dir, fs:fs[0]}.inspect)
        next
      end
      if options[:dryrun] || fs[0] =~ /\.part$/
        puts({dir:dir, fs:fs}.inspect)
        next
      end
      if fs.size == 1
        FileUtils.move("#{dir}/#{fs[0]}", "#{dir}/..", verbose:true)
      end
      FileUtils.rm_rf(dir, verbose:true)
    end
    true
  end
  
  def self.clean_dir
    dir = "."
    options = getOption

    `find #{dir} -type f`.split("\n").select { |f|
      (f !~ /Downloading/) && (f =~ /\//)
    }.each do |d|
      next unless (nd = _clean_name(d))
      if nd != d
        puts({d:d, nd:nd}.inspect)
        unless options[:dryrun]
          FileUtils.move(d, nd, verbose:true)
        end
      end
    end

    `find #{dir} -type f`.split("\n").select { |f|
      (f =~ /\//) && (f !~ /.part$/)
    }.each do |f|
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
      when /RARBG.COM/
        if options[:dryrun]
          p f
        else
          FileUtils.remove(f, verbose:true)
        end
        next
      end
      next unless (nfile = _clean_name(f))
      if nfile != f
        puts({f:f, nfile:nfile}.inspect)
        unless options[:dryrun]
          FileUtils.move(f, nfile, verbose:true)
        end
      end
    end
    if options[:backup]
      files = `find #{dir} -type f`.split("\n").select { |f|
        (f =~ /.(srt|bak)$/)
      }
      if files.size > 0
        FileUtils.remove(files, verbose:true)
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
    Plog.info("#{sfile} => #{dfile || ddir}")
    _movefile(sfile, dfile || ddir, options)
  end

  def self.move_to_movie_dir(movie_dir, ptn=nil)
    options   = getOption
    dir       = Dir.pwd
    ptn       = Regexp.new(ptn)
    movie_dir = File.expand_path(movie_dir)
    Plog.info "Getting names for files matching #{ptn}"

    Find.find(dir).each do |sfile|
      fdir, ffile = File.split(sfile)
      next if !ptn.match(sfile) || (ffile !~ /((20|19)\d{2})/o)
      next if fdir.start_with?(movie_dir) || ffile.start_with?('.')
      dyear = $1
      ddir  = "#{movie_dir}/#{dyear}"
      FileUtils.mkdir_p(ddir, verbose:true) unless test(?d, ddir)
      _movefile(sfile, ddir, options)
    end
    true
  end

  TV_SHOWS = [
    'Better Call Saul',
    'Big Little Lies',
    'Brooklyn Nine Nine',
    'Curb Your Enthusiasm',
    'Game of Thrones',
    'Grace And Frankie',
    'Homeland',
    'Louie',
    'Master Of None',
    'Rectify',
    'Sense 8',
    'The Americans',
    'The Big Bang Theory',
    'The Good Wife',
    'The Handmaids Tale',
    'The Middle',
    'The West Wing',
    'Veep',
    'Vice Principals',
    'Youre The Worst',
  ]
  def self.move_to_tv_dir(tv_dir, ptn=nil)
    options   = getOption
    dir       = Dir.pwd
    ddir_ptns = {}
    tv_dir    = File.expand_path(tv_dir)
    Plog.info "Getting names for files matching #{ptn}"

    TV_SHOWS.each do |tv_show|
      f = "#{tv_dir}/#{tv_show}"
      ddir_ptns[f] = Regexp.new(/#{tv_show.gsub(' ', '.')}/i)
    end

    to_move_files = Find.find(dir).select do |f|
      if f.start_with?(tv_dir) || File.basename(f).start_with?('.')
        false
      else
        test(?f, f) && (f !~ /(DS_Store|\.part)/o) && (!ptn || f =~ /#{ptn}/io)
      end
    end

    to_move_files.each do |f|
      ddir_ptns.each do |dir, ptn|
        next unless ptn.match(f)
        _move_to_season_dir(f, dir, options)
      end
    end
    true
  end
end

if (__FILE__ == $0)
  MKVMux.handleCli(
    ['--backup',    '-b', 0],
    ['--dryrun',    '-n', 0],
    ['--force',     '-f', 0],
    ['--odir',      '-d', 1],
    ['--skipfile',  '-s', 1],
  )
end

