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

module SrtUtil
  # Convert a text string to ms value
  def self.msec(ivalue)
    shr, smin, ssec, sms = ivalue.split(/[:,]/)
    val = shr.to_i*3600000 + smin.to_i*60000 + ssec.to_i*1000 + sms.to_i
  end
  
  def self.to_hms(val)
    "%02d:%02d:%02d,%03d" % [val/3600000, (val/60000)%60,
                (val/1000)%60, val%1000]
  end
end

# Helper for vnc script.
class SrtFile
  extendCli __FILE__

  attr_reader :filters

  def initialize(file)
    @file = file
    @filters = []
  end

  def run_filter
    filter_lyrics do |v1, v2|
      t1 = SrtUtil.msec(v1)
      t2 = SrtUtil.msec(v2)
      @filters.each do |afilter|
        t1 = afilter.call(t1)
        t2 = afilter.call(t2)
      end
      "#{SrtUtil.to_hms(t1)} --> #{SrtUtil.to_hms(t2)}"
    end
    true
  end

  # Add a delay to the srt (subtitle file)
  # Use: delay sec_offset - delay 28.3
  # If lyrics goes before sound, increase delay till sync
  # If lyrics goes after sound, decreate delay till sync
  def self.delay(file, ioffset)
    filter(file, :offset => ioffset)
  end

  def self.to_ntsc(file)
    filter(file, :scale => "29.97/25.0")
  end

  def self.to_pal(file)
    filter(file, :scale => "25.0/29.97")
  end

  def self.scale(file, scale)
    filter(file, :scale => scale)
  end

  def self.filter(file, options = {})
    afile = SrtFile.new(file)

    setOptions(options)

    if scale = getOption(:scale)
      smul, sdiv = scale.split('/')
      smul = smul.to_f
      sdiv = sdiv ? sdiv.to_f : 1.0
      afile.filters << 
        proc {|v| (v * smul / sdiv).to_i }
    end
    if ioffset = getOption(:offset)
      if ioffset =~ /^m/
        offset = ($'.gsub(/[^0-9\.]/, '').to_f * 1000).to_i
        offset = -1 * offset
      else
        offset = (ioffset.gsub(/[^0-9\.]/, '').to_f * 1000).to_i
      end
      afile.filters << 
        proc {|v| v + offset }
    end
    afile.run_filter
  end

  def self.cpscale(srtstart, srtend, vlcstart, vlcend)
    srtstart = SrtUtil.msec(srtstart).to_f
    srtend   = SrtUtil.msec(srtend).to_f
    vlcstart = SrtUtil.msec(vlcstart).to_f
    vlcend   = SrtUtil.msec(vlcend).to_f
    value = (vlcend - vlcstart)/(srtend - srtstart)
    p value
  end

  private
  def filter_lyrics
    time_ptn = Regexp.new(/^([0-9:,]+) --> ([0-9:,]+)$/)
    File.read(@file).split("\n").each do |aline|
      aline.chomp!
      if time_ptn.match(aline)
        aline = yield $1, $2
      end
      puts aline
    end
  end

end

if (__FILE__ == $0)
  SrtFile.handleCli(
    ['--offset', '-o', 1],
    ['--scale',  '-s', 1]
  )
end

exit 0
__END__

Filter the srt file for time and framerate shifting.
