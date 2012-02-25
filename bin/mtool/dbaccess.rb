#!/usr/bin/env ruby
#---------------------------------------------------------------------------
# File:        dbaccess.rb
# Date:        Sun Jan 15 22:00:13 -0800 2012
# Copyright:   E*Trade, 2012
# $Id$
#---------------------------------------------------------------------------
#++

require File.dirname(__FILE__) + "/../../etc/toolenv"
require 'active_record'
require 'mtool/core'

=begin
itune:
  drop table sources;
  create table sources(
    id integer primary key,
    name       varchar,
    base       varchar,
    search_url varchar,
    agent      varchar(20)
  );
  create unique index source_name on sources(name);
  drop table artists;
  create table artists(
    id integer primary key,
    name varchar(40)
  );
  create unique index artist_name on artists(name);
  drop table songs;
  create table songs(
    id         integer primary key,
    name       varchar,
    name_clean varchar,
    lyric_id   integer,
    artist_id  integer
  );
  create index song_name on songs(name);
  drop table lyrics;
  create table lyrics(
    id integer primary key,
    source_id integer,
    name varchar,
    name_clean varchar,
    composer varchar(40),
    content text
  );
  create unique index lyric_name_composer on lyrics(name_clean,composer);
  drop table skiplyrics;
  create table skiplyrics(
    id        integer primary key,
    source_id integer,
    song_id   integer
  );
  create unique index skip_index on skiplyrics(source_id, song_id);
  create index skip_source on skiplyrics(source_id);
  create index skip_song on skiplyrics(song_id);
=end

Connection = {
  'itune' => {
    :adapter  => 'sqlite3',
    :database => "#{ENV['HOME']}/itune-dump/itune.db",
    :pool     => 5,
    :timeout  => 5000
  }
}

module DB
  class Song < ActiveRecord::Base
  end

  class SkipLyric < ActiveRecord::Base
  end

  class Lyric < ActiveRecord::Base
    has_many :artists, :through => :songs
  end

  class Artist < ActiveRecord::Base
    has_many :lyrics, :through => :songs
  end

  class Source < ActiveRecord::Base
  end
end

class DbAccess
  extendCli __FILE__

  def self.load_from_yaml(dbconnect, table, file)
    db = connect(dbconnect)
    YAML.load_file(file).each do |record|
      cols = record.keys.join(', ')
      vals = record.values.join("', '")
      sql = "insert into #{table}(#{cols}) values('#{vals}')"
      db.execute(sql)
    end
    true
  end

  @@_dbinstance = {}
  @@_curconnect = nil
  def self.connect(name)
    unless @@_dbinstance[name]
      if test(?f, name)
        record = {
          :adapter  => 'sqlite3',
          :database => name,
          :pool     => 5,
          :timeout  => 5000
        }
        Connection[name] = record
      else
        record = Connection[name]
      end
      ActiveRecord::Base.establish_connection(record)
      @@_dbinstance[name] = ActiveRecord::Base.connection
    end
    @@_curconnect = @@_dbinstance[name]
  end

  def self.execute(sql)
    Plog.info(sql)
    @@_curconnect.execute(sql)
  end
end

if (__FILE__ == $0)
  DbAccess.handleCli
end

