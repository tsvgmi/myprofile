#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        lyricstore.rb
# Date:        Sat Mar 30 21:12:38 -0700 2013
# $Id$
#---------------------------------------------------------------------------
#++
require 'fileutils'
require_relative './core'
require_relative './vnmap'

module MidFolder
  # Monitor iTunes lyrics and display/edit
  class AriFolder
    def initialize(sdir='.', options={})
      @sdir    = sdir
      @options = options
      @odir    = options[:odir] || "../#{sdir}/tmp"
    end

    def group_by_dir
      files = []
      `find #{@sdir} -name '*mid'`.split("\n").sort.each do |sfile|
        cfolder, bfile = File.split(sfile)
        files << {bfile:bfile, sfile:sfile}
      end
      _group_by_dir(files, 1)
      true
    end

    def _dump_folder(cfolders, cfiles)
      if cfolders.size > 1
        gfolder = [cfolders[0], cfolders[-1]].join('~')
      else
        gfolder = cfolders[0]
      end
      codir = File.join(@odir, gfolder)
      FileUtils.mkdir_p(codir, verbose:true) unless test(?d, codir)
      cfiles.each do |fentry|
        ofile = File.join(codir, File.split(fentry[:sfile]).last)
        FileUtils.cp(fentry[:sfile], ofile, verbose:true)
      end
    end

    def _group_by_dir(files, psize)
      folders = {}
      files.each do |fentry|
        # The space is for ordering of folder so it does not come
        # before '-'
        fcs = fentry[:bfile]
          .sub(/_\d+.mid$/, '')
          .sub(/\(.*\)/, '')
          .gsub(/ +/, ',')
          .gsub(/[^,a-z0-9 ]+/io, '')[0..psize-1].strip.upcase
        folders[fcs] ||= []
        folders[fcs] << fentry
      end
      cfiles   = []
      cfolders = []
      folders.keys.sort.each do |folder|
        f_files = folders[folder]
        if f_files.size > 140
          if cfiles.size > 0
            _dump_folder(cfolders, cfiles)
            cfiles   = []
            cfolders = []
          end
          _group_by_dir(f_files, psize+1)
        else
          cfiles += f_files
          cfolders << folder
          if cfiles.size >= 140
            _dump_folder(cfolders, cfiles)
            cfiles   = []
            cfolders = []
          end
        end
      end
      if cfiles.size > 0
        _dump_folder(cfolders, cfiles)
      end
    end
  end

  class Main
    extendCli __FILE__

    def self.group_by_dir(dir='.')
      AriFolder.new(dir, getOption).group_by_dir
    end

    def self.reorganize(dir='.')
      Dir.glob('*mid').each do |sfile|
        dir, s0file = File.split(sfile)
        number, _tmp = s0file.split(/\s+-\s+/)
        sdir = number[0..3]
        ndir = "#{dir}/#{sdir}"
        FileUtils.mkdir_p(ndir, verbose:1)
        FileUtils.move(sfile, ndir, verbose:true)
      end
      true
    end

    def self.flatten_dir(dir='.')
      `find #{dir} -name '*mid'`.split("\n").each do |sfile|
        FileUtils.move(sfile, ".", verbose:true)
      end
    end

    def self.rename_from_file(nfile, dir='.')
      wset = {}
      File.read(nfile).split("\n").each do |l|
        number, name = l.split(' ', 2)
        wset[number] = name
      end
      `find #{dir} -name '*mid'`.split("\n").each do |sfile|
        dir, file = File.split(sfile)
        number, tmp, name = file.split(' ', 3)
        if repval = wset[number]
          nname = "#{number} - #{repval}"
          nfile = "#{dir}/#{nname}.mid"
          next if nfile == sfile
          FileUtils.move(sfile, nfile, verbose:true)
        end
      end
      true
    end

    def self.fix_noext(dir=".")
      `find #{dir} -type f`.split("\n").each do |sfile|
        next if sfile =~ /\.mid$/
        nfile = sfile + '.mid'
        FileUtils.move(sfile, nfile, verbose:true)
      end
      true
    end

    def self.remove_accent(dir=".")
      require 'unidecoder'

      _scandir('.', dir).each do |dir, bname, number, name|
        nname = name.to_ascii
        if nname !~ /^[-\(\). a-z0-9!,']+$/io
          puts "#{number} #{nname}"
        end
        next if nname == name
        nfile = "#{dir}/#{number} - #{nname}.mid"
        FileUtils.move("#{dir}/#{bname}", nfile, verbose:true)
      end
      true
    end

    def self.remove_lowcase(dir=".")
      _scandir('.', dir).each do |dir, bname, number, name|
        nname = name.gsub(/[a-z]/o, '')
        next if nname == name
        nfile = "#{dir}/#{nname}.mid"
        FileUtils.move(sfile, nfile, verbose:true)
      end
      true
    end

    def self.content(ptn='.', dir=".")
      _scandir(ptn, dir).map do |_dir, _bname, number, name|
        "#{number} #{name}"
      end.join("\n")
    end

    def self._scandir(ptn='.', dir=".")
      result = []
      `find #{dir} -name '*mid'`.split("\n").map do |sfile|
        dir, bname = File.split(sfile)
        next unless bname =~ /#{ptn}/o
        number, tmp, name = bname.sub(/\.mid$/, '').split(' ', 3)
        result << [dir, bname, number, name] if name
      end
      result
    end

    def self.sort_ext(ext='STL')
      require 'yaml'

      floc = {}
      `find . -name '*#{ext}'`.split("\n").each do |f|
        dir, fname = File.split(f)
        floc[fname] ||= []
        floc[fname] << dir
      end
      floc.to_yaml
    end
  end
end

if (__FILE__ == $0)
  MidFolder::Main.handleCli2(
    ['--odir', '-o', 1]
  )
end
