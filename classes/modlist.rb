# frozen_string_literal: true
require 'json'
require_relative '../helpers/webhelper'
require_relative '../errors/modlistnotfoundexception'

class Modlist
  attr_reader :id,
              :author_id,
              :author,
              :title,
              :version,
              :description,
              :image_link,
              :readme_link,
              :download_link

  # Initialize a modlist with modlist id (aka machineURL), author discord ID, array of servers
  def initialize(id, author_id, modlists_json = uri_to_json($settings['modlists_url']))
    @id = id
    @author_id = author_id
    @author = modlist_json['author']
    @title = modlist_json['title']
    @version = modlist_json['version']
    @description = modlist_json['description']
    @image_link = modlist_json['links']['image']
    @readme_link = modlist_json['links']['readme']
    @download_link = modlist_json['links']['download']
  end

  def to_hash
    Hash[instance_variables.map { |var| [var.to_s[1..-1], instance_variable_get(var)] }]
  end

  # Refresh fields coming from the modlists json, use the parameter when calling it multiple times for optimization
  def refresh(modlists_json = uri_to_json($settings['modlists_url']))
    modlist_json = modlists_json.find { |m| m['links']['machineURL'] == id }
    raise ModlistNotFoundException if modlist_json.nil?

    @author = modlist_json['author']
    @title = modlist_json['title']
    @version = modlist_json['version']
    @description = modlist_json['description']
    @image_link = modlist_json['links']['image']
    @readme_link = modlist_json['links']['readme']
    @download_link = modlist_json['links']['download']
  end

  def ==(other)
    self.class === other && other.id == @id
  end

end
