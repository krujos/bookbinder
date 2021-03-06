require 'spec_helper'

module Bookbinder
  describe Cli::Tag do
    include_context 'tmp_dirs'

    let(:book_sha) { 26.times.map { (65 + rand(26)).chr }.join  }
    let(:desired_tag) { 12.times.map { (65 + rand(26)).chr }.join  }
    let(:book_title) { 'fantastic/red-mars' }
    let(:logger) { NilLogger.new }
    let(:config_hash) do
      {
          'book_repo' => book_title,
          'sections' => []
      }
    end
    let(:config) { Configuration.new(logger, config_hash) }
    let(:git_client) { GitClient.new(logger) }

    before do
      allow(git_client).to receive(:create_tag!)
      allow(GitClient).to receive(:new).and_return(git_client)
    end

    it 'should tag the book and its sections' do
      @book = expect_to_receive_and_return_real_now(Book, :new, {logger: logger, full_name: book_title, sections: []})
      expect(@book).to receive(:tag_self_and_sections_with).with(desired_tag)
      Cli::Tag.new(logger, config).run [desired_tag]
    end

    context 'when no tag is supplied' do
      it 'raises a Cli::InvalidArguments error' do
        expect {
          Cli::Tag.new(logger, config).run []
        }.to raise_error(Cli::InvalidArguments)
      end
    end
  end
end