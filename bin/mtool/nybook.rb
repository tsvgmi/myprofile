#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        webpass.rb
# Date:        Wed Nov 07 09:23:03 PST 2007
# $Id: itunehelp.rb 6 2010-11-26 10:59:34Z tvuong $
#---------------------------------------------------------------------------
#+++
require File.dirname(__FILE__) + "/../../etc/toolenv"
require 'yaml'
require 'fileutils'
require 'mtool/core'

class NYBook
  extendCli __FILE__

  def self.xfer_dir(sdirs, ddir)
    sdir = sdirs.first
    if !test(?d, ddir)
      FileUtils.mkpath(ddir, :verbose=>true)
    end
    ctfile = "#{ddir}/content.yml"
    if test(?f, ctfile)
      content = YAML.load(file, ctfile)
    else
      content = []
    end
    content.concat(sdirs)
    fod = File.open(ctfile, "w")
    fod.puts content.uniq.to_yaml
    fod.close
    FileUtils.move(Dir.glob("#{sdir}/*"), ddir, :verbose=>true)
  end

  def self.merge_dirs(*dirs)
    odir = getOption(:outdir) || "./MergeList2"
    if !test(?d, odir)
      FileUtils.mkpath(odir, :verbose=>true)
    end
    dlist = {}
    dirs.each do |adir|
      `find "#{adir}" -type d`.split("\n").each do |d|
        dir, volume = File.split(d)
        if volume =~ /^#/
          rank, author, title = volume.split(/\s+-\s+/, 3)
          next unless title
        else
          title, author = volume.split(/\s+-\s+/, 2)
          next unless author
        end
        btype = File.basename(dir).downcase.gsub(/-/, '')
        key = "#{btype}:#{author} - #{title}"
        dlist[key] ||= []
        dlist[key] << d
      end
    end
    dlist.each do |bname, dirs|
      ddir = "#{odir}/#{bname.sub(/:/, '/')}"
      unless test(?d, ddir)
        xfer_dir(dirs, ddir)
      else
        Plog.info "#{ddir} created already.  Skip"
      end
    end
    true
  end

  def self.rename_dirs(*folders)
    folders.each do |folder|
      artist, title = folder.split(/\s+-\s+/, 2)
      next unless title
      next if artist =~ /(,|\&)/
      f = artist.split
      lname = f.last
      fname = f[0..-2].join(' ')
      ntitle = "#{lname}, #{fname} - #{title}"
      #puts "Moving '#{folder}' to '#{ntitle}'"
      if test(?d, ntitle)
        Plog.warn "#{ntitle} already exist, remove it ***"
        if Cli.confirm "OK to remove #{folder}"
          FileUtils.rm_rf(folder)
        end
      else
        FileUtils.move(folder, ntitle, :verbose=>true)
        #break
      end
    end
    true
  end
end

if (__FILE__ == $0)
  NYBook.handleCli
end

