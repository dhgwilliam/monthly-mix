require 'lastfm'
require 'fileutils'
require 'contracts'
require 'moneta'
require 'digest'
require 'optparse'

module MonthlyMix
  class Lastfm
    include Contracts

    Contract None => ::Lastfm
    def self.client
      return @lastfm if @lastfm

      key    = ENV['LASTFM_KEY']
      secret = ENV['LASTFM_SECRET']
      lastfm = ::Lastfm.new(key, secret)

      session_path = File.expand_path("~/.local/share/monthly-mix/session")
      token_path   = File.expand_path('~/.local/share/monthly-mix/token')

      if File.exist?(session_path)
        lastfm.session = File.read(session_path).chomp
      else
        FileUtils.mkdir_p(File.dirname(session_path))
        token =
          if File.exist?(token_path)
            File.read(token_path)
          else
            lastfm.auth.get_token
          end
        puts "http://www.last.fm/api/auth/?api_key=#{key}&token=#{token}"
        gets
        lastfm.session = lastfm.auth.get_session(token: token)['key']
        session = File.new(session_path, 'w')
        session.puts lastfm.session
      end
      @lastfm = lastfm
    end
  end

  class User
    include Contracts

    attr_reader :username

    Contract String => Any
    def initialize(username)
      @username = username
      @client = Lastfm.client
    end

    Contract None => ArrayOf[Hash]
    def weekly_chart_list
      @client.user.get_weekly_chart_list(@username)
    end

    Contract Maybe[KeywordArgs]
    def weekly_track_chart(opts = {})
      Week.new(@username, opts[:from], opts[:to])
    end
  end

  class Song
    include Contracts

    attr_reader :name, :artist, :count

    Contract Hash => Any
    def initialize(opts)
      @name = opts[:name]
      @artist = opts[:artist]
      @count = opts[:count].to_i || 0
    end

    Contract Num => Num
    def add(num)
      @count += num.to_i
    end

    Contract None => String
    def to_s
      "#{@name} by #{@artist} (#{@count})"
    end
  end

  class Chart
    include Contracts
    include Enumerable

    Contract None => Any
    def initialize
      @songs = []
    end

    Contract None => Num
    def count
      @songs.count
    end

    def each
      @songs.each {|s| yield s} 
    end

    Contract Or[ArrayOf[MonthlyMix::Song], MonthlyMix::Chart] => MonthlyMix::Chart
    def add_songs(songs)
      songs.each do |song|
        index = has_song(song)
        unless index.nil?
          #puts "adding #{song.count} plays to #{song}"
          @songs[index].add(song.count)
        else
          #puts "adding #{song}"
          @songs << song
        end
      end
      self
    end

    Contract MonthlyMix::Song => Maybe[Num]
    def has_song(song)
      @songs.find_index {|s| s.name == song.name && s.artist == song.artist}
    end

    Contract None => String
    def to_s
      @songs.sort_by {|song| song.count}.reverse.take(10).map do |song|
        song.to_s
      end.join("\n")
    end
  end

  class Week
    include Contracts

    Contract User, String, String => Any
    def initialize(user, from, to)
      @from = from
      @to = to
      @user = user
      @username = @user.username
      @client = MonthlyMix::Lastfm.client
      @chart = chart
    end

    def cache
      @cache if @cache
      dir = File.expand_path('~/.cache/monthly-mix')
      FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      @cache ||= Moneta.new(:File, dir: dir)
    end

    Contract None => ArrayOf[Hash]
    def raw_chart
      query = {user: @username, to: @to, from: @from}
      key   = Digest::SHA256.hexdigest(query.to_s)
      chart =
        if cache.key?(key)
          cache[key]
        else
          res = @client.user.get_weekly_track_chart(query)
          cache[key] = res
          res
        end


      if chart
        return [chart].flatten
      end
      []
    end

    Contract None => Chart
    def chart
      @chart if @chart

      
      return Chart.new unless raw_chart

      c = Chart.new
      songs = raw_chart.take(10).map do |s|
        MonthlyMix::Song.new(name: s['name'], artist: s['artist']['content'], count: s['playcount'])
      end
      c.add_songs(songs)
      c
    end
  end
end

options = {end: 0, weeks: 13}
op = OptionParser.new do |opts|
  opts.on('-u', '--user USER', String) do |u|
    options[:user] = u
  end
  opts.on('-s', '--start WEEKS', Integer, '# of weeks ago to start') do |s|
    options[:start] = s
  end
  opts.on('-e', '--end WEEKS', Integer, '# of weeks ago to end') do |e|
    options[:end] = e
  end
  opts.on('-w', '--weeks WEEKS', Integer, '# of weeks to combine in to a single chart') do |w|
    options[:weeks] = w
  end
end
op.parse!

unless options[:user]
  puts op
  exit 1
end

user = MonthlyMix::User.new(options[:user])
list_of_charts = user.weekly_chart_list
sliced_charts =
  if options[:start]
    start_index = -options[:start]-1
    count = options[:end]+options[:start]
    list_of_charts[start_index, count]
  else
    list_of_charts
  end
weekly_charts = sliced_charts.map do |span|
  week = MonthlyMix::Week.new(user, span['from'], span['to'])
  week.chart
end.compact

weekly_charts.each_slice(options[:weeks]) do |charts|
  c = charts.reduce(MonthlyMix::Chart.new) do |acc, chart|
    acc.add_songs(chart)
  end
  puts '---'
  puts c
end
