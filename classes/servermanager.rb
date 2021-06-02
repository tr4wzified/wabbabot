# frozen_string_literal: true

require_relative 'server'
class ServerManager
  def initialize
    @servers_path = "#{$root_dir}/db/servers.json"
    @servers = []
    initialize_json
    read_existing_servers
  end

  def get_servers_listening_to_id(modlist_id)
    servers_to_return = []
    @servers.each do |server|
      server.listening_channels.each do |channel|
        servers_to_return.push(server) if channel.listening_to.include?(modlist_id) && !servers_to_return.include?(server)
      end
    end
  end

  def del_listeners_to_id(modlist_id)
    @servers.each do |server|
      server.listening_channels.each do |channel|
        channel.listening_to.reject! { |listening_modlist_id| listening_modlist_id == modlist_id }
      end
    end
    save
  end

  def unlisten(server, channel_id, modlist_id)
    server.unlisten_to_list_in_channel(channel_id, modlist_id)
    puts server.listening_channels
    @servers.delete(server) if server.listening_channels.empty?
    save
  end

  def get_server_by_id(server_id)
    @servers.find { |server| server.id == server_id }
  end

  def spawn(server_id, server_name)
    server = get_server_by_id(server_id)
    return server unless server.nil?

    server = Server.new(server_id, server_name)
    add(server)
    return server
  end

  def set_list_role_by_id(server_id, modlist_id, list_role)
    server = get_server_by_id(server_id)
    server.set_list_role(modlist_id, list_role)
    save
  end

  def add_listener_to_channel(server, channel_id, modlist_id)
    server.listen_to_list_in_channel(channel_id, modlist_id)
    save
  end

  def add(server)
    @servers.push(server)
    save
  end

  def add_channel_to_server(server_id, channel)
    server = get_server_by_id(server_id)
    server.add_channel(channel)
    save
  end

  def read_existing_servers
    return unless File.exist?(@servers_path)

    json = JSON.parse(File.open(@servers_path).read)
    json.each do |server_json|
      server = Server.new(server_json['id'], server_json['name'])
      server_json['listening_channels'].each do |listening_channel_json|
        listening_channel_json['listening_to'].each do |modlist_id|
          server.listen_to_list_in_channel(listening_channel_json['id'], modlist_id, listening_channel_json['auto_listen_to_new_lists'])
        end
      end
      server_json['list_roles'].each do |list_role_json|
        server.set_list_role(list_role_json[0], list_role_json[1].to_i)
      end
      @servers.push(server)
    end

    @servers.each { |server| puts "Server #{server.name} is listening to: #{server.listening_channels} and has roles #{server.list_roles}" }
  end

  def save
    # .positive? Makes it return a bool if succesful instead of the number of chars written
    File.write(@servers_path, @servers.to_json).positive?
  end

  def initialize_json
    server_dir = File.dirname(@servers_path)
    Dir.mkdir(server_dir) unless Dir.exist?(server_dir)
    File.open(@servers_path, 'w') { |f| f.write('{}') } unless File.exist?(@servers_path)
  end
end
