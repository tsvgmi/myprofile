#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        hacauto.rb
# Date:        2017-07-29 09:54:48 -0700
# Copyright:   E*Trade, 2017
# $Id$
#---------------------------------------------------------------------------
#++
require File.dirname(__FILE__) + "/../etc/toolenv"
require 'micromidi'
require 'mtool/core'

class BKSet
  extendCli __FILE__

  class ToneSetting
    class << self
      TONE_DIR   = ENV['HOME'] + "/myprofile/etc"
      INSTRUMENT = 'bk50'

      def _load_soundlist(file)
        defs = {}
        File.read(file).split("\n").each do |l|
          fs = l.split
          next unless fs.size >= 5
          sno, c0, c32, ch = fs[0], fs[-3], fs[-2], fs[-1]
          name = fs[1..-4].join(' ')
          defs[sno] = {name: name, send:"#{c0}.#{c32}.#{ch}", sno:sno}
        end
        defs
      end

      def sound(sname)
        sname = "%04d" % sname.to_i
        @sdefs ||= _load_soundlist("#{TONE_DIR}/sounds-#{INSTRUMENT}.dat")
        @sdefs[sname]
      end

      def rhymth(rname)
        rname = "%04d" % rname.to_i
        @rdefs ||= _load_soundlist("#{TONE_DIR}/rhymths-#{INSTRUMENT}.dat")
        @rdefs[rname]
      end
    end
  end

  class MidiPlay
    def self.instance
      @mobj ||= MidiPlay.new
      @mobj
    end

    def initialize
      @o = UniMIDI::Output.use(:first)
    end

    Notes = %w{C C#|Db D D#|Eb E F F#|Gb G G#|Ab A A#|Bb B}
    Major = [0, 4, 7]
    Minor = [0, 3, 7]

    def notes_for_chord(key)
      mset     = (key[-1] == 'm') ? Minor : Major
      base_ofs = Notes.index{|n| key =~ /^#{n}/}
      unless base_ofs
        Plog.error "Unknown key: #{key}"
        return []
      end
      notes = mset.map do |interval|
        offset = (base_ofs + interval) % Notes.size
        snote  = Notes[offset].split('|')[0]
        [snote+"4", snote+"5"]
      end
      notes.flatten
    end

    def sselect(plist)
      #Plog.info({plist:plist}.inspect)
      sendc = 0
      [:lower, :upper, :rhymth].each do |atype|
        if value = plist[atype]
          send_pc(atype, value)
          sendc += value.size
        end
      end
      if value = plist[:pchange]
        MIDI.using(@o) do
          pc value.to_i-1
          sleep 0.1
        end
      end
      
      sound_chord(plist[:key] || "C")
    end

    ChannelMap = {
      drum:   9,
      lower:  10,
      rhymth: 0,                # Must set in keyboard everytime
      upper:  3,
    }
    def send_pc(mtype, unos)
      MIDI.using(@o) do
        chan = ChannelMap[mtype]
        channel chan
        unos.each do |uno|
          Plog.info "C#{chan} - #{mtype}: #{uno.inspect}"
          b0, b1, c = uno[:send].split('.')
          cc 0, b0.to_i
          cc 32, b1.to_i
          pc c.to_i-1
          sleep 0.1
        end
      end
    end

    def sound_chord(key)
      sound_notes(notes_for_chord(key))
    end

    def sound_notes(notes)
      MIDI.using(@o) do
        notes.each do |ano|
          note ano
        end
        sleep 1
        cc 120, 0
      end
    end
  end

  class << self
    def apply_settings(midiplay, sinfo)
      # Sort/reverse is needed so I don't intone the percussion
      htones = (sinfo[:htones] || []).sort.reverse.
        map {|htone| ToneSetting.sound(htone) }
      ltone  = ToneSetting.sound(sinfo[:ltone])
      rhymth = ToneSetting.rhymth(sinfo[:rhymth])
      Plog.dump_info(htones:htones, ltone:ltone, rhymth:rhymth)
      midiplay.sselect(upper:htones, lower:ltone ? [ltone] : nil,
                       rhymth:rhymth ? [rhymth] : nil,
                       key:sinfo[:key])
    end

    def load_setlist(flist)
      smap  = {}
      lcnt  = 0
      YAML.load_file(flist).each.sort_by {|r|
        r[:href] ? r[:href].split('/')[5] : r[:name].downcase
      }.each_with_index do |sentry, index|
        song = sentry[:name].strip[0..31]
        if sentry[:sound]
          htones, ltone, rhymth = sentry[:sound].to_s.split(',')
          skey = "#{index+1}.#{song}"
          smap[skey] = {
            htones: (htones || '').split('/'),
            ltone:  ltone,
            rhymth: rhymth,
          }
        else
          skey = "-#{index+1}.#{song}"
          smap[skey] = {}
        end
        smap[skey].update({
          index:    lcnt+1,
          key:      sentry['key'],
          playnote: sentry['playnote'],
        })
        lcnt += 1
      end
      smap
    end

    def apply_midi(set_str)
      htones, ltone, rhythm = set_str.split(',')
      htones   = htones.split(/[\/\+]/)
      setup    = {htones:htones, ltone:ltone, rhythm:rhythm}
      Plog.dump_info(setup:setup)
      midiplay = MidiPlay.instance
      apply_settings(midiplay, setup)
    end

    def setloop(flist)
      smap     = load_setlist(flist)
      smtime   = File.mtime(flist)
      midiplay = MidiPlay.instance
      puts <<EOF
Roland BK-50 Midi SetList.
*** Remember to set rhymth in MIDI section every power on ***
EOF
      loop do
        if File.mtime(flist) > smtime
          Plog.info("#{flist} changed.  Reload")
          smap   = load_setlist(flist)
          smtime = File.mtime(flist)
        end
        aprompt = 'Select song to load [R|b|c..|l..|r..|u..]'
        song = Cli.select(smap.keys.sort) do
          ans = nil
          loop do
            $stderr.print "#{aprompt}: "
            ans = $stdin.gets.chomp
            case ans
            when /^R/
              $0 = 'Running'
              file = __FILE__
              begin
                eval "load '#{file}'", TOPLEVEL_BINDING
              rescue => errmsg
                Plog.error errmsg
              end
            when /^b/i
              require 'byebug'
              byebug
            when /^u/
              htones = $'.split('/').map{|sno| ToneSetting.sound(sno.strip)}
              midiplay.sselect(upper:htones)
            when /^l/
              ltone = ToneSetting.sound($'.strip)
              midiplay.sselect(lower:[ltone])
            when /^r/
              rhymth = ToneSetting.rhymth($'.strip)
              midiplay.sselect(rhymth:[rhymth])
            when /^c/
              midiplay.sselect(pchange:$')
            else
              break
            end
          end
          ans
        end
        break unless song
        Plog.info("Selecting #{song}: #{smap[song].inspect}")
        apply_settings(midiplay, smap[song])
      end
    end
  end
end

if (__FILE__ == $0)
  BKSet.handleCli(
    ['--channel', '-C', 1],
  )
end
