#!/bin/env ruby

require 'chargepoint'
require 'restclient'
require 'yaml'
require 'eventmachine'
require 'slack-ruby-bot'

Config = YAML.load_file(ENV['HOME'] + "/etc/mon_cp.yml")

if false
  Slack.configure do |config|
    config.token = Config[:slack_api_token]
  end
end

class CpBot < SlackRubyBot::Bot
  command 'ping' do |client, data, match|
    client.message text: 'pong', channel: data.channel
  end

  command 'state' do |client, data, match|
    msg = $spots.history.map do |spot, rec|
      rec.map do |time, state, free|
        "| #{spot} | #{time} | #{state} | #{free} free |"
      end.join("\n")
    end.join("\n\n")
    msg += "\n---\n" + $spots.uselist.map{|r| r.join(' | ')}.join("\n")
    client.message text:msg, channel:data.channel
  end

  command 'plugin' do |client, data, match|
    tmp, tmp, car, station = data['text'].split
    $spots.assign_last(car, station)
    puts data.inspect
  end
end


class Spots
  attr_reader :history, :uselist

  def initialize(cp_credentials, latitude, longitude)
    ChargePoint::API.authenticate(cp_credentials)
    @latitude, @longitude = latitude, longitude
    @wset    = {}
    @history = {}
    @uselist = []
  end

  def send_notification(msg)
    if false && !@client
      @client = Slack::Web::Client.new
      @client.auth_test
    end

    msg = "%s: %s" % [Time.now.strftime("%H:%M:%S"), msg]
    puts "\n" + msg
    if false
      msg = msg.gsub(/\&/, '&amp;').gsub(/</, '&lt;').gsub(/>/, '&gt;')
      @client.chat_postMessage(channel:'#chargepoint', text:msg, as_user: true)
    end
  end

  def check_charge_spots

    byebug
    now     = Time.now
    result  = ChargePoint::API.get_charge_spots(@latitude, @longitude, 0.2)
    result  = result[0]['station_list']['summaries']
    changed = false
    result.each do |astation|
      sname  = astation['station_name'].last
      avail  = astation['map_data']['level2']['free']
      msg    = nil
      if (oavail = @wset[sname]) != avail
        fcount = avail['available']
        if oavail
          if oavail['available'] < avail['available']
            state = "Car unplugged"
            emoji = "+1"
            changed = true
          elsif oavail['available'] > avail['available']
            state = "Car plugged in"
            emoji = "-1"
            changed = true
            @uselist.unshift([now, sname])
          end
        else
          state = "First time"
          emoji = ""
        end
        msg = ":#{emoji}: #{sname}: #{state} (#{fcount} free)"
        send_notification(msg)
        @wset[sname] = avail
        @history[sname] ||= []
        @history[sname].unshift([now, state, fcount])
      end
    end
    changed
  end

  def assign_last(car, nstation)
    added = false
    @uselist.each_with_index do |entry, index|
      time, station, ocar = entry
      unless ocar
        @uselist[index] = [time, station, car]
        added = true
      end
    end
    unless added
      @uselist.unshift([Time.now, nstation || "Unknown", car])
    end
  end
end

longitude = -122.1764043
latitude  = 37.4802316
$spots    = Spots.new(Config[:chargepoint], latitude, longitude)
$spots.send_notification("Starting to monitor")


EM.run do
  $spots.check_charge_spots
  timer = EM.add_periodic_timer(15) do
    begin
      $spots.check_charge_spots
      STDOUT.print "."; STDOUT.flush
    rescue => errmsg
      p errmsg
    end
  end

  if false
    cpbot = SlackRubyBot::Server.new(token:Config[:slack_api_token])
    cpbot.auth!
    cpbot.start_async
  end
end

__END__

