#!/bin/env ruby

$: << ENV['HOME'] + "/bin"
require ENV['HOME'] + '/etc/toolenv'

require 'yaml'
require 'fileutils'
require 'mtool/core'

module KfUtils
  def self.scan_files(dir, filter="")
    require 'digest/sha1'

    dir = File.absolute_path(dir)
    cmd = "find #{dir} -name '*kfn' #{filter}"
    key = Digest::SHA1.hexdigest(cmd)
    cfile = "/tmp/kf-#{key}.yml"
    Plog.info({dir:dir,   mtime:File.mtime(dir)}.inspect)
    Plog.info({dir:cfile, mtime:File.mtime(cfile)}.inspect) if test(?f, cfile)
    doscan = false
    if !test(?f, cfile)
      doscan = true
    elsif (File.mtime(dir) > File.mtime(cfile))
      doscan = true
    end
    if doscan
      Plog.info("Scan #{dir} and cache to #{cfile}")
      files = `#{cmd}`.split("\n")
      File.open(cfile, "w") do |fod|
        fod.puts files.sort.to_yaml
      end
    else
      Plog.info("Loading #{dir} from #{cfile}")
      files = YAML.load_file(cfile)
    end
    files
  end

  def self.clean_name(string)
    require 'iconv'

    string = string.sub(/\.kfn$/, '')
    string = File.basename(string).split.map{|w|
      if w =~ /[a-z0-9]+/i
        $` + $&.capitalize + $'
      else
        w.capitalize
      end
    }.join(' ')
    Iconv.conv('ascii//translit//ignore', 'utf-8', string).to_s
  end

  def self.move_files(files, ddir, options={})
    files   = files.sort
    if files.size > 0
      if options[:dryrun]
        files.each do |afile|
          nfile = "#{ddir}/#{afile}"
          Plog.info("%30s >> %s" % [afile, nfile])
        end
      else
        FileUtils.mkdir_p(ddir, verbose:true) unless test(?d, ddir)
        files.each do |afile|
          begin
            FileUtils.move(afile, ddir, verbose:true)
          rescue => errmsg
            p errmsg
          end
        end
      end
    end
  end

  def self.dirs_by(dirlist, dtype=:name, options={})
    entries = []
    dirlist.each_with_index do |adir, index|
      entries.concat(KfUtils.scan_files(adir).map{|f| [f, index]})
    end
    result = entries.select {|f| f !~ /\._/}.
    group_by do |f, index|
      group = f
      case dtype
      when :artist
        afile = File.basename(f).sub(/^\d+\.\s*/, '').
              gsub(/\([^\)]+\)/, '').
              sub(/\.kfn/, '').
              sub(/Nhac Ngoai - /i, '').
              split(/\s+-\s+/)
        if afile.size > 1
          group = afile[1].sub(/\s*\(.*$/, '').
                        split(/,\s*/).sort.join(', ')
        else
          group = "Unknown"
        end
      else
        group = File.basename(f).sub(/^\d+\.\s*/, '').
              gsub(/\([^\)]+\)/, '').
              sub(/Nhac Ngoai - /i, '').
              sub(/^NK_/i, '').
              sub(/\.kfn/, '').sub(/\s+-\s+.*$/, '').
              sub(/\s*\(.*$/, '')
      end
      KfUtils.clean_name(group).downcase
    end
    if options[:short]
      case dtype
      when :artist
        result.each do |title, wlist|
          result[title] = wlist.map {|f, index|
            File.basename(f).split(/\s+-\s+/)[0]
          }
        end
      else
        result.each do |title, wlist|
          result[title] = wlist.map {|f, index|
            File.basename(f).split(/\s+-\s+/)[1..-1].join(' - ')
          }.sort.join(' *** ').gsub(/\.kfn/, '')
          #p title, result[title]
        end
      end
    end
    result
  end

end

class Karafun
  extendCli __FILE__

  def self.clean_dir
    system "find . -name '._*' -exec rm -f {} \\;"
  end

  # Normalize filenames: name (author) - artist.kfn
  def self.rename_files(ptn=nil)
    options = getOption
    limit   = (options[:limit] || 100_000).to_i
    count   = 0
    KfUtils.scan_files(".").each do |apath|
      next if (count > limit)
      dirname, afile = File.split(apath)
      next if (afile =~ /\._/)
      if ptn && (afile !~ /#{ptn}/)
        next
      end
      if File.size(apath) <= 0
        STDERR.puts "#{apath} is 0 bytes.  Not touching"
        next
      end
      nfile = afile.clone
      while nfile =~ /([a-z])([A-Z])/
        nfile = $` + $1 + ' ' + $2 + $'
      end
      nfile = nfile.gsub(/\s*-\s*/, ' - ').
                sub(/^Ut ?Cafe - /i, '').
                sub(/^NK_/, '').
                sub(/(_NTHkrf|_KKKKrf| Krf) Binh Yen/i, '').
                sub(/\.CKN/i, '').
                sub(/^LK - /i, 'LK ').
                sub(/^Lien Khuc/i, 'LK ').
                sub(/- Hulk -/i, '-').
                sub(/^(l Del|New) - /i, '').
                sub(/^\d+\.\s+/, '').
                sub(/yphuong/i, 'Y Phuong').
                sub(/yphung/i, 'Y Phung').
                sub(/5dong/i, '5 Dong').
                sub(/evis phuong/i, 'Elvis Phuong').
                sub(/PDT\./, 'Phan Dinh Tung.').
                sub(/\s*nhh$/i, '').
                gsub(/\s+/, ' ')
      if nfile.scan(/_/).size == 1
        nfile = nfile.sub(/_/, ' - ')
      end
      if nfile =~ /\s+Remix\s*-/
        nfile = nfile.sub(/\s+Remix\s*-/, ' -').sub(/\.kfn$/, '') + " - Remix.kfn"
      end
      nfile = KfUtils.clean_name(nfile) + ".kfn"

      # Take out the remix
      wset = nfile.split(/\s+-\s+/)
      if wset.size > 2
        if wset[-1] =~ /remix/i
          wset[-2] += " (Remix)"
          nfile = wset[0..-2].join(' - ') + ".kfn"
        elsif wset[-1] == 'Tt.kfn'
          nfile = wset[0..-2].join(' - ') + ".kfn"
        end
      end

      next if (nfile == afile)

      rename_file("#{dirname}/#{afile}", "#{dirname}/#{nfile}", options[:dryrun])
      count += 1
      if count > limit
        break
      end
    end
    true
  end

  def self.rename_file(from_name, to_name, dryrun=false)
    if dryrun
      Plog.info("%30s >> %s" % [from_name, to_name])
    else
      if from_name.downcase == to_name.downcase
        tmpfile = "#{from_name}.tmp"
        FileUtils.mv(from_name,  tmpfile, verbose:true)
        FileUtils.mv(tmpfile, to_name, verbose:true)
      else
        FileUtils.mv(from_name,  to_name, verbose:true)
      end
    end
  end

  def self.reorder_title(*files)
    options = getOption
    files.each do |afile|
      artist, remain = afile.split(/\s+-\s+/)
      if !remain
        remain = afile
        artist = File.basename(Dir.pwd)
      end
      remain = remain.sub(/\.kfn$/, '').sub(/[_ ](BietLy|Quang Dung)/, '')
      artist = artist.gsub(/\s/, '')
      nfile = "../#{remain}-#{artist}.kfn"
      if options[:dryrun]
        Plog.info("%30s >> %s" % [afile, nfile])
      else
        FileUtils.mv(afile, nfile, verbose:true)
      end
    end
    true
  end

  def self.flatten_dir
    options = getOption
    KfUtils.scan_files(".", "-type d").each do |dir|
      ndir = dir.sub(/\.kfn$/, '')
      if options[:dryrun]
        Plog.info "%-30s >> %s" % [dir, ndir]
        Plog.info "%-30s >> %s" % ["#{ndir}/#{dir}", "."]
      else
        FileUtils.mv(dir, ndir, verbose:true)
        FileUtils.mv("#{ndir}/#{dir}", ".", verbose:true)
        FileUtils.rmdir(ndir, verbose:true)
      end
    end
    true
  end

  def self.extract_links(file)
    require 'open-uri'
    require 'nokogiri'

    content = open(file).read
    doc     = Nokogiri::HTML.parse(content)
    doc.css("a").map {|link|
      link['href']
    }.select {|link|
      link !~ /blogspot|blogger|javascript/
    }
  end

  def self.output_pdf(wlist, ofile)
    Plog.info("Writting output to #{ofile}")
    ofid  = File.popen("groff -mm | pstopdf -i -o #{ofile}", "w")
    ofid.puts ".FAMILY H"
    ofid.puts ".HR"
    ofid.puts ".PF '#{Date.today}'"
    ofid.puts ".2C"
    ofid.puts ".AL A 0 1"
    wlist.keys.sort.each do |title|
      files = wlist[title]
      ofid.puts ".LI"
      ofid.puts title.upcase.split.map{|w| ".B #{w}"}.join("\n")
      ofid.puts ".BL 4 1"
      if files.is_a?(Array)
        ofid.puts files.sort.map{|f, index|
          f = KfUtils.clean_name(f)
          ".LI\n#{f}"
        }.join("\n")
      else
        ofid.puts KfUtils.clean_name(files)
      end
      ofid.puts ".LE"
    end
    ofid.puts ".LE"
    ofid.close
  end

  def self.output_text(wlist, ofile)
    ofid = ofile ? File.open(ofile) : STDOUT
    wlist.keys.sort.each do |name|
      files = wlist[name]
      ofid.puts "%-50s [%d]" % [name.upcase, files.size]
      if files.is_a?(String)
        files = [files]
      end
      files.each do |f, index|
        f = KfUtils.clean_name(f)
        ofid.puts "    #{index}. #{f}"
      end
    end
    if ofile
      ofid.close
      Plog.info("Output written to #{ofile}")
    end
  end

  def self.dirs_by_name(*dirs)
    if dirs.size <= 0
      dirs << "."
    end
    options = getOption
    ofmt    = options[:ofmt]
    entries = KfUtils.dirs_by(dirs, :name, options)
    #puts entries.to_yaml
    if ofmt == 'pdf'
      output_pdf(entries, options[:ofile] || "./dirs_by_name.pdf")
    else
      output_text(entries, options[:ofile])
    end
    true
  end

  def self.dirs_by_artist(*dirs)
    if dirs.size <= 0
      dirs << "."
    end
    options = getOption
    ofmt    = options[:ofmt]
    entries = KfUtils.dirs_by(dirs, :artist, options)
    if options[:ofmt] == "pdf"
      output_pdf(entries, options[:ofile] || "dirs_by_artist.pdf")
    else
      output_text(entries, options[:ofile])
    end
    true
  end

  def self.check_files(cfile)
    result = {}
    File.read(cfile).split("\n").select {|l| l =~ /mediafire/}.each {|l|
      if l =~ /\.kfn$/
        link = l
      else
        link = `curl -sI #{l}`.split("\n").grep(/^Location:/)[0].split[1]
        Plog.info(link)
      end
      name = File.basename(link)
      result[name] = l
    }
    result.to_yaml
  end

  def self.check_new_files(cfile, *dirs)
    if dirs.size <= 0
      dirs << "."
    end
    curfiles = KfUtils.dirs_by(dirs, :artist, getOption)
    lnames   = {}
    if cfile =~ /.yml$/
      newfiles = {}
      YAML.load_file(cfile).each do |name, link|
        bname = File.basename(name).gsub(/(_|%20)/, ' ').
                gsub(/\+/, ' ').
                sub(/\.kfn/, '').sub(/\s+-\s+.*$/, '').
                sub(/\s+av$/i, '').
                sub(/\s*\(.*$/, '').downcase
        newfiles[bname] ||= []
        newfiles[bname] << link
        lnames[bname] = File.basename(name)
      end
    else
      newfiles = File.read(cfile).split("\n").select {|l| l =~ /mediafire/}
        group_by {|l|
          File.basename(l).gsub(/(_|%20)/, ' ').
                gsub(/\+/, ' ').
                sub(/\.kfn/, '').sub(/\s+-\s+.*$/, '').
                sub(/\s*\(.*$/, '').downcase
        }
    end
    newfiles.each do |name, links|
      if curfiles[name]
        STDERR.puts("'#{lnames[name] || name}' found")
        STDERR.puts "OLD"
        STDERR.puts curfiles[name].to_yaml
        STDERR.puts "NEW"
        STDERR.puts newfiles[name].to_yaml
        next unless Cli.confirm("OK to add")
      end
      Plog.info("#{name} new")
      STDOUT.puts links.join("\n")
      STDOUT.flush
    end
    true
  end

  # Process bietly html dump to retrieve mediafire link.  Dump to stdout
  # for jdownloader to use
  def self.process_bietly(file)
    require 'open-uri'
    require 'nokogiri'

    content = open(file).read
    doc     = Nokogiri::HTML.parse(content)
    doc.css("a").map {|link|
      link['href']
    }.select {|link|
      link =~ /mediafire/
    }.sort_by {|l| File.basename(l)}.join("\n")
  end

  def self.find_no_artist
    options = getOption
    files   = KfUtils.scan_files(".", "-depth 1").select {|f| f !~ /-/}
    if moveto = options[:moveto]
      KfUtils.move_files(files, moveto, options)
    end
    files
  end

  # Dup detection
  def self.list_dups(*dirlist)
    options = getOption
    dirlist << '.' if (dirlist.size <= 0)
    entries = []
    dirlist.each do |adir|
      entries.concat(KfUtils.scan_files(adir, "-depth 1"))
    end
    keyset = {}
    entries.select {|f| f !~ /\._/}.
    group_by do |afile|
      key = File.basename(afile).
        gsub(/\(Remix\)/i, 'Remix').
        gsub(/\([^\)]+\)/, '').gsub(/[^a-z0-9]+/i, ' ').split.sort.join(' ')
      keyset[key] ||= []
      keyset[key] << afile
    end
    result = keyset.to_a.select{|k, v| v.size > 1}.sort_by {|k, v| v}
    if moveto = options[:moveto]
      if dirlist.include?(moveto)
        Plog.error("Move to dir cannot be in the source list")
        return false
      end
      files = result.map {|k, v| v}.flatten
      KfUtils.move_files(files, moveto, options)
    end
    result.to_yaml
  end

  def self.list_ambiguous(*dirlist)
    options = getOption
    dirlist << '.' if (dirlist.size <= 0)
    entries = []
    dirlist.each do |adir|
      KfUtils.scan_files(adir, "-depth 1").each do |afile|
        wset = afile.split(/\s+-\s+/)
        if wset.size > 2
          entries << afile
        end
      end
    end
    if moveto = options[:moveto]
      KfUtils.move_files(entries, moveto, options)
    end
    entries
  end
end

if (__FILE__ == $0)
  Karafun.handleCli(
    ['--dups',   '-D', 0],
    ['--odir',   '-d', 1],
    ['--ofmt',   '-f', 1],
    ['--limit',  '-l', 1],
    ['--moveto', '-m', 1],
    ['--dryrun', '-n', 0],
    ['--ofile',  '-o', 1],
    ['--short',  '-s', 0]
  )
end

