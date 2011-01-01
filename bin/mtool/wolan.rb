#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        webpass.rb
# Date:        Wed Nov 07 09:23:03 PST 2007
# $Id: wolan.rb 6 2010-11-26 10:59:34Z tvuong $
#---------------------------------------------------------------------------
#+++
require 'socket'
require File.dirname(__FILE__) + "/../../etc/toolenv"
require 'mtool/core'

HomeMap = YAML.load <<EOD
---
vuong-pc:   ["00:11:11:67:EE:79", "192.168.1.255"]
thanh-pc:   ["00:16:CE:64:13:A6", "192.168.1.255"]
EOD

class WakeOnLan
  attr :socket

  def initialize
    @socket=UDPSocket.open()
    @socket.setsockopt(Socket::SOL_SOCKET,Socket::SO_BROADCAST,1)
  end;

  def close
    @socket.close
    @socket = ""
  end

  def wake(mac_addr, broadcast)
    wol_magic=(0xff.chr)*6+(mac_addr.split(/:/).pack("H*H*H*H*H*H*"))*16
    3.times{ @socket.send(wol_magic,0,broadcast,"discard") }
    true
  end
end

class WolClient
  extendCli __FILE__

  def self.wake(name)
    mac_addr, broadcast  = HomeMap[name]
    if broadcast
      WakeOnLan.new.wake(mac_addr, broadcast)
    else
      EmLog.error "#{name} not found"
    end
  end
end

if (__FILE__ == $0)
  WolClient.handleCli(
        ['--verbose', '-v', 0])
end

