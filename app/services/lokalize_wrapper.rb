require 'ruby-lokalise-api'
require 'uri'
require 'net/http'

class LokalizeWrapper
  include ApplicationHelper

  def initialize(token)
    @client = Lokalise.client(token)
  end

  def file_uploaded?(process)
    5.times do # try to check the status 5 times
      process = process.reload_data # load new data
      return(true) if process.status == 'finished' # return true is the upload has finished
      sleep 1 # wait for 1 second, adjust this number with regards to the upload size
    end

    false # if all 5 checks failed, return false (probably something is wrong)
  end

  def upload_to_lokalize(tool, filename)
    translatable = flatten_hash(tool.json_spec).select { |k, v| v.is_a? String }
    base64_raw = Base64.strict_encode64(translatable.to_json)

    client.upload_file(ENV['LOKALIZE_PROJECT_ID'], data: base64_raw, filename: filename, lang_iso: tool.language)
  end

  def download_from_lokalize
    download_url = client.download_files(ENV['LOKALIZE_PROJECT_ID'], format: :json)['bundle_url']
    uri = URI(download_url)
    response = Net::HTTP.get_response(uri)

    unpack_and_parse(response.body)
  end

  private

  attr_reader :client
end
