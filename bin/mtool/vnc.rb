#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        vnc.rb
# $Id: vnc.rb 91 2009-03-10 00:13:42Z thien $
#---------------------------------------------------------------------------
#+++
require File.dirname(__FILE__) + "/../../etc/toolenv"
require 'yaml'
require 'mtool/core'

# Helper for vnc script.
class VncSession
  extendCli __FILE__

  include YamlConfig
  extend  YamlConfig

  UVNC_PATH = ENV['HOME'] + "/.vnc"

  attr_reader :config

  def initialize(dispno = 1)
    require 'socket'

    if dispno =~ /:/
      @dispno = dispno.sub(/^.*:/, '').to_i
    else
      @dispno = dispno.to_i
    end
    @key    = "#{Socket.gethostname}:#{@dispno}"
    obj     = VncSession.configLoad(VncSession.getOption(:config), @key)
    @config = obj ? obj.config : {:WM=>"startkde"}
  end

  public
# Start a vnc session.  The start options (size, depth, ,..) are
# defined in the configuration file.  It could be overridden here
# also.  In that case, the new options will be used and stored back
# into the configuration for future use.
# wm::       Windows manater to use.
# *options:: Any extra options to Xvnc
#
# Script options:
# --start:: [number].  Specify a start display # to start hunting
#           for free display.
  def start(wm = "", *options)
    if @dispno <= 0
      start = getOption(:start) ? getOption(:start).to_i : 1
      initialize(VncSession.huntFreeSlot(start))
    end

    wm      = (wm == "") ? @config[:WM] : wm
    Plog.trace("Starting vncserver on display #{@key} using #{wm}")
    options = (options.size > 0) ? options.join(' ') : @config[:OPTIONS]
    options = "-depth 16 -nevershared" unless options

    # Backward compatible ...
    options.gsub!(/:/, '-')

    @config[:WM]      = wm
    @config[:OPTIONS] = options
    @config.delete(:PID)
    change            = true

    command = "vncserver :#{@dispno} #{options} -name '#{@key} [#{ENV['USER']}]'"
    # A work around for tightvnc server
    if test(?e, "/usr/share/X11/rgb.txt")
      command += " -co /usr/share/X11/rgb"
    end
    [ 'GVIM', 'MSVN_ROOT', 'TOOL_DEFINED', 'T_TOOL_DIR', 'T_PROJ',
      'T_XENVSET'].each do |var|
      ENV.delete(var)
    end
    envfile = "#{UVNC_PATH}/#{@key}.env"
    File.catto(envfile, YAML.dump(ENV.to_hash))
    [ "/tmp/.X11-unix/X#{@dispno}",
      "/tmp/.X11-unix/X#{@dispno}-lock"].each do |afile|
      File.deleteForce(afile)
    end
    ENV['VNC_WM'] = wm
    VncSession.configSave(self, @key) if change
    Pf.system(command, 1)
    pidfile = "#{UVNC_PATH}/#{@key}.pid"
    isrunning = nil
    1.upto(3) do
      sleep 1
      if File.readable?(pidfile)
        Plog.trace("Found pid file. server started");
        isrunning = true
        break
      end
    end
    if isrunning
      duration = VncSession.getOption(:duration)
      if duration
        rpid =  File.read(pidfile).to_i
        Plog.info("Waiting for #{duration} for PID #{rpid}")
        sleep(duration.to_i)
        Process.kill("INT", rpid)
      end
    end
  end

# Helper function for vnc xstartup. ~/.vnc/xstartup must arrange to call
# vnc.rb svStart at the end to allow this script to setup the window
# manager support.  By default, "vnc start" will take care of that, but
# in case there are some problems ...
#
# If you invoke vnc server with the -n (name) option, you could create a
# script at ~/.vnc/xstartup-$name and it will be executed for that named
# server
#
# A typical ~/.vnc/xstartup could be as followed:
#   exec vnc.rb $DISPLAY svStart   [or]
#   exec vnc.rb --class svStart
#
# If the window manager/desktop crashed somehow, it could be restarted
# with
#   exec vnc.rb --detach $DISPLAY svStart [or]
#   exec vnc.rb --detach --class svStart
  def svStart(wm = nil)
    Pf.system('xhost +', 1)
    Pf.system('xsetroot -solid "#224488"', 1)
    if test(?r, "#{ENV['HOME']}/.Xdefaults")
      Pf.system('xrdb -merge $HOME/.Xdefaults', 1)
    end
    [ 'TOOL_DEFINED', 'SSH_CLIENT', 'SSH_CONNECTION'].each do |e|
      ENV[e] = nil
    end
    wm ||= @config[:WM] || "startkde"
    ENV['VNC_WM']      = wm
    ENV['VNC_DISPLAY'] = ENV['DISPLAY']

    pidfile = "#{UVNC_PATH}/#{@key}.pid"
    if File.readable?(pidfile)
      @config.delete(:STALE)
      @config[:PID]     = File.read(pidfile).to_i
      @config[:STARTAT] = Time.new
      VncSession.configSave(self, @key)
    else
      fod = File.open("#{UVNC_PATH}/#{@key}.pid2", "w")
      fod.close
    end

    # Clear the tool environmnet
    Pf.resetEnv

    wmcommand = wm
    case wm
    when 'twm'
      VncSession.openTerm
    when 'dtwm'
      ENV['LANG'] = 'C'
      wmcommand = "/usr/dt/bin/XSession"
    when /olv?wm/
      wmcommand = "#{wm} -3d -depth 8"
    when 'wmaker'
      wmcommand = "nohup #{wm}"
      #ENV['GNUSTEP_SYSTEM_ROOT'] = ENV['T_TOOL_DIR'] + "/GNUstep"
    end
    VncSession.openTerm
    Pf.system("vncconfig -nowin &")
    wmcommand += " &" if VncSession.getOption(:detach)
    Pf.exec(wmcommand)
  end

# Stop the vnc session (kill the process for vncserver if it is running
# Script options:
# --force:: Force kill
  def stop
    if VncSession.getOption(:force) || !@config[:STALE]
      if @config[:PID]
        pid   = @config[:PID]
        Plog.trace("Killing process #{pid}")
        begin
          Process.kill("INT", pid)
        rescue => errmsg
          p errmsg
        end
      else
        cmd = "pkill -f Xvnc.*:#{@dispno}"
        Pf.system(cmd, 1)
      end
      sleep(1)
    end
    VncSession.list
  end

  # Class methods
  class << self
    # Return a free display # to be used
    def huntFreeSlot(start)
      host     = hostname
      prefslot = []
      sessions = VncSession.configLoad(getOption(:config))
      if sessions
        sessions.keys.each do |akey|
          if akey =~ /^#{host}:(.*)$/
            dispno = $1.to_i
            if dispno >= start
              prefslot << dispno
            end
          end
        end
      end
      dispno = 0
      (prefslot.sort + (start..512).to_a).each do |i|
        # startup will delete the lock.  But may have to enable this
        # in case of weird problems
        lockfile = "/tmp/.X11-unix/X#{i}"
        next if test(?e, lockfile)
        vport, dport = 5900+i, 6000+i
        begin
          TCPSocket.new("127.0.0.1", vport)
        rescue => errmsg
          dispno = i
          break
        end
      end
      dispno
    end

    # List all live vnc session.  This only list session started with
    # 'start' method.
    def list(pattern = nil)
      require 'socket'

      format = "%-14s %-10s %5s %s"
      puts format % ["Display", "WM", "PID", "Args"]
      puts format % ["-------", "--", "---", "----"]
      sessions = VncSession.configLoad(getOption(:config))
      return unless sessions
      changed = false
      sessions.keys.sort.each do |k|
        v            = sessions[k].config
        display      = k.sub(/\..*:/, ':')
        next if (pattern && (display !~ /#{pattern}/))
        host, dispno = display.split(/:/)
        if v[:XSTALE]
          if getOption(:all)
            puts format % [display, v[:WM], "***", v[:OPTIONS]]
          end
          next
        end
        begin
          socket = TCPSocket.new(host, 5900+dispno.to_i)
          puts format % [display, v[:WM], v[:PID], v[:OPTIONS]]
          socket.close
        rescue => errmsg
          p display, errmsg
          if getOption(:all)
            puts format % [display, v[:WM], "***", v[:OPTIONS]]
          end
          v[:STALE] = true
          changed = true
        end
      end
      if changed
        Plog.info "Saving sessions"
        VncSession.configSave(sessions)
      end
      nil
    end

    # Open a terminal - type based on my preference and availability
    def openTerm
      ['konsole', 'mrxvt', 'gnome-terminal', 'xterm'].each do |aterm|
        prog = File.execPath(aterm)
        if prog
          ENV['TERMCMD'] = prog
          Pf.system("#{prog} -ls &", 1)
          break
        end
      end
    end
  
    # Run the window manager, possibly on a different display (to
    # restart a dead window manager on a runnin vnc session)
    def svStart(display = nil, wm = nil)
      ENV['DISPLAY'] = display if display
      VncSession.new(ENV['DISPLAY']).svStart(wm)
    end
  end
end

if (__FILE__ == $0)
  VncSession.handleCli(
        ["--all",      "-a"],
        ["--detach",   "-D"],
        ["--duration", "-t", 1],
        ["--display",  "-d", 1],
        ["--force",    "-f"],
        ["--name",     "-n", 1],
        ["--config",   "-C", 1, "#{ENV['HOME']}/.vnc/vncsession2.yml"],
        ["--start",    "-s", 1]) do |opt|
    (ARGV.length > 0) || VncSession.cliUsage
    session = ARGV.shift
    host, disp = session.split(/:/)
    unless disp
      host, disp = nil, host
    end
    if !host || (host == "")
      host = hostname(true)
    end
    if host == hostname(true)
      VncSession.new(disp).send(*ARGV)
    else
      cmd = "ssh -t #{host} #{__FILE__} #{VncSession.cliOptBuild} #{session} #{ARGV.join(' ')}"
      Pf.exec(cmd, 1)
    end
  end
end

