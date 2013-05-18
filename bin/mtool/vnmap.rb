# Mapping of Viet UTF-8 string to ASCII
class VnMap
  @@fmap, @@rmap = nil, nil

  def self.load_map(mfile)
    @@fmap = YAML.load_file(mfile)
    @@rmap = {}
    @@fmap.each do |mc, mapset|
      mapset.each do |seq|
        @@rmap[seq] = mc
      end
    end
  end

  def self.to_ascii(string)
    require 'mtool/utfstring'

    unless @@rmap
      load_map("#{ENV['EM_HOME_DIR']}/etc/vnmap.yml")
    end
    result = ""
    string.each_utf8_char do |achar|
      if mchar = @@rmap[achar]
        result << mchar
      elsif achar < 127.chr
        result << achar
      #else
        #p achar
      end
    end
    result
  end
end

class String
  def cap_words
    result = if self =~ /\s*\((.*)\)(.*)$/
      p1, p2, p3 = $`, $1, $2
      p1.cap_words + ' (' + p2.cap_words + ') ' + p3.cap_words
    else
      self.split(/[ _]+/).map {|w| w.capitalize}.join(' ')
    end
    result.strip
  end

  def vnto_ascii
    VnMap.to_ascii(self)
  end
end

