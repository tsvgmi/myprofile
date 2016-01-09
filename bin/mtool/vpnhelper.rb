#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        webpass.rb
# Date:        Wed Nov 07 09:23:03 PST 2007
# $Id: vpnhelper.rb 6 2010-11-26 10:59:34Z tvuong $
#---------------------------------------------------------------------------
#+++
require File.dirname(__FILE__) + "/../../etc/toolenv"
require 'mtool/core'
require 'yaml'

def grep_cmd(cmd, ptn)
  `#{cmd}`.split("\n").grep(ptn).first
end

class VpnHelper
  extendCli __FILE__

  CFILE  = "#{ENV['HOME']}/.tool/vpnset.yml"

  def initialize(dest)
    if test(?f, CFILE)
      @config = YAML.load_file(CFILE)
    end
    raise "#{CFILE} is not valid" unless @config
    @routes = @config[dest] || []
    if @routes.size <= 0
      Plog.error "No route specified for #{dest}"
    end
  end

  def self.intf_addr(intf)
    unless enip = grep_cmd("ifconfig #{intf}", /inet\s/)
      return nil
    end
    enip.split[1]
  end

#=================================================================== split
  def split(vpnif = "utun0")
=begin
--- Method: split(vpnif = "utun0")
Split the VPN by only move address range terminated to VPN to its interface
and route the rest through regular interface
*      vpnif: 
=end
    Plog.info "Waiting for tunnel #{vpnif} to get assign default route"
    while true
      if deftunnel = grep_cmd("netstat -nrf inet", /default.*#{vpnif}/)
        if deftunnel != /link/
          Plog.info "Detect #{deftunnel}"
          break
        end
      end
      sleep(1)
    end
    tunip = deftunnel.split[1]
    unless tunip
      Plog.error "No tunnel #{vpnif} detected"
      return false
    end
    gwip  = nil
    while !gwip do
      ['en0', 'en1', 'en2', 'en3', 'en4', 'en5'].each do |intf|
        next if (intf == vpnif)
        if (enip = VpnHelper.intf_addr(intf)) != nil
          if gwip = grep_cmd("netstat -nrf inet", /default.*#{intf}/)
            gwip = gwip.split[1]
          end
        end
      end
      sleep(1) unless gwip
    end
    unless gwip
      Plog.error "No non VPN interface with default gw detected. ???"
      return false
    end
    cmds = vpnroutes(vpnif, tunip)
    cmds << "route delete -net 0.0.0.0 #{tunip} 0.0.0.0"
    cmds << "route add -net 0.0.0.0 #{gwip} 0.0.0.0"
    ENV.delete('LD_LIBRARY_PATH')
    STDERR.puts cmds.inspect
    cmds.each do |acmd|
      Pf.system("sudo #{acmd}", 1)
    end
    true
  end

  def vpnroutes(vpnif, tunip)
    cmds = []
    @routes.each do |aroute|
      net, mask = aroute.split('/')
      if mask
        cmds << "route add -net #{net} #{tunip} #{mask}"
      else
        cmds << "route add -host #{net} #{tunip}"
      end
    end
    cmds
  end
end

if (__FILE__ == $0)
  VpnHelper.handleCli
end

