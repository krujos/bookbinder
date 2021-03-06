require 'spec_helper'
module Bookbinder
  describe Section do
    include_context 'tmp_dirs'

    let(:logger) { NilLogger.new }

    describe '.get_instance' do
      let(:local_repo_dir) { '/dev/null' }
      let(:github) {"https://#{ENV['GITHUB_API_TOKEN']}:x-oauth-basic@github.com"}

      before do
        allow(Git).to receive(:clone).with("#{github}/foo/book",
                                            'book',
                                            anything)
        allow_any_instance_of(Repository).to receive(:get_repo_url) { |o, name | "#{github}/#{name}"}
      end

      context 'when called more than once' do
        it 'always returns the same instance for the same arguments' do
          first_instance = Section.get_instance(logger, section_hash: {'repository' => {'name' => 'foo/book'}}, local_repo_dir: local_repo_dir)
          second_instance = Section.get_instance(logger, section_hash: {'repository' => {'name' => 'foo/book'}}, local_repo_dir: local_repo_dir)
          expect(first_instance).to be(second_instance)
        end

        it 'returns different instances for different repo names' do
          first_instance = Section.get_instance(logger, section_hash: {'repository' => {'name' => 'foo/dogs-repo'}}, local_repo_dir: local_repo_dir)
          second_instance = Section.get_instance(logger, section_hash: {'repository' => {'name' => 'foo/book'}}, local_repo_dir: local_repo_dir)

          expect(first_instance).not_to be(second_instance)
        end

        it 'returns different instances for different modes' do
          local_code_repo = Section.get_instance(logger, section_hash: {'repository' => {'name' => 'foo/book'}}, local_repo_dir: 'spec/fixtures/repositories')
          remote_code_repo = Section.get_instance(logger, section_hash: {'repository' => {'name' => 'foo/book'}})

          expect(local_code_repo).not_to be(remote_code_repo)
        end
      end

      context 'in local mode' do
        context 'if the repo is present, locally' do
          let(:local_repo_dir) { 'spec/fixtures/repositories' }

          it 'copies repos from local directory' do
            expect(Section.get_instance(logger, section_hash: {'repository' => {'name' => 'foo/code-example-repo'}}, local_repo_dir: local_repo_dir)).to be_copied
          end
        end

        context 'if the repo is missing' do
          let(:local_repo_dir) { '/dev/null' }

          it 'logs a warning' do
            allow(logger).to receive(:log)
            expect(logger).to receive(:log).with /skipping \(not found\)/
            Section.get_instance(logger, section_hash: {'repository' => {'name' => 'foo/definitely-not-around'}}, local_repo_dir: local_repo_dir)
          end
        end

        context 'if the repo is not a hash' do
          let(:local_repo_dir) { 'spec/fixtures/repositories' }
            it 'raises a not a hash error message' do
            expect {
              Section.get_instance(logger, section_hash: {
                  'repository' => 'foo/definitely-not-around' }, local_repo_dir: local_repo_dir)
            }.to raise_error(RuntimeError,
                             "section repository 'foo/definitely-not-around' is not a hash")
          end
        end

        context 'if the repo name is missing' do
          let(:local_repo_dir) { 'spec/fixtures/repositories' }
          it 'raises a missing name key error message' do
            expect {
              Section.get_instance(logger, section_hash: {
                  'repository' => { some_key: 'test' }}, local_repo_dir: local_repo_dir)
            }.to raise_error(RuntimeError,
                             "section repository '{:some_key=>\"test\"}' missing name key")
          end
        end
      end

      context 'in remote mode' do
        let(:destination_dir) { tmp_subdir('output') }
        let(:repo_name) { 'great_org/dogs-repo' }

        context 'when no REF is provided' do
          let(:ref) { 'master' }
          let(:section_hash) { {'repository' => {'name' => repo_name}} }

          it 'passes nil to the Repository as the ref' do
            expect(Repository).to receive(:build_from_remote).with(logger, section_hash, destination_dir, nil, Git)
            Section.get_instance(logger, section_hash: section_hash, destination_dir: destination_dir)
          end

          it 'copies the repo from github' do
            Section.get_instance(logger, section_hash: section_hash, destination_dir: destination_dir, git_accessor: SpecGitAccessor)
            expect(File.exist? File.join(destination_dir, 'dogs-repo', 'index.html.md.erb')).to eq true
          end

          context 'and a target_tag is provided' do
            let(:target_tag) { 'oh-dot-three-dot-oh' }

            it 'uses the tag to make requests for the archive link' do
              expect(Repository).to receive(:build_from_remote).with(logger, section_hash, destination_dir, target_tag, Git)
              Section.get_instance(logger, section_hash: section_hash, destination_dir: destination_dir, target_tag: target_tag)
            end
          end
        end

        context 'when a REF is provided' do
          let(:ref) { 'foo-1.7.12' }
          let(:section_hash) { {'repository' => {'name' => repo_name, 'ref' => ref}} }

          it 'uses the provided REF to make requests for the archive link' do
            expect(Repository).to receive(:build_from_remote).with(logger, section_hash, destination_dir, nil, Git)
            Section.get_instance(logger, section_hash: section_hash, destination_dir: destination_dir)
          end

          it 'copies the repo from github' do
            Section.get_instance(logger, section_hash: section_hash, destination_dir: destination_dir, git_accessor: SpecGitAccessor)
            expect(File.exist? File.join(destination_dir, 'dogs-repo', 'index.html.md.erb')).to eq true
          end

          context 'and a target_tag is provided' do
            let(:target_tag) { 'oh-dot-three-dot-oh' }

            it 'uses the tag to make requests for the archive link' do
              expect(Repository).to receive(:build_from_remote).with(logger, section_hash, destination_dir, target_tag, Git)
              Section.get_instance(logger, section_hash: section_hash, destination_dir: destination_dir, target_tag: target_tag)
            end
          end
        end
      end
    end

    describe '#subnav_template' do
      let(:repo) { Section.new(logger, double(:repo), subnav_template_name) }

      context 'when the incoming template does not look like a partial file' do
        let(:subnav_template_name) { 'my_template' }

        it 'is unchanged' do
          expect(repo.subnav_template).to eq('my_template')
        end
      end

      context 'when the incoming template looks like a partial file' do
        let(:subnav_template_name) { '_my_tem.erbplate.erb' }

        it 'is trimmed' do
          expect(repo.subnav_template).to eq('my_tem.erbplate')
        end
      end

      context 'when the incoming template is not defined' do
        let(:subnav_template_name) { nil }

        it 'is nil' do
          expect(repo.subnav_template).to be_nil
        end
      end
    end

    describe '#get_modification_date_for' do
      let(:local_repo_dir) { '/some/dir' }
      let(:repo_name) { 'farm/my_cow_repo' }
      let(:repo) { Repository.new(full_name: repo_name, local_repo_dir: local_repo_dir) }
      subject(:section) { Section.new(logger, repo, 'my_template') }
      let(:file) { 'some-file' }
      let(:git_base_object) { double Git::Base }
      let(:time) { Time.new(2011, 1, 28) }

      context 'when publishing from local' do
        it 'creates the git object locally' do
          allow(repo).to receive(:has_git_object?).and_return(false)
          allow(repo).to receive(:get_modification_date_for).with(file: file, git: git_base_object).and_return(time)

          expect(Git).to receive(:open).with(local_repo_dir+'/my_cow_repo').and_return(git_base_object)
          expect(section.get_modification_date_for(file: file)).to eq time
        end

        it 'raises if the local repo does not exist or is not a git repo' do
          allow(repo).to receive(:has_git_object?).and_return(false)
          allow(Git).to receive(:open).with(local_repo_dir+'/my_cow_repo').and_raise
          expect { section.get_modification_date_for(file: file) }.
              to raise_error('Invalid git repository! Cannot get modification date for section: /some/dir/my_cow_repo.')
        end
      end

      context 'when publishing from remote' do
        let(:time) { Time.new(2011, 1, 28) }

        it 'gets the last modified date of the repository' do
          allow(repo).to receive(:has_git_object?).and_return(true)
          allow(repo).to receive(:get_modification_date_for).with(file: file, git: nil).and_return(time)

          expect(section.get_modification_date_for(file: file)).to eq time
        end
      end
    end
  end
end
