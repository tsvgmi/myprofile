#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        hacauto.rb
# Date:        2017-07-29 09:54:48 -0700
# Copyright:   E*Trade, 2017
# $Id$
#---------------------------------------------------------------------------
#++
require File.dirname(__FILE__) + "/../etc/toolenv"
require 'selenium-webdriver'
require 'nokogiri'
require 'byebug'
require 'mtool/core'

class SDriver
  attr_reader :driver

  def initialize(base_url)
    @url    = base_url
    @driver = Selenium::WebDriver.for :firefox
    @driver.navigate.to(@url)
    sleep(1)
  end

  def click_and_wait(selector)
    begin
      puts "Click on #{selector}"
      @driver.find_element(:css, selector).click
      sleep(2)
    rescue => errmsg
      errmsg
    end
  end

  def type(selector, data)
    puts "Enter on #{selector}"
    @driver.find_element(:css, selector).send_keys(data)
  end

  def goto(path)
    if path !~ /^https?:/io
      path = "#{@url}/#{path}"
    end
    puts "Goto #{path}"
    @driver.navigate.to(path)
  end

  def method_missing(method, *argv)
    @driver.send(method.to_s, *argv)
  end
end

class SPage
  attr_reader :sdriver

  def initialize(sdriver)
    @sdriver = sdriver
    refresh
  end

  def refresh
    @page = Nokogiri::HTML(@sdriver.page_source)
  end

  def click_links(lselector, rselector)
    links = []
    @page.css(lselector).each do |asong|
      link = asong['href']
      @sdriver.goto(link)
      sleep(2)
      @sdriver.click_and_wait(rselector)
      sleep(2)
      links << link
    end
    links
  end

  def goto(link)
    @sdriver.goto(link)
    refresh
  end

  def method_missing(method, *argv)
    @sdriver.send(method.to_s, *argv)
  end
end

class HACAuto
  extendCli __FILE__

  class << self
    def _connect_site
      options = getOption
      auth    = options[:auth] || 'thienv:kKtx75LUY9GA'
      identity, password = auth.split(':')
      sdriver = SDriver.new('https://hopamchuan.com')
      sdriver.click_and_wait('#login-link')
      sdriver.type('#identity', identity)
      sdriver.type('#password', password)
      sdriver.click_and_wait('#submit-btn')
      yield SPage.new(sdriver)
      sdriver.close
    end

    def rate_user(user, level)
      page = 0
      _connect_site do |spage|
        while true
          offset = page * 10
          spage.goto("/profile/posted/#{user}?offset=#{offset}")
          links = spage.click_links('div.song-list a.song-title',
                                    "#contribute-rating-control li:nth-child(#{level})")
          if links.size <= 0
            break
          end
          page += 1
        end
      end
    end

    def rate_today
      _connect_site do |spage|
        spage.click_links('a.hot-today-item-song',
                          '#contribute-rating-control')
      end
    end

    def rate_week
      _connect_site do |spage|
        spage.click_links('div#weekly-monthly-list a.song-title',
                          '#contribute-rating-control')
      end
    end

    def rate_rhythm(path)
      page = 0
      _connect_site do |spage|
        while true
          offset = page * 10
          spage.goto("/rhythm/v/#{path}?offset=#{offset}")
          links = spage.click_links('div.song-list a.song-title',
                                    '#contribute-rating-control')
          if links.size <= 0
            break
          end
          page += 1
        end
      end
    end
  end
end

if (__FILE__ == $0)
  HACAuto.handleCli(
    ['--auth', '-a', 1],
  )
end
