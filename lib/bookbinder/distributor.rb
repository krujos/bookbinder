module Bookbinder
  class Distributor
    EXPIRATION_HOURS = 2

    def self.build(logger, options)
      namespace = Repository.new(logger: logger, full_name: options[:book_repo]).short_name
      namer = ArtifactNamer.new(namespace, options[:build_number], 'log', '/tmp')

      archive = Archive.new(logger: logger, key: options[:aws_credentials].access_key, secret: options[:aws_credentials].secret_key)
      command_runner = CfCommandRunner.new(logger, options[:cf_credentials], namer.full_path)
      pusher = Pusher.new(command_runner)
      new(logger, archive, pusher, namespace, namer, options)
    end

    def initialize(logger, archive, pusher, namespace, namer, options)
      @logger = logger
      @archive = archive
      @pusher = pusher
      @namespace = namespace
      @namer = namer
      @options = options
    end

    def distribute
      download if options[:production]
      push_app
      nil
    ensure
      upload_trace
    end

    private

    attr_reader :options, :archive, :namer, :namespace, :pusher

    def download
      archive.download(download_dir: options[:app_dir], bucket: options[:aws_credentials].green_builds_bucket, build_number: options[:build_number],
                       namespace: namespace)
    end

    def push_app
      warn if options[:production]
      pusher.push(options[:app_dir])
    end

    def upload_trace
      uploaded_file = archive.upload_file(options[:aws_credentials].green_builds_bucket, namer.filename, namer.full_path)
      @logger.log("Your cf trace file is available at: #{uploaded_file.url(Time.now.to_i + EXPIRATION_HOURS*60*60).green}")
      @logger.log("This URL will expire in #{EXPIRATION_HOURS} hours, so if you need to share it, make sure to save a copy now.")
    rescue Errno::ENOENT
      @logger.error "Could not find CF trace file: #{namer.full_path}"
    end

    def warn
      @logger.warn 'Warning: You are pushing to CF Docs production. Be careful.'
    end
  end
end