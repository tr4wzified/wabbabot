# frozen_string_literal: false

require 'active_support/all'
require_relative 'modlist'
require_relative '../errors/duplicatemodlistexception.rb'

class ModlistManager
  def initialize
    @modlists = []
    @modlist_path = "#{$root_dir}/db/modlists.json"
    initialize_json
    read_existing_lists
  end

  def add(modlist)
    raise DuplicateModlistException if @modlists.include? modlist

    @modlists.push(modlist)
    save
  end

  def del(modlist)
    @modlists.delete(modlist)
    save
  end

  def del_by_id(modlist_id)
    modlist = get_by_id(modlist_id)
    del(modlist)
  end

  def get(modlist)
    @modlists.find { |existing_modlist| existing_modlist == modlist }
  end

  def get_by_id(id)
    @modlists.find { |existing_modlist| existing_modlist.id == id }
  end

  def get_by_author_id(author_id)
    @modlists.find { |existing_modlist| existing_modlist.author_id == author_id }
  end

  def save
    File.write(@modlist_path, @modlists.to_json).positive?
  end

  def show
    modlists_str = @modlists.count == 1 ? "There is 1 modlist.\n"
                                        : "There are #{@modlists.count} modlists.\n"

    @modlists.each_with_index do |modlist, index|
      modlists_str << "#{index} - **#{modlist.title}** (`#{modlist.id}`) owned by #{modlist.author_id}.\n"
    end
    return modlists_str
  end

  private

  def read_existing_lists
    return unless File.exist?(@modlist_path)

    json = JSON.parse(File.open(@modlist_path).read)
    modlists_json = uri_to_json($settings['modlists_url'])
    json.each do |modlist|
      modlist_json = modlists_json.find { |m| m['links']['machineURL'] == modlist['id'] }
      if modlist_json.nil?
        puts "Could not find modlist #{modlist['title']} in external json!"
      else
        @modlists.push(Modlist.new_with_json(modlist['id'], modlist['author_id'], modlist_json))
      end
    end
  end

  def refresh
    modlists_json = uri_to_json($settings['modlists_url'])
    @modlists.each do |modlist|
      modlist.refresh(modlists_json)
    end
  end

  # Create directories and files if they do not exist
  def initialize_json
    modlist_dir = File.dirname(@modlist_path)
    Dir.mkdir(modlist_dir) unless Dir.exist?(modlist_dir)
    File.open(@modlist_path, 'w') { |f| f.write('{}') } unless File.exist?(@modlist_path)
  end
end

