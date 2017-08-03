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
  attr_reader :sdriver, :page

  def initialize(sdriver)
    @sdriver = sdriver
    refresh
  end

  def refresh
    @page = Nokogiri::HTML(@sdriver.page_source)
  end

  def find_and_click_links(lselector, rselector)
    links = @page.css(lselector).map {|asong| asong['href']}
    click_links(link, rselector)
  end
  
  def click_links(links, rselector)
    links.each do |link|
      goto(link)
      sleep(2)
      @sdriver.click_and_wait(rselector)
      sleep(2)
      links << link
    end
    links
  end


  def goto(link)
    @sdriver.goto(link)
    sleep(2)
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

    def _each_page(link)
      page = 0
      _connect_site do |spage|
        while true
          offset = page * 10
          spage.goto("#{link}?offset=#{offset}")
          links = yield spage
          if !links || links.size <= 0
            break
          end
          page += 1
        end
      end
    end

    def rate_today
      _connect_site do |spage|
        spage.find_and_click_links('a.hot-today-item-song',
                          '#contribute-rating-control')
      end
    end

    def rate_week
      _connect_site do |spage|
        spage.find_and_click_links('div#weekly-monthly-list a.song-title',
                          '#contribute-rating-control')
      end
    end

    def rate_user(user, level)
      _each_page("/profile/posted/#{user}") do |spage|
        spage.find_and_click_links('div.song-list a.song-title',
                          "#contribute-rating-control li:nth-child(#{level})")
      end
    end

    def rate_rhythm(path, level=3)
      _each_page("/rhythm/v/#{path}") do |spage|
        spage.find_and_click_links('div.song-list a.song-title',
                          "#contribute-rating-control li:nth-child(#{level})")
      end
    end

    def rate_genre(path, level=3)
      _each_page("/genre/v/#{path}") do |spage|
        spage.find_and_click_links('div.song-list a.song-title',
                          "#contribute-rating-control li:nth-child(#{level})")
      end
    end

    def like_user(user, nlike=3)
      _each_page("/profile/posted/#{user}") do |spage|
        nlinks = []
        spage.page.css(".song-item").each do |sitem|
          iclasses = sitem.css('.song-like')[0].attr('class').split
          next if iclasses.include?('starred')
          nlinks << sitem.css('.song-title')[0]['href']
        end
        spage.click_links(nlinks, "#song-favorite-star-btn")
      end
    end
  end
end

if (__FILE__ == $0)
  HACAuto.handleCli(
    ['--auth', '-a', 1],
  )
end
