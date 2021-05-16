#!/usr/bin/ruby
# frozen_string_literal: false

require 'discordrb'
require 'slop'
require 'uri'
require_relative 'helpers/webhelper'
require_relative 'helpers/typehelper'
require_relative 'classes/modlistmanager'
require_relative 'classes/servermanager'
require_relative 'errors/modlistnotfoundexception'
require_relative 'errors/duplicatemodlistexception'

$root_dir = __dir__.freeze

opts = Slop.parse do |arg|
  arg.string '-p', '--prefix', 'prefix to use for @bot commands', default: '!'
  arg.on '-h', '--help' do
    puts arg
    exit
  end
  arg.on '--version', 'print the version' do
    puts Slop::VERSION
    exit
  end
  arg.bool '-P', '--production', 'enable production mode (keep a logfile)', default: false
end

if opts[:production]
  $stdout.reopen("#{$root_dir}/db/logfile", 'w')
  $stdout.sync = true
  $stderr.reopen($stdout)
end

prefix = proc do |message|
  p = opts[:prefix]
  message.content[p.size..-1] if message.content.start_with? p
end

settings_path = "#{$root_dir}/db/settings.json"
$settings = JSON.parse(File.open(settings_path).read).freeze
@modlistmanager = ModlistManager.new
@servermanager = ServerManager.new
last_release_messages = {}

@bot = Discordrb::Commands::CommandBot.new(
  token: $settings['token'],
  client_id: $settings['client_id'],
  prefix: prefix
)

puts "Running WabbaBot with invite URL: #{@bot.invite_url}."

@bot.command(
  :listen,
  description: 'Listen to new modlist releases from the specified list in the specified channel',
  usage: "#{opts[:prefix]}listen <modlist id> <channel>",
  min_args: 1
) do |event, modlist_id, channel|
  manage_roles_only(event)

  modlist = @modlistmanager.get_by_id(modlist_id)
  error(event, "Modlist with id #{modlist_id} not found") if modlist.nil?

  server = @servermanager.spawn(event.server.id, event.server.name)
  channel = get_server_channel_for_channel(event, channel)
  @servermanager.add_channel_to_server(event.server.id, Channel.new(channel.id))
  return "Now listening to **#{modlist.title}** in #{channel.name}." if @servermanager.add_listener_to_channel(server, channel.id, modlist_id)
end

@bot.command(
  :unlisten,
  description: 'Stop listening to new modlist releases from the specified list in the specified channel',
  usage: "#{opts[:prefix]}unlisten <modlist id> <channel>",
  min_args: 2
) do |event, modlist_id, channel|
  error(event, 'This server is not listening to any modlists yet') if (server = @servermanager.get_server_by_id(event.server.id)).nil?
  channel = get_server_channel_for_channel(event, channel)
  error(event, "Modlist with id #{modlist_id} does not exist") if (modlist = @modlistmanager.get_by_id(modlist_id)).nil?
  return "No longer listening to #{modlist.title} in #{channel.name}." if @servermanager.unlisten(server, channel.id, modlist_id)
end

@bot.command(
  :showlisteners,
  description: 'Shows all servers and channels listening to the specified modlist',
  usage: "#{opts[:prefix]}showlisteners <modlist id>",
  min_args: 1
) do |event, modlist_id|
  admins_only(event)

  message = ''
  error(event, "Modlist with id #{modlist_id} not found") if (modlist = @modlistmanager.get_by_id(modlist_id)).nil?
  error(event, 'There are no servers listening to this modlist') if (servers = @servermanager.get_servers_listening_to_id(modlist_id)).nil?
  servers.each do |server|
    message << "Server #{server.name} (`#{server.id}`) is listening to #{modlist.title} in the following channels: "
    channels = server.get_channels_listening_to(modlist_id)
    channels.each do |channel|
      message << "`#{channel.id}` "
    end
    message << "\n"
  end
  return message
end

@bot.command(
  :release,
  description: 'Put out a new release of your list',
  usage: "#{opts[:prefix]}release <modlist id> <message>",
  min_args: 1
) do |event, modlist_id|
  modlistmanager_json = uri_to_json($settings['modlists_url'])

  modlist = @modlistmanager.get_by_id(modlist_id)
  error(event, "Modlist with id #{modlist_id} not found") if modlist.nil?
  error(event, 'You\'re not managing this list') unless event.author.id == modlist.author_id || $settings['admins'].include?(event.author.id)

  message = event.message.content.delete_prefix("#{opts[:prefix]}release #{modlist_id}")

  listening_servers = @servermanager.get_servers_listening_to_id(modlist_id)
  error(event, 'There are no servers listening to this modlist') if listening_servers.empty?
  channel_count = 0
  modlist.refresh
  sent_messages = []
  listening_servers.each do |listening_server|
    server = @bot.servers[listening_server.id]
    listening_server.listening_channels.each do |channel|
      next unless channel.listening_to.include? modlist_id

      channel_to_post_in = server.channels.find { |c| c.id == channel.id.to_i }
      channel_count += 1
      message = channel_to_post_in.send_embed do |embed|
        embed.title = "#{event.author.username} just released #{modlist.title} #{modlist.version}!"
        embed.colour = 0xbb86fc
        embed.timestamp = Time.now
        embed.description = message
        embed.image = Discordrb::Webhooks::EmbedImage.new(url: modlist.image_link)
        embed.footer = Discordrb::Webhooks::EmbedFooter.new(text: 'WabbaBot')
      end
      sent_messages.push(message)
      channel_to_post_in.send_message("<@&#{listening_server.list_roles[modlist.id]}>") if listening_server.list_roles.include?(modlist.id)
    end
  end
  last_release_messages[modlist_id] = sent_messages if sent_messages.any?
  puts "Last release messages: #{last_release_messages}"
  channel_count.positive? ? "Modlist was released in #{channel_count} channels!" : error(event, 'Failed to release modlist in any servers')
end

@bot.command(
  :revise,
  description: 'Revise/edit the last release messaage for this list',
  usage: "#{opts[:prefix]}revise <modlist id> <new message>",
  min_args: 2
) do |event, modlist_id, new_message|
  modlist = @modlistmanager.get_by_id(modlist_id)
  error(event, "Modlist with id #{modlist_id} not found") if modlist.nil?
  error(event, 'You\'re not managing this list') unless event.author.id == modlist.author_id || $settings['admins'].include?(event.author.id)
  error(event, 'Could not edit last message for this list - was there one?') unless last_release_messages.key? modlist_id

  new_message = event.message.content.delete_prefix("#{opts[:prefix]}revise #{modlist_id} ")

  embed = Discordrb::Webhooks::Embed.new
  embed.title = "#{event.author.username} just released #{modlist.title} #{modlist.version}!"
  embed.colour = 0xbb86fc
  embed.timestamp = Time.now
  embed.description = new_message
  embed.image = Discordrb::Webhooks::EmbedImage.new(url: modlist.image_link)
  embed.footer = Discordrb::Webhooks::EmbedFooter.new(text: 'WabbaBot')

  last_release_messages[modlist_id].each do |release_message|
    release_message.edit(release_message.content, embed)
  end
  return "Succesfully revised #{last_release_messages[modlist_id].length} release messages for #{modlist.title}!"
end


@bot.command(
  :addmodlist,
  description: 'Adds a new modlist',
  usage: "#{opts[:prefix]}addmodlist <modlist id> <user>",
  min_args: 2
) do |event, id, user|
  admins_only(event)

  member = get_member_for_user(event, user)
  error(event, "I can't manage a modlist myself") if member.id == $settings['client_id']
  modlist = nil
  begin
    modlist = Modlist.new(id, member.id)
  rescue ModlistNotFoundException => e
    error(event, e.message)
  end

  begin
    return "Modlist **#{modlist.title}** managed by **#{member.username}** was added to the database." if @modlistmanager.add(modlist)

    error(event, "Failed to add modlist #{id} to the database")
  rescue DuplicateModlistException => e
    error(event, e.message)
  end
end

@bot.command(
  :delmodlist,
  description: 'Deletes a modlist',
  usage: "#{opts[:prefix]}delmodlist <modlist id>",
  min_args: 1
) do |event, id|
  admins_only(event)

  error(event, "Modlist #{id} does not exist!") if (modlist = @modlistmanager.get_by_id(id)).nil?
  return "Modlist `#{modlist.title}` was deleted." if @servermanager.del_listeners_to_id(id) && @modlistmanager.del(modlist)
end

@bot.command(
  :setrole,
  description: 'Sets the role to ping for when the specified modlist releases a new version',
  usage: "#{opts[:prefix]}setrole <modlist id> <role>",
  min_args: 2
) do |event, id, role|
  manage_roles_only(event)

  role = get_server_role_for_role(event, role)
  modlist = @modlistmanager.get_by_id(id)
  error(event, "Modlist #{id} could not be found in the database") if modlist.nil?
  error(event, "This server is not listening to any channels yet for list #{modlist.title}") if @servermanager.get_servers_listening_to_id(id).find { |s| s.id == event.server.id }.nil?
  return "Releases for #{modlist.title} will now ping the #{role.name} role!" if @servermanager.set_list_role_by_id(event.server.id, id, role.id)
end

@bot.command(
  :showmodlists,
  description: 'Presents a list of all modlists',
  usage: "#{opts[:prefix]}showmodlists"
) do |event|
  manage_roles_only(event)

  event.channel.split_send(@modlistmanager.show)
end

def error(event, message)
  error_msg = "An error occurred! **#{message}.**"
  @bot.send_message(event.channel, error_msg)
  raise error_msg
end

# Error out when someone calls this method and isn't a bot administrator
def admins_only(event)
  author = event.author
  error_msg = 'This command is reserved for bot administrators'
  error(event, error_msg) unless $settings['admins'].include? author.id
end

# Error out when someone calls this method and isn't a bot administrator or a person that can manage roles
def manage_roles_only(event)
  author = event.author
  error_msg = 'This command is reserved for people with the Manage Roles permission'
  error(event, error_msg) unless author.permission?(:manage_roles) || $settings['admins'].include?(author.id)
end

def get_server_channel_for_channel(event, channel)
  # Format of channel: <#717201910364635147>
  error(event, 'Invalid channel provided') unless (match = channel.match(/<#([0-9]+)>/))
  error(event, 'Channel does not exist in server') if (server_channel = event.server.channels.find { |c| c.id == match.captures[0].to_i }).nil?
  return server_channel
end

def get_member_for_user(event, user)
  # Format of user: @<185807760590372874>
  match = user.match(/<@!?([0-9]+)>/)
  user_id = match.nil? ? user.to_i : match.captures[0].to_i
  error(event, 'User does not exist in server') if (member = event.server.members.find { |m| m.id == user_id }).nil?
  return member
end

def get_server_role_for_role(event, role)
  # Format of role: <@&812762942260904016>
  match = role.match(/<@&?([0-9]+)>/)
  role_id = match.nil? ? role.to_i : match.captures[0].to_i
  error(event, 'Role does not exist in server') if (server_role = event.server.roles.find { |r| r.id == role_id }).nil?
  return server_role
end


@bot.run
