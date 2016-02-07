#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        vnc.rb
# $Id: lyscanner.rb 6 2010-11-26 10:59:34Z tvuong $
#---------------------------------------------------------------------------
#+++
require File.dirname(__FILE__) + "/../../etc/toolenv"
require 'fileutils'
require 'epub/parser'
require 'mtool/core'
require 'iconv'
require 'find'
require 'yaml'

class Epub
  extendCli __FILE__

  def self.reorganize
    Dir.glob("*.epub") do |file|
      book    = EPUB::Parser.parse(file)
      meta    = book.metadata
      subject = (entry = meta.subjects.first) ? entry.content : nil
      #STDERR.puts({file:file, subject:subject}.inspect)
      if subject
        target = "#{subject}/#{file}"
      elsif file =~ /chua xac dinh/i
        target = "Chua xac dinh/#{file}"
      elsif file =~ /kim dung/i
        target = "Kiếm Hiệp/#{file}"
      end
      if target
        FileUtils.mkdir_p(target) unless test(?d, target)
        FileUtils.move(file, target, verbose:true)
      else
        STDERR.print('.')
        STDERR.flush
      end
    end
  end

end

if (__FILE__ == $0)
  Epub.handleCli(
    ['--dryrun', '-n', 0],
    ['--force',  '-f', 0],
    ['--odir',   '-d', 1]
  )
end

