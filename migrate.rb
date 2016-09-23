#!/opt/sensu/embedded/bin/ruby

require 'net/http'
require 'json'
require 'optparse'

module Sensu
  class Api
    attr_reader :server, :port
    def initialize(server='localhost', port=4567)
      @server = server
      @port   = port
      @http   = Net::HTTP.new(@server, @port)
      @http.set_debug_output($stdout) if $DEBUG
    end

    def headers
      {'api-proxy' => 'true', 'Content-Type' => 'application/json'}
    end

    def http
      @http ||= Net::HTTP.new(@server, @port)
      @http.set_debug_output($stdout) if $DEBUG
      @http
    end

    def make_request(action, path, headers, content=false)
      if action == "get"
        req = Net::HTTP::Get.new(URI.encode(path), headers)
      elsif action == "post"
        req = Net::HTTP::Post.new(URI.encode(path), headers)
        req.body = content.to_json
      elsif action == "delete"
        req = Net::HTTP::Delete.new(URI.encode(path), headers)
      else
        raise 'Invalid Request'
      end

      begin
        http.request(req)
      rescue Timeout::Error
        puts 'HTTP request has timed out.'
        exit 1
      rescue StandardError => e
        puts 'An HTTP error occurred'
        puts e
        exit 1
      end
    end

    def get_request(path)
      make_request('get', path, headers)
    end

    def post_request(path, content)
      make_request('post', path, headers, content)
    end

    def delete_request(path)
      make_request('delete', path, headers)
    end

    def parse_response(res)
      JSON.parse(res.body)
    end

    def stashes
      return @stashes if @stashes
      res = get_request('/stashes')
      if res.code == '200'
        @stashes ||= parse_response(res)
      else
        puts "Failed with #{res.code}, #{res.body}"
        exit 1
      end
    end

    def silenced
      res = get_request('/silenced')
      if res.code == '200'
        parse_response(res)
      else
        puts "Failed with #{res.code}, #{res.body}"
        exit 1
      end
    end


    def delete_all_stashes
      stashes.each do |stash|
        delete_stash(stash['path'])
      end
    end

    def delete_stash(path)
      path = '/' + path unless path.start_with?('/')
      res = delete_request('/stashes' + path)
      if res.code == '204'
        puts "The stash at #{path} was successfully deleted."
      else
        puts "stash at #{path} could not be deleted. Failed with #{res.code}, #{res.body}"
      end
    end


    def create_silenced(content)
      res = post_request('/silenced', content)
      silenced_id = content.fetch(:id)
      if res.code == '201'
        puts "The silenced entry created for #{silenced_id}"
      else
        puts "silence entry for #{silenced_id} could not be created. Failed with #{res.code}, #{res.body}"
      end
    end

    def stash_to_silenced
      stashes.each do |stash|
        _, client, check = stash['path'].split('/')
        content = {}
        content.merge!(:subscription => "client:#{client}")
        content.merge!(:check => check) if !check.nil?
        content.merge!(:expire => stash['content'].fetch('expire', 3600)) if stash['content'].key?('expire')
        content.merge!(:reason => "testing")
        content.merge!(:creator => "vjain")
        content.merge!(:expire_on_resolve => false)
        subscription = content.fetch(:subscription, "*")
        check = content.fetch(:check, "*")
        silenced_id = "#{subscription}:#{check}"
        content.merge!(:id => silenced_id)
        create_silenced(content)
      end
    end

    def run
      stash_to_silenced
      delete_all_stashes
    end
  end
end

def parse_options
  options = {:server => 'localhost'}
  
  parser = OptionParser.new do |opts|
    opts.banner = "Usage: migrate.rb [options]"
    opts.on("-s", "--server server", "Sensu Server") do |server|
      options[:server] = server
    end
    opts.on("-h", "--help", "Help") do |server|
      puts opts
      exit 1
    end
    opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
        options[:verbose] = v
    end
  end
  
  parser.parse!
  options
end

def stash_to_silence_migrate
  options = parse_options
  $DEBUG = options[:verbose]
  Sensu::Api.new(options[:server]).run
end

stash_to_silence_migrate
