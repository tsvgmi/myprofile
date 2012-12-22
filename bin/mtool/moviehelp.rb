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

class MovieHelp
  extendCli __FILE__

  # Purging directory of empty dirs b/c Finder would not delete
  def self.purge_dir
    pfid = File.popen("find . -type d")
    while dir = pfid.gets
      dir   = dir.chomp
      files = Dir.glob("#{dir}/*")
      next if files.count > 0
      pdir, pfile = File.split(dir)
      begin
        if pfile =~ /^BAD\./
          # Removing it now
          FileUtils.rm_rf(dir, :verbose=>true)
        else
          # Storage hang on the the dir if other machine is opening it
          FileUtils.mv(dir, "#{pdir}/BAD.#{pfile}", :verbose=>true)
        end
      rescue => errmsg
        p errmsg
      end
    end
    true
  end
end

if (__FILE__ == $0)
  MovieHelp.handleCli
end

