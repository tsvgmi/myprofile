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

  def click_and_wait(selector, wtime=3)
    begin
      Plog.info "Click on #{selector}"
      @driver.find_element(:css, selector).click
      sleep(wtime) if wtime > 0
    rescue => errmsg
      errmsg
    end
  end

  def type(selector, data)
    Plog.info "Enter on #{selector}"
    @driver.find_element(:css, selector).send_keys(data)
  end

  def goto(path)
    if path !~ /^https?:/io
      path = "#{@url}/#{path.sub(%r{^/}, '')}"
    end
    Plog.info "Goto #{path}"
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

  def find_and_click_links(lselector, rselector, options={})
    links = @page.css(lselector).map {|asong| asong['href']}
    click_links(links, rselector, options)
  end
  
  def click_links(links, rselector, options={})
    if exclude_user = options[:exclude_user]
      exclude_user = exclude_user.split(',')
    end
    links.each do |link|
      goto(link)
      if exclude_user
        auth_link = @page.css("div.song-poster-username a")[0]['href']
        uname     = File.split(auth_link)[1]
        if exclude_user.include?(uname)
          Plog.info "Skipping with exclude user"
          next
        end
      end
      @sdriver.click_and_wait(rselector, 3)
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

class SiteConnect
  def self.connect_hac(options)
    auth    = options[:auth] || 'thienv:kKtx75LUY9GA'
    identity, password = auth.split(':')
    sdriver = SDriver.new('https://hopamchuan.com')
    sdriver.click_and_wait('#login-link', 5)
    sdriver.type('#identity', identity)
    sdriver.type('#password', password)
    sdriver.click_and_wait('#submit-btn')
    sdriver
  end
end

class HACAuto
  extendCli __FILE__

  class << self
    def _connect_site
      sdriver = SiteConnect.connect_hac(getOption)
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
      options = getOption
      _connect_site do |spage|
        spage.find_and_click_links('a.hot-today-item-song',
                          '#contribute-rating-control', options)
      end
    end

    def rate_week
      options = getOption
      _connect_site do |spage|
        spage.find_and_click_links('div#weekly-monthly-list a.song-title',
                          '#contribute-rating-control', options)
      end
    end

    def rate_new
      options = getOption
      _connect_site do |spage|
        spage.find_and_click_links('div#recent-list a.song-title',
                          '#contribute-rating-control', options)
      end
    end

    def _rate_with_path(path, level, options={})
      _each_page(path) do |spage|
        spage.find_and_click_links('div.song-list a.song-title',
                          "#contribute-rating-control li:nth-child(#{level})",
                                  options)
      end
    end

    def rate_user(user, level)
      _rate_with_path("/profile/posted/#{user}", level, getOption)
    end

    def rate_rhythm(path, level=3)
      _rate_with_path("/rhythm/v/#{path}", level, getOption)
    end

    def rate_genre(path, level=3)
      _rate_with_path("/genre/v/#{path}", level, getOption)
    end

    def rate_artist(path, level=3)
      _rate_with_path("/artist/#{path}", level, getOption)
    end

    def like_user(user, nlike=3)
      options = getOption
      _each_page("/profile/posted/#{user}") do |spage|
        nlinks = []
        sitems = spage.page.css(".song-item")
        sitems.each do |sitem|
          iclasses = sitem.css('.song-like')[0].attr('class').split
          next if iclasses.include?('starred')
          nlinks << sitem.css('.song-title')[0]['href']
        end
        spage.click_links(nlinks, "#song-favorite-star-btn", options)
        sitems
      end
    end

    def get_from_hav(url)
      require 'open-uri'

      fid    = open(url)
      page   = Nokogiri::HTML(fid.read)
      fid.close
      links  = page.css('.ibar a')
      {
        lyric:  page.css('#lyric').text.strip,
        title:  page.css('.ibar h3').text.strip,
        artist: page.css('#fullsong a')[0].text.strip,
        author: links[0].text,
        genre:  links[1].text,
        source: page.css('audio')[0].css('source')[0]['src'].strip,
      }
    end

    def create_from_hav
      require 'byebug'

      _connect_site do |spage|
        while true
          STDERR.print "Enter URL to retrieve song (enter to quit): "
          STDERR.flush
          url = STDIN.gets.strip
          break if url.empty?

          info = get_from_hav(url)
          spage.click_and_wait('#create-song-link')
          spage.click_and_wait('#auto-caret-btn', 0)
          spage.type('#song-name', info[:title])
          spage.type('#song-lyric', info[:lyric])
          spage.type('#song-authors', info[:author])
          spage.type('#song-genres', info[:genre])
          spage.type('#singer-names', info[:artist])
          Plog.info "Review page to fill in remaining info and submit afterward"
        end
      end
    end
  end
end

if (__FILE__ == $0)
  HACAuto.handleCli(
    ['--auth',         '-a', 1],
    ['--exclude_user', '-x', 1],
  )
end
