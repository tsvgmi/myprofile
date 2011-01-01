#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        srtfile.rb
# Date:        Sat Dec 18 14:18:48 -0800 2010
# $Id: srtfile.rb 10 2010-12-18 22:19:25Z tvuong $
#---------------------------------------------------------------------------
#++
require File.dirname(__FILE__) + "/../../etc/toolenv"
require 'yaml'
require 'mtool/core'

# Helper for vnc script.
class SrtFile
  extendCli __FILE__

  def initialize(file)
    @file = file
  end

  def self.add_ofs(ivalue, offset)
    shr, smin, ssec, sms = ivalue.split(/[:,]/)
    val = shr.to_i*3600000 + smin.to_i*60000 + ssec.to_i*1000 + sms.to_i
    nval = val + offset
    nvals = "%02d:%02d:%02d,%03d" % [nval/3600000, (nval/60000)%60,
                (nval/1000)%60, nval%1000]
    nvals
  end

  # Add a delay to the srt (subtitle file)
  # Use: delay sec_offset - delay 28.3
  def delay(ioffset)
    offset   = (ioffset.to_f * 1000).to_i
    time_ptn = Regexp.new(/^([0-9:,]+) --> ([0-9:,]+)$/)
    File.read(@file).split("\n").each do |aline|
      aline.chomp!
      if time_ptn.match(aline)
        t1, t2 = $1, $2
        nval1 = SrtFile.add_ofs(t1, offset)
        nval2 = SrtFile.add_ofs(t2, offset)
        aline = "#{nval1} --> #{nval2}"
      end
      puts aline
    end
    true
  end
end

if (__FILE__ == $0)
  SrtFile.handleCli
end

