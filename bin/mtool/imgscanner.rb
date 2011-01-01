#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        vnc.rb
# $Id: imgscanner.rb 6 2010-11-26 10:59:34Z tvuong $
#---------------------------------------------------------------------------
#+++
require File.dirname(__FILE__) + "/../../etc/toolenv"
require 'yaml'
require 'fileutils'
require 'tempfile'
require 'open-uri'
require 'hpricot'
require 'mtool/core'

class VnhimPage
end

# Helper for vnc script.
class ImgScanner
  extendCli __FILE__

  def initialize(actress)
    @pages  = []
    @images = []
    1.upto(100) do |apage|
      url = "http://www.revolutionmyspace.com/pictures-#{apage}/#{actress}"
      if (content = ImgScanner.page_load(url)) == nil
        break
      end
      pimg = []
      content.search("img").each do |img|
        src = img['src']
        next unless (src =~ /http:\//)
        next unless (src =~ /photobucket/)
        pimg << src
      end
      break unless (pimg.size > 0)
      @pages << content
      @images.concat(pimg)
    end
  end

  def load_img
    @images.each do |src|
      dext = src.sub(/^.*\./, '')
      dest = Digest::MD5.hexdigest(src) + ".#{dext}"
      #dest = File.basename(src)

      unless test(?f, dest)
        Plog.info "Loading #{src} to #{dest}"
        begin
          fid  = open(src)
          fod  = File.open(dest, "w")
          fod.write(fid.read)
          fod.close
          fid.close
        rescue OpenURI::HTTPError => errmsg
          p errmsg
        end
      end
    end
    true
  end

  def self.page_load(url)
    require 'hpricot'
    require 'digest/md5'

    sig = Digest::MD5.hexdigest(url)
    cfile = "#{sig}.html"
    unless test(?f, cfile)
      Plog.info "Caching #{url} to #{cfile}"
      begin
        fid  = open(url)
        page = fid.read
        fid.close
        fod  = File.open(cfile, "w")
        fod.puts(page)
        fod.close
      rescue => errmsg
        page = ""
        p errmsg
      end
    else
      page = File.read(cfile)
    end
    Hpricot(page)
  end
end

if (__FILE__ == $0)
  ImgScanner.handleCli(
        ['--update',  '-u', 0]
        )
end

