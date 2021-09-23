require 'uri'
require 'net/http'
require 'zip'
require 'ruby-lokalise-api'
require 'digest'

class ToolsController < ApplicationController
  before_action :set_tool, only: %i[ show update_translations ]

  skip_before_action :verify_authenticity_token, only: [:update_merged]

  UPLOAD_ERROR = 'Looks like translation file was not successfully uploaded'.freeze

  # GET /tools or /tools.json
  def index
    @tools = Tool.all
  end

  # GET /tools/1 or /tools/1.json
  def show
  end

  # GET /tools/new
  def new
    @tool = Tool.new
  end

  # POST /tools or /tools.json
  def create
    path = "#{tool_params[:name]}.#{tool_params[:language]}.json"
    master_path = "#{tool_params[:name]}.#{tool_params[:language]}.master.json"
    filename, spec, _ = fetch_file_if_exists(path) || fetch_file_if_exists(master_path)

    @tool = Tool.new(tool_params.merge(json_spec: spec))

    upload_process = upload_to_lokalize(@tool, filename)

    respond_to do |format|
      return format.html { render :new, status: :unprocessable_entity, notice: UPLOAD_ERROR } unless file_uploaded?(upload_process)

      if @tool.save
        format.html { redirect_to @tool, notice: "Tool was successfully created." }
      else
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  end

  # GET /tools/1/update_translations or /tools/1.json
  def update_translations
    path = "#{@tool.name}.#{@tool.language}.json"
    master_path = "#{@tool.name}.#{@tool.language}.master.json"
    filename, spec, sha = fetch_file_if_exists(path) || fetch_file_if_exists(master_path)

    updated_spec = inject_translations(spec)

    result = create_pull_request_with_translations(filename, JSON.unparse(updated_spec), sha)

    respond_to do |format|
      if result
        format.html { redirect_to @tool, notice: 'Pull request was successfully created' }
      else
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end

  def update_merged
    return unless params['pull_request']['state'] == 'closed'

    params.permit!

    title = params['pull_request']['title']
    tool_attrs = title.split('.')

    _, spec, _ = fetch_file_if_exists(title)

    Tool.find_by(name: tool_attrs[0], language: tool_attrs[1]).update(json_spec: spec)
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_tool
      @tool = Tool.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def tool_params
      params.require(:tool).permit(:name, :language)
    end

    def flatten_hash(input_hash)
      input_hash.each_with_object({}) do |(key, value), hash|
        if value.is_a? Hash
          flatten_hash(value).map do |nested_key, nested_value|
            hash["#{key}_#{nested_key}"] = nested_value
          end
        else 
          hash[key] = value
        end
      end
    end

    def github_client
      @github_client ||= Octokit::Client.new(access_token: ENV['GITHUB_TOKEN'])
    end

    def lokalize_client
      @lokalize_client ||= Lokalise.client ENV['LOKALIZE_API_KEY']
    end

    def file_uploaded?(process)
      5.times do # try to check the status 5 times
        process = process.reload_data # load new data
        return(true) if process.status == 'finished' # return true is the upload has finished
        sleep 1 # wait for 1 second, adjust this number with regards to the upload size
      end

      false # if all 5 checks failed, return false (probably something is wrong)
    end

    def fetch_file_if_exists(path)
      file = github_client.contents(ENV['REPO_NAME'], path: path)
      download_url = file[:download_url]
      uri = URI(download_url)
      response = Net::HTTP.get_response(uri)
      json_spec = JSON.parse(response.body)

      sha = file[:sha]

      [path, json_spec, sha]
    rescue Octokit::NotFound
      return nil
    end

    def create_pull_request_with_translations(filename, content, sha)
      branch_name = "#{filename}_#{Time.now.getutc.strftime('%Y%m%d%H%m%s')}"

      commit_sha = github_client.commits(ENV['REPO_NAME'], 'main').first[:sha]

      github_client.create_ref ENV['REPO_NAME'], "heads/#{branch_name}", commit_sha

      github_client.update_contents(ENV['REPO_NAME'], filename, 'Updating translations', sha, content, branch: branch_name)

      github_client.create_pull_request(ENV['REPO_NAME'], 'main', branch_name, filename, '')
    end

    def upload_to_lokalize(tool, filename)
      translatable = flatten_hash(tool.json_spec).select { |k, v| v.is_a? String }
      base64_raw = Base64.strict_encode64(translatable.to_json)

      lokalize_client.upload_file(ENV['LOKALIZE_PROJECT_ID'], data: base64_raw, filename: filename, lang_iso: tool.language)
    end

    def download_from_lokalize
      download_url = lokalize_client.download_files(ENV['LOKALIZE_PROJECT_ID'], format: :json)['bundle_url']
      uri = URI(download_url)
      response = Net::HTTP.get_response(uri)

      unpack_and_parse(response.body)
    end

    def unpack_and_parse(raw)
      translations = ""

      Zip::File.open_buffer(raw) do |zip|
        zip.each do |entry|
          next unless entry.file?

          entry.extract("/tmp/#{Time.now.getutc.strftime('%Y-%m-%d_%H:%m:%s')}")
          translations = JSON.parse(entry.get_input_stream.read)
        end
      end

      translations
    end

    def inject_translations(spec)
      resulting_spec = spec.clone

      download_from_lokalize.each do |path, translation|
        keys_array = path.split('_')
        keys_array.size > 1 ? last_key = keys_array.pop : last_key = keys_array.last

        command_string = 'resulting_spec'
        keys_array.each { |key| command_string = command_string + "['" + key + "']" }

        command_string = "#{command_string} = '#{translation}'"
        eval(command_string)
      rescue NoMethodError, IndexError
      end

      resulting_spec
    end
end
