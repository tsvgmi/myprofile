#!/usr/bin/env ruby

$: << "/Users/thienvuong/RedCloth-4.2.9/lib"
require 'redcloth'

doc = RedCloth.new(File.read(ARGV.shift))
doc.hard_breaks = false
puts doc.to_mediawiki
