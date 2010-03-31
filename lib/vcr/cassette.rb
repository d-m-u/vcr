require 'fileutils'
require 'yaml'

module VCR
  class Cassette
    VALID_RECORD_MODES = [:all, :none, :new_episodes].freeze

    attr_reader :name, :record_mode

    def initialize(name, options = {})
      @name = name
      @record_mode = options[:record] || VCR::Config.default_cassette_options[:record]
      deprecate_unregistered_record_mode
      @allow_real_http_lambda = allow_real_http_lambda_for(options[:allow_real_http] || VCR::Config.default_cassette_options[:allow_real_http])
      self.class.raise_error_unless_valid_record_mode(record_mode)
      set_http_connections_allowed
      load_recorded_responses
    end

    def eject
      write_recorded_responses_to_disk
      unstub_requests
      restore_http_connections_allowed
    end

    def recorded_responses
      @recorded_responses ||= []
    end

    def store_recorded_response!(recorded_response)
      recorded_responses << recorded_response
    end

    def file
      File.join(VCR::Config.cassette_library_dir, "#{name.to_s.gsub(/[^\w\-\/]+/, '_')}.yml") if VCR::Config.cassette_library_dir
    end

    def self.raise_error_unless_valid_record_mode(record_mode)
      unless VALID_RECORD_MODES.include?(record_mode)
        raise ArgumentError.new("#{record_mode} is not a valid cassette record mode.  Valid options are: #{VALID_RECORD_MODES.inspect}")
      end
    end

    def allow_real_http_requests_to?(uri)
      @allow_real_http_lambda ? @allow_real_http_lambda.call(uri) : false
    end

    def new_recorded_responses
      recorded_responses - @original_recorded_responses
    end

    def should_allow_http_connections?
      [:new_episodes, :all].include?(record_mode)
    end

    def set_http_connections_allowed
      @orig_http_connections_allowed = VCR::Config.http_stubbing_adapter.http_connections_allowed?
      VCR::Config.http_stubbing_adapter.http_connections_allowed = should_allow_http_connections?
    end

    def restore_http_connections_allowed
      VCR::Config.http_stubbing_adapter.http_connections_allowed = @orig_http_connections_allowed
    end

    def load_recorded_responses
      @original_recorded_responses = []
      return if record_mode == :all

      if file
        @original_recorded_responses = File.open(file, 'r') { |f| YAML.load(f.read) } if File.exist?(file)
        recorded_responses.replace(@original_recorded_responses)
      end

      VCR::Config.http_stubbing_adapter.stub_requests(recorded_responses)
    end

    def write_recorded_responses_to_disk
      if VCR::Config.cassette_library_dir && new_recorded_responses.size > 0
        directory = File.dirname(file)
        FileUtils.mkdir_p directory unless File.exist?(directory)
        File.open(file, 'w') { |f| f.write recorded_responses.to_yaml }
      end
    end

    def unstub_requests
      VCR::Config.http_stubbing_adapter.unstub_requests(@original_recorded_responses)
    end

    def allow_real_http_lambda_for(allow_option)
      if allow_option == :localhost
        lambda { |uri| uri.host == 'localhost' }
      else
        allow_option
      end
    end
  end
end