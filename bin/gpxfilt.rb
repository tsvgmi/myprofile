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
require 'nokogiri'
require 'open-uri'

class GpxFile
  def initialize(gfile)
    p gfile
    @doc = Nokogiri::XML(open(gfile))
  end

  def split_by_latitude(latitude)
    count = 0
    @doc.css("wpt").each do |wpt|
      lat = wpt[:lat].to_f
      if lat < latitude
        #p({wpt:wpt, lat:wpt[:lat], long:wpt[:lon], content:wpt.inner_html}.inspect)
        wpt.remove
        count += 1
      end
    end
    puts "Removing #{count} waypoints"
    count = 0
    @doc.css("trkpt").each do |trkpt|
      lat = trkpt[:lat].to_f
      if lat < latitude
        trkpt.remove
        count += 1
      end
    end
    puts "Removing #{count} trkpoints"
    open("test.gpx", "w") do |fod|
      fod.puts @doc.to_xml
    end
    true
  end

  def split_by_track(trackname)
    @doc.xpath("//trk/name[#{name}]").each do |track|
      p waypoint
      break
    end
    true
  end

  def crop(minlat, maxlat, minlong, maxlong)
  end
end

class GpxConvert
  extendCli __FILE__

  def self.split_by_latitude(file, latitude)
    GpxFile.new(file).split_by_latitude(latitude.to_f)
  end
end

if (__FILE__ == $0)
  GpxConvert.handleCli
end


