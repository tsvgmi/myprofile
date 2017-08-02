#!/bin/env ruby

$: << ENV['HOME'] + "/bin"
require ENV['HOME'] + '/etc/toolenv'

require 'yaml'
require 'fileutils'
require 'mtool/core'

class Hopam
  extendCli __FILE__

  def self.bracket_chords(file='-')
    input = (file == '-') ? STDIN.read : File.read(file)
    input.split('\n').map do |l|
      l.gsub(/\b([A-G](#|b)?m?((min|maj|sus|dim)?[4679]?))\b/, '[\1]')
        .gsub(%r{([A-G])\](#|b)}, '\1\2]')
        .gsub(%r{\]/\[}, '/')
        .gsub(%r{\](m?)7b5}, '\17b5]')
    end.join('\n')
  end

  RootMap = [
    {
      root:     %w[C# A#m D Bm E C#m G Em A F#m B G#m],
      sequence: %w[A A# B C C# D D# E F F# G G#],
    }, {
      root:     %w[Db Abm Eb Cm F Dm Ab Fm Bb Gm],
      sequence: %w[A Bb B C Db D Eb E F Gb G Ab],
    }
  ]

  def self.transpose(steps, croot)
    cmap    = root_map(croot)
    newroot = croot + steps
    new_map = root_map(newroot)
    old_set.chords.each do |old_chord|
      new_chord = old_chord + steps
      new_chord = new_map.adapt(new_chord)
    end
  end

  def self.extract_hopamchuan(file)
    require 'open-uri'
    require 'nokogiri'

    content = open(file).read
    doc     = Nokogiri::HTML.parse(content)
    doc.css(".chord_lyric_line").each {|dline|
      tokens = []
      dline.css(".hopamchuan_lyric, .hopamchuan_chord_inline").each {|div|
        tokens << div.text.gsub(/\r/, '').strip
      }
      puts tokens.join(' ').strip
    }
    true
  end

  def self.extract_hopamviet(file)
    require 'open-uri'
    require 'nokogiri'

    content = open(file).read
    doc     = Nokogiri::HTML.parse(content)
    doc.css(".chord_lyric_line").each {|dline|
      tokens = []
      dline.css(".hopamchuan_lyric, .hopamchuan_chord_inline").each {|div|
        tokens << div.text.gsub(/\r/, '').strip
      }
      puts tokens.join(' ').strip
    }
    true
  end

end

if (__FILE__ == $0)
  Hopam.handleCli(
    ['--dups',   '-D', 0],
  )
end

