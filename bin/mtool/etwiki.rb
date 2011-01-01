#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        vnc.rb
# $Id: etwiki.rb 6 2010-11-26 10:59:34Z tvuong $
#---------------------------------------------------------------------------
#+++
require File.dirname(__FILE__) + "/../../etc/toolenv"
require 'yaml'
require 'mtool/core'

# Helper for vnc script.
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
end

if (__FILE__ == $0)
  EtWiki.handleCli
end

