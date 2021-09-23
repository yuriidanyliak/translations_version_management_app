class ToolsController < ApplicationController
  include ApplicationHelper

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
    filename, spec, _ = github_wrapper.fetch_file_if_exists(path) || github_wrapper.fetch_file_if_exists(master_path)

    @tool = Tool.new(tool_params.merge(json_spec: spec))

    upload_process = lokalize_wrapper.upload_to_lokalize(@tool, filename)

    respond_to do |format|
      return format.html { render :new, status: :unprocessable_entity, notice: UPLOAD_ERROR } unless lokalize_wrapper.file_uploaded?(upload_process)

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
    filename, spec, sha = github_wrapper.fetch_file_if_exists(path) || github_wrapper.fetch_file_if_exists(master_path)

    updated_spec = inject_translations(spec)

    result = github_wrapper.create_file_and_open_pr(filename, JSON.unparse(updated_spec), sha)

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

    _, spec, _ = github_wrapper.fetch_file_if_exists(title)

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

    def github_wrapper
      GithubWrapper.new(ENV['GITHUB_TOKEN'])
    end

    def lokalize_wrapper
      LokalizeWrapper.new(ENV['LOKALIZE_API_KEY'])
    end
end
