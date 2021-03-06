require 'spec_helper'

module Bookbinder
  describe Cli::Publish do
    include_context 'tmp_dirs'

    around_with_fixture_repo do |spec|
      spec.run
    end

    let(:sections) do
      [
          {'repository' => {
              'name' => 'fantastic/dogs-repo',
              'ref' => 'dog-sha'},
           'directory' => 'dogs',
           'subnav_template' => 'dogs'},
          {'repository' => {
              'name' => 'fantastic/my-docs-repo',
              'ref' => 'some-sha'},
           'directory' => 'foods/sweet',
           'subnav_template' => 'fruits'},
          {'repository' => {
              'name' => 'fantastic/my-other-docs-repo',
              'ref' => 'some-other-sha'},
           'directory' => 'foods/savory',
           'subnav_template' => 'vegetables'}
      ]
    end

    let(:config_hash) do
      {'sections' => sections,
       'book_repo' => book,
       'pdf_index' => [],
       'public_host' => 'example.com'}
    end

    let(:config) { Configuration.new(logger, config_hash) }
    let(:book) { 'fantastic/book' }
    let(:logger) { NilLogger.new }
    let(:publish_command) { Cli::Publish.new(logger, config) }
    let(:git_client) { GitClient.new(logger) }

    context 'local' do
      around do |spec|
        WebMock.disable_net_connect!(:allow_localhost => true)
        spec.run
        WebMock.disable_net_connect!
      end

      let(:dogs_index) { File.join('final_app', 'public', 'dogs', 'index.html') }

      def response_for(page)
        publish_command.run(['local'], SpecGitAccessor)

        response = nil
        ServerDirector.new(logger, directory: 'final_app').use_server do |port|
          uri = URI "http://localhost:#{port}/#{page}"
          req = Net::HTTP::Get.new(uri.path)
          response = Net::HTTP.start(uri.host, uri.port) { |http| http.request(req) }
        end
        response
      end

      it 'runs idempotently' do
        silence_io_streams do
          publish_command.run(['local'], SpecGitAccessor) # Run Once

          expect(File.exist? dogs_index).to eq true
          publish_command.run(['local'], SpecGitAccessor) # Run twice
          expect(File.exist? dogs_index).to eq true
        end
      end

      it 'creates some static HTML' do
        publish_command.run(['local'], SpecGitAccessor)

        index_html = File.read dogs_index
        expect(index_html).to include 'Woof'
      end

      it 'respects a redirects file' do
        redirect_rules = "r301 '/index.html', '/dogs/index.html'"

        expect { File.write('redirects.rb', redirect_rules) }.to change {
          response_for('index.html')
        }.from(Net::HTTPSuccess).to(Net::HTTPMovedPermanently)
      end

      context 'when provided a layout repo' do
        let(:config_hash) do
          {'sections' => sections, 'book_repo' => book, 'pdf_index' => [], 'public_host' => 'example.com', 'layout_repo' => 'such-org/layout-repo'}
        end

        it 'passes the provided repo as master_middleman_dir' do
          fake_publisher = double(:publisher)

          expect(Publisher).to receive(:new).and_return fake_publisher
          expect(fake_publisher).to receive(:publish) do |args|
            expect(args[:master_middleman_dir]).to match('layout-repo')
          end
          publish_command.run(['local'], SpecGitAccessor)
        end
      end
    end

    context 'github' do
      let(:zipped_repo_url) { "https://github.com/#{book}/archive/master.tar.gz" }
      let(:github) {"https://#{ENV['GITHUB_API_TOKEN']}:x-oauth-basic@github.com"}

      before do
        allow_any_instance_of(Repository).to receive(:get_repo_url) { |o, name | "#{github}/#{name}"}
      end

      it 'creates some static HTML' do
        publish_command.run(['github'], SpecGitAccessor)

        index_html = File.read File.join('final_app', 'public', 'foods', 'sweet', 'index.html')
        expect(index_html).to include 'This is a Markdown Page'
      end

      context 'when a tag is provided' do
        let(:desired_tag) { 'foo-1.7.12' }
        let(:cli_args) { ['github', desired_tag] }

        it 'gets the book at that tag' do
          book = double('Book', directory: 'test')
          allow(FileUtils).to receive(:chdir).with(/test$/)

          expect(Book).to receive(:from_remote).with(
                              logger: logger,
                              full_name: 'fantastic/book',
                              destination_dir: anything,
                              ref: desired_tag,
                              git_accessor: Git
                          ).and_return(book)
          publish_command.run(cli_args)
        end

        context 'the old config.yml lists fewer repos than the new config.yml' do
          let(:early_section) { 'fantastic/dogs-repo' }
          let(:another_early_section) { 'fantastic/my-docs-repo' }
          let(:later_section) { 'fantastic/my-other-docs-repo' }

          it 'calls for the old sections, but not the new sections' do
            book = double('Book')

            allow(Book).to receive(:from_remote).with(
                               logger: logger,
                               full_name: 'fantastic/book',
                               destination_dir: anything,
                               ref: 'foo-1.7.12',
                               git_accessor: Git
                           ).and_return(book)
            allow(book).to receive(:directory).and_return('test-directory')
            allow(FileUtils).to receive(:chdir).with(%r{/test-directory$})

            publish_command.run(cli_args, SpecGitAccessor)

            expect(File.read('./config.yml')).to include('dogs-repo')
            expect(File.read('./config.yml')).to include('my-docs-repo')
            expect(File.read('./config.yml')).to include('my-other-docs-repo')
          end
        end
      end

      context 'when provided a layout repo' do
        let(:config_hash) do
          {'sections' => sections,
           'book_repo' => book,
           'pdf_index' => [],
           'public_host' => 'example.com',
           'layout_repo' => 'such-org/layout-repo'}
        end

        it 'passes the provided repo as master_middleman_dir' do
          fake_publisher = double(:publisher)
          expect(Publisher).to receive(:new).and_return fake_publisher
          expect(fake_publisher).to receive(:publish) do |args|
            expect(args[:master_middleman_dir]).to match('layout-repo')
          end
          publish_command.run(['github'], SpecGitAccessor)
        end
      end

      context 'when multiple versions are provided' do
        let(:book_without_third_section) do
          RepoFixture.tarball('book', 'v1') do |dir|
            config_file = File.join(dir, 'config.yml')
            config = YAML.load(File.read(config_file))
            config['sections'].pop
            File.write(config_file, config.to_yaml)
          end
        end

        let(:versions) { %w(v1 v2) }
        let(:cli_args) { ['github'] }
        let(:config_hash) do
          {
              'versions' => versions,
              'sections' => sections,
              'book_repo' => book,
              'pdf_index' => [],
              'public_host' => 'example.com'
          }
        end
        let(:config) { Configuration.new(logger, config_hash) }
        let(:book) { 'fantastic/book' }
        let(:logger) { NilLogger.new }
        let(:publish_commander) { Cli::Publish.new(logger, config) }
        let(:temp_dir) { Dir.mktmpdir }
        let(:git_accessor_1) { SpecGitAccessor.new('dogs-repo', temp_dir) }
        let(:git_accessor_2) { SpecGitAccessor.new('dogs-repo', temp_dir) }

        it 'publishes previous versions of the book down paths named for the version tag' do
          publish_commander.run(cli_args, SpecGitAccessor)

          index_html = File.read File.join('final_app', 'public', 'dogs', 'index.html')
          expect(index_html).to include 'images/breeds.png'

          index_html = File.read File.join('final_app', 'public', 'foods', 'sweet', 'index.html')
          expect(index_html).to include 'This is a Markdown Page'

          index_html = File.read File.join('final_app', 'public', 'foods', 'savory', 'index.html')
          expect(index_html).to include 'This is another Markdown Page'

          v1_dir = File.join('final_app', 'public', 'v1')
          index_html = File.read File.join(v1_dir, 'dogs', 'index.html')
          expect(index_html).to include 'images/breeds.png'

          index_html = File.read File.join(v1_dir, 'foods', 'sweet', 'index.html')
          expect(index_html).to include 'This is a Markdown Page'
          expect(File.exist? File.join(v1_dir, 'foods', 'savory', 'index.html')).to eq false

          v2_dir = File.join('final_app', 'public', 'v2')
          index_html = File.read File.join(v2_dir, 'dogs', 'index.html')
          expect(index_html).to include 'images/breeds.png'

          index_html = File.read File.join(v2_dir, 'foods', 'sweet', 'index.html')
          expect(index_html).to include 'This is a Markdown Page'

          index_html = File.read File.join(v2_dir, 'foods', 'savory', 'index.html')
          expect(index_html).to include 'This is another Markdown Page'
        end

        context 'when a tag is at an API version that does not have sections' do
          let(:versions) { %w(v1) }
          it 'raises a VersionUnsupportedError' do
            book = double('Book')

            allow(Book).to receive(:from_remote).with(
                               logger: logger,
                               full_name: 'fantastic/book',
                               destination_dir: anything,
                               ref: 'v1',
                               git_accessor: SpecGitAccessor
                           ).and_return(book)
            allow(book).to receive(:directory).and_return('test-directory')
            allow(File).to receive(:read).with(%r{/test-directory/config.yml$}).and_return(
                               "---\nsections: ")

            expect {
              publish_command.run ['github'], SpecGitAccessor
            }.to raise_error(Cli::Publish::VersionUnsupportedError)
          end
        end
      end
    end

    describe 'invalid arguments' do
      it 'raises Cli::InvalidArguments' do
        expect {
          publish_command.run(['blah', 'blah', 'whatever'], SpecGitAccessor)
        }.to raise_error(Cli::InvalidArguments)

        expect {
          publish_command.run([], SpecGitAccessor)
        }.to raise_error(Cli::InvalidArguments)
      end
    end

    describe 'publication arguments' do
      let(:fake_publisher) { double('publisher') }
      let(:all_these_arguments_and_such) do
        {sections: sections,
         output_dir: anything,
         master_middleman_dir: anything,
         final_app_dir: anything,
         pdf: nil,
         verbose: false,
         pdf_index: [],
         local_repo_dir: anything,
         host_for_sitemap: 'example.com',
         template_variables: {},
         book_repo: 'fantastic/book',
         git_accessor: SpecGitAccessor}
      end

      before do
        expect(Publisher).to receive(:new).and_return fake_publisher
      end

      it 'are appropriate' do
        expect(fake_publisher).to receive(:publish).with all_these_arguments_and_such
        publish_command.run(['local'], SpecGitAccessor)
      end
    end
  end
end
