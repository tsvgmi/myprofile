#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        EditFilt.rb
# Date:        Wed Nov 07 09:23:03 PST 2007
# $Id: textfilt.rb 6 2010-11-26 10:59:34Z tvuong $
#---------------------------------------------------------------------------
#+++
=begin rdoc
=NAME
textfilt.rb - VIM miscellaneous filter

=SYNOPSIS

=DESCRIPTION
This script implements various vi/vim filter used in development.  This
is preferable to writing filter in VIM scripting language (this works
for other editors as well).  This allows creating common filter script
which could be used with many editors.

=end

require File.dirname(__FILE__) + "/../etc/toolenv"
require 'mtool/core'

class TextFilt
  extendCli __FILE__

  def self.load_input
    result = []
    while line = STDIN.gets
      result << line.chomp
    end
    result
  end

  def self.join_stanza
    state  = :odd
    output = []
    oline  = nil
    while line = STDIN.gets
      if (line =~ /^\s*$/) || (line =~/[DĐ]K:/)
        if oline
          puts oline
          oline = nil
          state = :odd
        end
        puts line.chomp
        next
      end
      if state == :odd
        oline = line.chomp
        state = :even
      else
        puts(oline + " / " + line.chomp)
        oline = nil
        state = :odd
      end
    end
    if oline
      puts oline
      oline = nil
    end
    true
  end
end

if (__FILE__ == $0)
  TextFilt.handleCli
end


