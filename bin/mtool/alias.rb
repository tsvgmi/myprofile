#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        alias.rb
# Date:        Sat Nov 17 15:31:23 -0800 2007
# $Id: alias.rb 16 2008-05-28 18:24:58Z tvuong $
#---------------------------------------------------------------------------
#+++
require File.dirname(__FILE__) + "/../../etc/toolenv"
require 'mtool/core'

# I use alias a lot to simplify shell use.  But alias creation, sourcing,
# sync across different shells are a pain.  You edit various .alias,
# resource them in all opened windows, ...  So this is created.  It is
# supposed to be used in conjunction with a few shell functions: genalias(
# and realias () defines under myprofile
# 
# Use:
# * (Optional) realias to bring the current shell alias up to date.
#   Note if this is not done and there were newly alias saved on a different
#   shell, subsequent genalias in this shell would think that those are
#   deleted aliases and would not save them/mark them as such so they
#   could never be saved again.
# * Create an alias manually
# * genalias to save it to alias file
# * realias is added to .profile to load list at each login
#
# genalias() generates all aliases into common, or OS specific alias
# realias() resource all aliases from those files.
#
class Alias
  extendCli __FILE__

  attr_reader :dellist, :valias, :oldlist, :version
  attr_accessor :valias

  def initialize(cfile)
    @cfile = cfile
    if File.readable?(@cfile)
      config   = YmlConfig.new(@cfile)
      @valias  = config.valias
      @oldlist = config.valias
      @dellist = config.dellist
      @version = config.version || 0
    else
      @valias  = {}
      @oldlist = {}
      @dellist = {}
      @version = 0
      Alias.setOptions(:force=>true)
    end
  end

  private
  def _saveSelf
    oldlist      = @oldlist
    @oldlist     = {}
    sdata        = YmlConfig.new(@cfile)
    sdata.config = self.dup
    sdata.config.valias = nil
    sdata.save
    fod = File.open(sdata.cfile, "a")
    fod.puts "valias: "
    valias.keys.sort.each do |k|
      v = valias[k]
      fod.puts "  #{k}:"
      v.each do |vl|
        fod.puts "  - \"#{vl}\""
      end
    end
    fod.close
    @oldlist     = oldlist
  end

  public
# Some aliases are always generated at runtime, and should not be saved.
# This command register them so when make is run, it would not be restored
# again.
# names:: List of names never to save
  def remove(*names)
    names.each do |name|
      Plog.info("Add #{name} in ignorelist")
      @dellist[name] = ["IGNORE", Time.new]
    end
    _saveSelf
  end

  # Un-remove a deleted alias by removing it from the deleted list
  def unrm(*names)
    has_restored = false
    names.each do |name|
      v = @dellist[name]
      if v
        puts "alias #{name}=#{v[0]}"
        has_restored = true
        @dellist.delete(name)
      end
    end
    if has_restored
      _saveSelf
    end
    nil
  end

  def showRemoved(pattern = nil)
    @dellist.each do |name, value|
      if pattern
        next unless (name =~ /#{pattern}/)
      end
      puts "#{name} => #{value[0]}"
    end
    nil
  end

  private
  # Write the alias list into the specified output file
  def writeAliasFile(ofile, aliasList, version, csh=false)
    File.open(ofile, "w") do |fod|
      aliasList.keys.sort.each do |akey|
        value = aliasList[akey][0]
        next if (akey == '_ALIAS_VERSION')
        fod.puts csh ? "alias #{akey} #{value}" : "alias #{akey}=#{value}"
      end
      fod.puts csh ? "alias _ALIAS_VERSION #{version}" :
                     "alias _ALIAS_VERSION=#{version}"
    end
  end

  def loadAliasDump(newalias_dump)
    newlist  = {}               # As given from input dump
    validset = false
    @oldlist ||= {}
    @valias ||= {}
    File.foreach(newalias_dump) do |aline|
      if aline =~ /^alias/
        tmp, name, value = aline.chop.split(/[ =]/, 3)
      else
        # This form is for csh variants
        name, value = aline.chop.split(/[ =]/, 2)
        value = "'#{value}'"
      end
      if (name == '_ALIAS_VERSION')
        unless Alias.getOption(:force)
          if "'#{@version}'" != value
            raise "Alias version mismatch #{value}:#{@version}.  Please reload first"
          end
        end
        validset = true
      end
      # Skip processing the deleted one.  It could be deleted
      # in one shell and save on another shell.
      if @dellist[name]
        Plog.info("#{name} was deleted before.  Skip")
        next
      end
      
      # This is existing name.  Move it to the newlist
      if (!@oldlist[name]) || (!@oldlist[name][1])
        newlist[name] = [value, nil]
      else
        newlist[name] = [value, @oldlist[name][1]]
      end
      @valias[name] = newlist[name]             # Update the global list
    end
    if !validset && !Alias.getOption(:force)
      raise "Alias not loaded.  Please reload first"
    end
    newlist
  end

  public
  # Generate the alias file based on the new alias list and the existing
  # file.  Removed alias are saved into delete list (so the next make from
  # a different window with those alias still defined won't undo the
  # delete one).  ** Deprecate in favor of make2 ***
  def make(newalias_dump, *oldfiles)
    newlist = Alias.getOption(:newalias) ?
                        @oldlist :
                        loadAliasDump(newalias_dump)

    # Check for the any newly removed items.
    (@oldlist.keys - newlist.keys).each do |k|
      Plog.info("Alias #{k} removed")
      v = @oldlist[k]
      @dellist[k] = [v[0], v[1], Time.new]
      @valias.delete(k)
    end

    oldfiles.each do |oldalias_file|
      ownlist  = {}               # For my file alias list
      ofile = File.basename(oldalias_file)

      newlist.each do |name, val|
        if !val[1]
          newlist[name] = [val[0], ofile]
          ownlist[name] = newlist[name]
        elsif val[1] == ofile
          ownlist[name] = newlist[name]
        end
      end
      ofile = oldalias_file + ".new"
      writeAliasFile(ofile, ownlist, @version+1, Alias.getOption(:csh))
      File.deleteForce(oldalias_file)
      File.rename(ofile, oldalias_file)
      Plog.info("Alias version #{@version+1} written to #{oldalias_file}")
    end
    @version += 1
    _saveSelf
    nil
  end

  def make2(oldfile)
    newalias = Alias.getOption(:newalias)
    newlist  = newalias ? loadAliasDump(newalias) : @oldlist

    # Check for the any newly removed items.
    (@oldlist.keys - newlist.keys).each do |k|
      Plog.info("Alias #{k} removed")
      v = @oldlist[k]
      @dellist[k] = [v[0], v[1], Time.new]
      @valias.delete(k)
    end

    file0 = File.basename(oldfile)
    flist = [file0]
    newlist.each do |name, val|
      if !val[1] || (val[1] == "")
        newlist[name] = [val[0], file0]
      else
        flist << val[1]
      end
    end

    flist.uniq.each do |oldalias_file|
      ownlist = {}               # For my file alias list
      ofile   = File.basename(oldalias_file)
      newlist.each do |name, val|
        if val[1] == ofile
          ownlist[name] = newlist[name]
        end
      end
      ofile = oldalias_file + ".new"
      writeAliasFile(ofile, ownlist, @version+1, Alias.getOption(:csh))
      File.deleteForce(oldalias_file)
      File.rename(ofile, oldalias_file)
      Plog.info("Alias version #{@version+1} written to #{oldalias_file}")
    end
    @version += 1
    _saveSelf
    nil
  end

  def self.cliNew
    new(File.expand_path("~/.alias.yml"))
  end
end

if (__FILE__ == $0)
  Alias.handleCli(['--csh',      '-C'],
                  ['--force',    '-f'],
                  ['--newalias', '-n', 1])
end

