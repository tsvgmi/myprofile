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

  # Transfer either epub or mob files in a subdir to a destination flat dir
  # Example
  # nybook.rb xfer_flat '/Volumes/Kindle/documents/newdir' [pattern]
  def self.xfer_flat(ddir, pattern = nil)
    wset = {}
    fset = `find . -name '*.mobi'`.split("\n")
    fset.concat `find . -name '*.epub'`.split("\n")
    fset.each do |f|
      if pattern
        next unless f =~ /#{pattern}/
      end
      bname = f.sub(/\.(mobi|epub)$/, '')
      if !wset[bname]
        wset[bname] = f
      end
    end
    files = []
    wset.each {|k, v| files << v}
    unless test(?d, ddir)
      FileUtils.mkpath(ddir, :verbose=>true)
    end
    files.each do |file|
      file  = file.first
      dfile = ddir + "/" + File.basename(file).sub(/^\d+\s+-\s+/, '')
      unless test(?f, dfile)
        FileUtils.copy(file, dfile, :verbose=>true)
      end
    end
    true
  end

  def self.merge_dirs(*dirs)
    odir = getOption(:outdir) || "./MergeList"
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

  def self.rename_files_01(fcontent)
    require 'fileutils'

    File.read(fcontent).split(/\n/).each do |file|
      next unless test(?e, file)
      name = File.basename(file)
      publisher = ""
      authors, title = name.split(/\s*-\s*/, 2)
      next unless authors
      nauthors = []
      authors.split(/\s*\&\s*/).each do |author|
        fs = author.split
        fname, lname = fs[0..-2].join(' '), fs[-1]
        nauthors << "#{lname}, #{fname}"
      end
      p "N: #{name}"
      title = title.sub(/\s*\(mobi\)\s*/i, '')
      if title =~ /\s*-\s*/
        publisher, title = $`, $'
      end
      #p "A: " + "#{nauthors.join(' & ')}", "T: " + title, "P: " + publisher
      newname = "#{nauthors.join(' & ')} - #{title}"
      if false
        p newname
      else
        if newname != name
          FileUtils.move(file, "#{newname}", :verbose=>true)
        end
      end
    end
    true
  end

  def self.rename_files(fcontent)
    require 'fileutils'

    File.read(fcontent).split(/\n/).each do |file|
      next unless test(?e, file)
      name = File.basename(file)
      title, authors = name.split(/\s*, by\s*/, 2)
      next unless authors
      authors = authors.sub(/^by\s+/, '')
      nauthors = []
      authors.split(/\s+(and|with)\s+/).each do |author|
        next if author =~ /and|with/
        p "A: " + author
        fs = author.split
        fname, lname = fs[0..-2].join(' '), fs[-1]
        nauthors << "#{lname}, #{fname}"
      end
      p "N: #{name}"
      title = title.sub(/\s*\(mobi\)\s*/i, '')
      if title =~ /\s*-\s*/
        publisher, title = $`, $'
      end
      newname = "#{nauthors.join(' & ')} - #{title}"
      if false
        p newname
      else
        if newname != name
          FileUtils.move(file, "#{newname}", :verbose=>true)
        end
      end
    end
    true
  end

  def self.rename_file(type, path)
    dir, file = File.split(path)
    case type
    when 'author.title'
      author, title = file.split(/\s*-\s*/, 2)
      raise "No title" unless title
      first, last, other = author.split
      raise "Bad form name" if other
      newtitle = "#{dir}/#{last}, #{first} - #{title}"
      FileUtils.move(path, newtitle, :verbose=>true)
    when 'title.author'
      title, author = file.split(/\s*-\s*/, 2)
      author, fext  = author.split(/\./)
      raise "No author" unless author
      names = author.sub(/\s*\(.*$/, '').split
      last  = names[-1]
      first = names[0..-2].join(' ')
      raise "Bad form name" if other
      newtitle = "#{dir}/#{last}, #{first} - #{title}"
      if fext
        newtitle += ".#{fext}"
      end
      FileUtils.move(path, newtitle, :verbose=>true)
    else
      raise "Unknown type: #{type}"
    end
  end
end

if (__FILE__ == $0)
  NYBook.handleCli
end

