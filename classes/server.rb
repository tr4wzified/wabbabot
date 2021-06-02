# frozen_string_literal: true
require_relative 'channel'
class Server
  attr_reader :id, :name, :listening_channels, :list_roles

  def initialize(id, name, listening_channels = [], list_roles = {})
    @id = id
    @name = name
    @listening_channels = listening_channels
    @list_roles = list_roles
  end

  def add_channel(channel)
    @listening_channels.push(channel) unless @listening_channels.include?(channel)
  end

  def set_list_role(modlist_id, role)
    @list_roles[modlist_id] = role.to_i
  end

  def listen_to_list_in_channel(channel_id, modlist_id, auto_listen_to_new_lists = false)
    channel = @listening_channels.find { |listening_channel| listening_channel.id == channel_id }
    if channel.nil?
      channel = Channel.new(channel_id, [modlist_id], auto_listen_to_new_lists)
      listening_channels.push(channel)
    else
      channel.listen_to(modlist_id)
    end
  end

  def unlisten_to_list_in_channel(channel_id, modlist_id)
    channel = @listening_channels.find { |listening_channel| listening_channel.id == channel_id }
    return false if channel.nil?

    successful = channel.unlisten_to(modlist_id)
    @listening_channels.delete(channel) if channel.listening_to.empty?
    return successful
  end

  def get_channels_listening_to(modlist_id)
    @listening_channels.filter { |channel| channel.listening_to.include?(modlist_id) }
  end

  def to_hash
    Hash[instance_variables.map { |var| [var.to_s[1..-1], instance_variable_get(var)] }]
  end

  def ==(other)
    self.class === other && other.id == @id
  end
end
