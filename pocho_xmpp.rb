# Bundler
require File.expand_path('../.bundle/environment', __FILE__)
require 'xmpp4r'
require 'xmpp4r-simple'
require 'xmpp4r/muc/helper/simplemucclient'

# Redis is the default datastore, but you can implement your own! 
# Take a look at 'pocho/datastores/dummy' to get started.
DATASTORE = :redis
require File.expand_path("../pocho/datastores/#{DATASTORE}", __FILE__)
require File.expand_path('../pocho/time', __FILE__)

# Pocho The Robot
class PochoTheRobot
  attr_accessor :ns

  # Intitialization and Jabber authentication.
  def initialize options = {}
    @logger = Logger.new(File.expand_path("../log/pocho_xmpp.log", __FILE__))

    @logger.level = ENV['DEBUG'] ? Logger::DEBUG : Logger::INFO
    jid = options[:user]
    @name, @ns = jid.split('@') # Namespace
    @ds = DataStore.new @ns

    logger.info "[Pocho] Connecting #{jid}"
    @pocho = Jabber::Simple.new(jid, options[:password])
    @rooms = options[:rooms] # MUC rooms
    @notify_with = options[:notify_with]
  end

  # Connect to all the rooms and wait for messages.
  def connect!
    @rooms.each do |room|
      Thread.new do
        muc = Jabber::MUC::SimpleMUCClient.new(@pocho.client)
        muc.on_message do |time,user,msg|
          m = parse_and_store(user, msg, Time.now, muc) unless time # Avoid msg history
          notify(muc, user) if m == :tag && @notify_with
        end
        muc.join("#{room}/Pocho The Robot")
      end
      logger.info "[Pocho] Listening for messages at #{room}..."
    end
    Thread.stop
    jabber.client.close
  end

  private

  def notify(muc, user)
    sentence = "gotcha ;)"
    case @notify_with.to_sym
    when :whisper
      muc.say(sentence, user)
    when :shout
      muc.say("#{user}: #{sentence}")
    end
  end

  # Parse the message looking for #hashtags, if there's any, it'll be stored.
  def parse_and_store user, msg, time, muc
    logger.debug "[Pocho] Processing: #{user.inspect} - #{msg.inspect}"
    msg = msg.strip

    if msg =~ /#{@name}: (.*)/
      commands = $1.split
      obey(muc, commands)
      return :command
    elsif user != 'Pocho The Robot' && tags = msg.scan(/ #[\w-]+/).map(&:strip)
      tuple = Marshal.dump([user, msg, time])
      tags.each do |tag|
        @ds.store_message_by_tag tuple, tag
        @ds.store_tag tag
      end
      @ds.store_message_by_date tuple, time
      @ds.store_message_by_user tuple, user
      return :tag
    else
      return nil
    end

    rescue Exception => e
      logger.error "[Pocho] Exception: #{e.message} | Processing: #{msg.inspect}"
      logger.error e.backtrace
  end

  def obey(muc, commands)
    case commands.first
    when "list"
      muc.say("Current tags: " + @ds.find_all_tags.join(" "))
    when "show"
      if commands.last != "show"
        @ds.find_messages_by_tag(commands.last).each_with_index do |(user, message, date), i|
          muc.say("#{i}. #{message} -- by #{user} at #{date.strftime('%d.%m.%Y %H:%M')}")
        end
      end
    end
  end

  # Logger sugar.
  def logger
    @logger
  end
end
