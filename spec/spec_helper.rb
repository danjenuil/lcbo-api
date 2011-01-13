# This file is copied to ~/spec when you run 'ruby script/generate rspec'
# from the project root directory.
ENV['RAILS_ENV'] ||= 'test'
require File.expand_path("../../config/environment", __FILE__)
require 'rspec/rails'

# Requires supporting files with custom matchers and macros, etc,
# in ./support/ and its subdirectories.
Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each { |f| require f }

module DatabaseHelpers
  def clean_database
    DB.tables.
      reject { |table| table == :schema_info }.
      each   { |table| DB[table].delete }
  end
end

module FactoryHelpers
  def RevisionFactory(type, model_instance, opts = {})
    db = {
      :store => DB[:store_revisions],
      :product => DB[:product_revisions],
      :inventory => DB[:inventory_revisions]
    }[type]
    cols = db.columns
    data = model_instance.as_json.slice(*cols)
    if [:store, :product].include?(type)
      data[:"#{type}_id"] = model_instance.id
      data[:crawl_id]     = opts.delete(:crawl_id) || Fabricate(:crawl).id
    else
      data[:updated_on] = opts.delete(:updated_on) || Date.new(2010, 10, 10)
    end
    db.insert(data.merge(opts))
  end
end

class ActionDispatch::TestResponse
  def jsonp?
    'text/javascript' == content_type
  end

  def json?
    'application/json' == content_type
  end

  def csv?
    'text/csv' == content_type
  end

  def tsv?
    'text/tsv' == content_type
  end

  def tsv
    @tsv ||= parse_tsv
  end

  def csv
    @csv ||= parse_csv
  end

  def jsonp
    @jsonp ||= parse_jsonp
  end

  def json
    @json ||= parse_json
  end

  private

  def parse_csv
    raise "Not a CSV response: #{content_type}" unless csv?
    CSV.parse(body)
  end

  def parse_tsv
    raise "Not a TSV response: #{content_type}" unless tsv?
    CSV.parse(body, :col_sep => "\t")
  end

  def parse_json
    raise "Not a JSON response: #{content_type}" unless json?
    Yajl::Parser.parse(body, :symbolize_keys => true)
  end

  def parse_jsonp
    raise "Not a JSON-P response: #{content_type}" unless jsonp?
    json = body.scan(/\A[a-z0-9_]+\((.+)\)\;\Z/mi)[0][0]
    Yajl::Parser.parse(json, :symbolize_keys => true)
  end
end

RSpec.configure do |config|
  config.mock_with :rspec
  config.include(DatabaseHelpers)
  config.include(FactoryHelpers)
end

shared_examples_for 'a resource' do |options|
  options ||= {}

  def formatted_uri(format = nil, opts = {})
    path, query = subject.split('?')
    q = (query ? query.split('&') : [])
    opts.each { |k, v| q << "#{k}=#{v}" }
    [].tap { |uri|
      uri << (format ? "#{path}.#{format}" : path)
      uri << q.join('&') if q.any?
    }.join('?')
  end

  let(:expected_size) { options[:size] }

  describe 'as JSON (default)' do
    before { get formatted_uri(nil) }

    it 'has the correct HTTP status in the body' do
      response.status.should == 200
      response.json[:status].should == 200
    end

    it 'is JSON' do
      response.should be_json
      response.json.should be_a Hash
    end

    it 'includes the appropriate nodes' do
      response.json.keys.should_not include :error
      response.json.keys.should include :message
      response.json.keys.should include :result
    end

    it 'is the correct size' do
      response.json[:result].size.should == expected_size if expected_size
    end
  end

  describe 'as JSON' do
    before { get formatted_uri(:json) }

    it 'is JSON' do
      response.should be_json
      response.json.should be_a Hash
    end
  end

  describe 'as CSV' do
    before { get formatted_uri(:csv) }

    it 'is successful' do
      response.status.should == 200
    end

    it 'is CSV' do
      response.should be_csv
      response.csv.should be_a Array
    end

    it 'contains a header' do
      response.csv.first.should be_a Array
      response.csv.first.size.should > 0
    end

    it 'contains at least two rows' do
      response.csv.size.should > 1
    end

    it 'contains the correct number of rows' do
      (response.csv.size - 1).should == expected_size if expected_size
    end
  end

  describe 'as TSV' do
    before { get formatted_uri(:tsv) }

    it 'is successful' do
      response.status.should == 200
    end

    it 'is TSV' do
      response.should be_tsv
      response.tsv.should be_a Array
    end

    it 'contains a header' do
      response.tsv.first.should be_a Array
      response.tsv.first.size.should > 0
    end

    it 'contains at least two rows' do
      response.tsv.size.should > 1
    end

    it 'contains the correct number of rows' do
      (response.tsv.size - 1).should == expected_size if expected_size
    end
  end

  describe 'as JSON-P (with js extension)' do
    before { get formatted_uri(:js, :callback => 'test') }

    it 'is JSON-P' do
      response.should be_jsonp
      response.jsonp.should be_a Hash
    end

    it 'is successful' do
      response.status.should == 200
      response.jsonp[:status].should == 200
    end

    it 'includes a callback' do
      response.body.should include 'test({'
      response.body.should include '});'
    end
  end

  describe 'as JSON-P (implicit from presence of callback param)' do
    before { get formatted_uri(nil, :callback => 'test') }

    it 'is JSON-P' do
      response.should be_jsonp
      response.jsonp.should be_a Hash
    end
  end
end

shared_examples_for 'a JSON 404 error' do
  it 'returns a properly formed JSON error response' do
    response.status.should == 404
    response.should be_json
    response.json.should be_a Hash
    response.json[:error].should == 'not_found_error'
    response.json[:message].should be_a String
    response.json.keys.should include :result
    response.json[:status].should == 404
  end
end

shared_examples_for 'a JSON 400 error' do
  it 'returns a properly formed JSON error response' do
    response.status.should == 400
    response.should be_json
    response.json.should be_a Hash
    response.json[:error].should be_a String
    response.json[:message].should be_a String
    response.json.keys.should include :result
    response.json[:status].should == 400
  end
end
