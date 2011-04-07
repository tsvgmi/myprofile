#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        vnc.rb
# $Id: etwiki.rb 6 2010-11-26 10:59:34Z tvuong $
#---------------------------------------------------------------------------
#+++
require File.dirname(__FILE__) + "/../../etc/toolenv"
require 'csv'
require 'mtool/core'

# Helper for vnc script.
class WikiTable
  def self.trimset(clist)
    offset = clist.size - 1
    while (offset >= 0) && ((!clist[offset]) || clist[offset].empty?)
      clist[offset] = nil
      offset -= 1
    end
    clist = clist.compact
    clist
  end

  def self.csv2wiki(csvfile)
    rowdefs = nil
    puts "{|"
    CSV.open(csvfile, 'r', ',') do |cols|
      cols = trimset(cols)
      if rowdefs
        if cols.size > 0
          cols.each do |ahead|
            puts "| #{ahead}"
          end
          puts "|-"
        end
      else
        cols.each do |ahead|
          puts "! #{ahead}"
        end
        puts "|-"
        rowdefs = true
      end
    end
    puts "|}"
  end
end

class ContribFile
  def self.get_all(file)
    require 'hpricot'
    require 'time'

    doc = Hpricot(File.read(file))
    urlset = {}
    doc.search("//li").each do |alist|
      links = alist.search("//a")
      next unless (links.size == 4)
      time  = links[0].inner_html
      url   = links[3]['href']
      next if (url =~ /redirect=no|File:|Category:/o)
      unless urlset[url]
        urlset[url] = Time.parse(time)
      end
    end
    puts urlset.to_yaml
    true
  end
end

class EtWiki
  extendCli __FILE__

  def self.tbline(aline)
    if aline =~ /\*/
      aline.gsub(/(\s)\|(\s)/, '\1!!\2').sub(/\s*\|$/, '')
    else
      aline.gsub(/(\s)\|(\s)/, '\1||\2').sub(/\s*\|$/, '')
    end
  end

  def self.retro2wiki(retrofile)
    fid = File.open(retrofile)
    state = :outside
    while (line = fid.gets) != nil
      line.chomp!
      case state
      when :outside
        if line =~ /^\|/
          state = :intable
          puts "{|"
          puts tbline(line)
          next
        end
      when :intable
        puts "|-"
        puts tbline(line)
        if line !~ /^\|/
          state = :outside
          puts "|}"
        else
          next
        end
      end
      puts line
    end
    fid.close
    if state == :intable
      state = :outside
      puts "|}"
    end
    true
  end

  def self.csv2wiki(csvfile)
    WikiTable.csv2wiki(csvfile)
  end

  def self.contribfile(file)
    ContribFile.get_all(file)
  end
end

if (__FILE__ == $0)
  EtWiki.handleCli
end

