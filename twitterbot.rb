#!env ruby
require "rubygems"
require "bundler/setup"

require "rmeetup"
require 'etc'
require 'twitter'
require 'sqlite3'

# http://www.meetup.com/meetup_api/oauth_consumers/

def parseConfig(fileName)
    section = key = value = ""
    config  = Hash.new

    file = File.open(fileName, "r")
    while (line = file.gets)
    #File.foreach fileName do |line|
        if line =~ /^\s*$/
        elsif line =~ /^\[(.+)\]$/
            section = $1
            config[section] = Hash.new
        elsif line =~ /^(\w+)\s*:\s*(.+)$/
            key = $1
            value = $2
            config[section][key] = value
        else
            raise "Don't know how to handle %s" % line
        end
    end
    file.close()
    return config
end

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

    msg = "%s%s @ %s - %s #vanpgg #meetup" % [ 
        isReminder ? "[Reminder] " : "",
        result.name,
        result.time.strftime("%Y-%b-%-d @ %-l%p"), 
        result.event_url
    ]

    puts msg
    Twitter.update(msg)
end

config = parseConfig(File.join(Etc.getpwuid.dir, '.vanPortGamers.conf'))

Twitter.configure do |tconfig|
    tconfig.consumer_key       = config['default']['consumer_key']
    tconfig.consumer_secret    = config['default']['consumer_secret']
    tconfig.oauth_token        = config['default']['access_token']
    tconfig.oauth_token_secret = config['default']['access_token_secret']
end

$db = SQLite3::Database.new(File.join(Etc.getpwuid.dir, '.vanPortGamers.db'))
#$db.execute("DROP TABLE IF EXISTS meetup_seen");
$db.execute("CREATE TABLE IF NOT EXISTS meetup_seen ( meetup_event_id int PRIMARY KEY, first_announce int, reminder_announce int  )");

RMeetup::Client.api_key = config['default']['meetup_key']
results = RMeetup::Client.fetch(:events,{:group_id => "1564870"})
event_ids = Array.new

results.each do |result|
    event_ids.push result.id.to_i
end

$seen_status = getStatusFromSQL(event_ids)

results.each do |result|
    postUpdate(result);
end
