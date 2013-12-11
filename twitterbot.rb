#!/usr/bin/env ruby
require 'configatron'
require 'rmeetup'
require 'twitter'
require 'sqlite3'
require 'oauth'
require 'yaml'
require 'optparse'

$options = {
  :config => File.join(Dir.home(),'.config', 'twitterbot.conf'),
  :dbfile => File.join(Dir.home(),'.config', 'twitterbot.sqlite3')
}
OptionParser.new do |opts|
  opts.banner = "Usage: download-patv.rb [options]"
  opts.on("-c","--configfile", "configfile") do |v|
    $options[:config] = v
  end
  opts.on("-d","--dbfile", "dbfile") do |v|
    $options[:dbfile] = v
  end
  opts.on("-a","--add", "Add new group") do |v|
    $options[:add_group] = true
  end

end.parse!

# post to facebook -
# - http://stackoverflow.com/questions/4108932/whats-the-easiest-way-to-post-on-my-facebook-wall-through-my-ruby-on-rails-app/4890921#4890921
# - https://github.com/nov/fb_graph
# - http://stackoverflow.com/questions/4883699/easy-way-of-posting-on-facebook-page-not-a-profile-but-a-fanpage

# meetup -
# - http://www.meetup.com/meetup_api/

if File.exists?($options[:config])
  $config = configatron.configure_from_hash(YAML.load(File.read($options[:config])))
else
  $config = configatron.configure_from_hash({})
end
puts $config.inspect

def getStatusFromSQL(ids)
    ret = Hash.new
    return ret unless ids.count > 0
    sql = "SELECT * FROM meetup_seen WHERE meetup_event_id IN (%s)" % [ids.map { |i| "?" }.join(',')]
    $db.execute(sql, ids) do |row|
        ret[row[0].to_i] = {
            :first_announce => row[1],
            :reminder_announce => row[2]
        }
    end
    return ret
end

def postUpdate(result)

    isReminder = false
    time = Time.parse(result.time.to_s)
    if ((time.getutc.to_i - (2*60*60*24)) < Time.now.getutc.to_i)
        isReminder = true
    end

    if ($seen_status.include?(result.id.to_i))
        status = $seen_status[result.id.to_i]
        if (status[:reminder_announce].nil?)
            if (!isReminder)
#                puts "Not yet time to remind"
                return
            end
            $db.execute("UPDATE meetup_seen SET reminder_announce = ? WHERE meetup_event_id=?", Time.now.to_i, result.id.to_i)
        else
            return
        end
    else
        $db.execute("INSERT INTO meetup_seen (meetup_event_id, first_announce, reminder_announce) VALUES (?, ?, ?)",
                    result.id.to_i, Time.now.to_i, (isReminder ? Time.now.to_i : nil)
        )
    end

    hashtags = []
    hashtags = $config['hashtags'].dup if $config['hashtags']
    hashtags.push('#meetup')

    # TODO switch to #{} instead of printf
    msg = "%s%s @ %s - %s %s" % [ 
        isReminder ? "[Reminder] " : "",
        result.name,
        result.time.strftime("%Y-%b-%-d @ %-l%p"), 
        result.event_url,
        hashtags.join(' ')
    ]

    puts msg
    # TODO - reminders use :in_reply_to_status_id =>  ?
    $twitter.update(msg)
end

def write_config()
  File.open($options[:config], "w") do |f| 
    f.write $config.to_h.to_yaml
  end
end

unless $config['consumer_key']
  $stderr.puts "Enter Consumer Key:"
  $config['consumer_key'] = (gets.chomp)
  $stderr.puts "Enter Consumer Secret:"
  $config['consumer_secret'] = (gets.chomp)
  write_config()
end

if !$config['oauth_token_secret']
  c = OAuth::Consumer.new(
    $config['consumer_key'],
    $config['consumer_secret'],
    {
      :site => "https://api.twitter.com",
      :scheme => :header
    }
  )
  request_token = c.get_request_token
  $stderr.puts "\nPlease goto https://api.twitter.com/oauth/authorize?oauth_token=#{request_token.token} to register this app\n"
  $stderr.puts
  $stderr.puts "Enter PIN: "
  pin = (gets.chomp).to_i
  at = request_token.get_access_token(:oauth_verifier => pin)

  $config['oauth_token'] = at.params[:oauth_token]
  $config['oauth_token_secret'] = at.params[:oauth_token_secret]
  write_config()
end

unless $config['meetup_key']
  $stderr.puts "Enter Meetup Key (http://www.meetup.com/meetup_api/key/):"
  $config['meetup_key'] = (gets.chomp)
  write_config()
end

RMeetup::Client.api_key = $config['meetup_key']
# TODO - change this to an option
# twitterbot -a which would list ids and you can choose one
if $options[:add_group] || !$config['meetup_group_id']
  $stderr.puts "Enter Meetup Group UrlName:"
  group_name = (gets.chomp)

  $config['meetup_group_id'] ||= []
  group = RMeetup::Client.fetch(:groups, { :group_urlname => group_name })[0]
  $config['meetup_group_id'].push(group.id.to_i)
  write_config()
end

$twitter = Twitter::REST::Client.new do |tconfig|
    tconfig.consumer_key        = $config['consumer_key']
    tconfig.consumer_secret     = $config['consumer_secret']
    tconfig.access_token        = $config['oauth_token']
    tconfig.access_token_secret = $config['oauth_token_secret']
end
$twitter.verify_credentials

$db = SQLite3::Database.new($options[:dbfile])
#$db.execute("DROP TABLE IF EXISTS meetup_seen");
$db.execute("CREATE TABLE IF NOT EXISTS meetup_seen ( meetup_event_id int PRIMARY KEY, first_announce int, reminder_announce int  )");

results = RMeetup::Client.fetch(:events,{:group_id => $config['meetup_group_id'].join(',')})
event_ids = Array.new

results.each do |result|
    event_ids.push result.id.to_i
end

$seen_status = getStatusFromSQL(event_ids)

results.each do |result|
    postUpdate(result);
end
