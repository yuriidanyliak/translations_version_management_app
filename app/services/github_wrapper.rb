require 'uri'
require 'net/http'

class GithubWrapper
  def initialize(token)
    @client = Octokit::Client.new(access_token: token)
  end

  def fetch_file_if_exists(path)
    file = client.contents(ENV['REPO_NAME'], path: path)

    uri = URI(file[:download_url])
    response_body = Net::HTTP.get_response(uri).body

    [path, JSON.parse(response_body), file[:sha]]
  rescue Octokit::NotFound
    return nil
  end

  def create_file_and_open_pr(filename, content, sha)
    branch_name = "#{filename}_#{Time.now.getutc.strftime('%Y%m%d%H%m%s')}"

    commit_sha = client.commits(ENV['REPO_NAME'], 'main').first[:sha]

    client.create_ref ENV['REPO_NAME'], "heads/#{branch_name}", commit_sha

    client.update_contents(ENV['REPO_NAME'], filename, 'Updating translations', sha, content, branch: branch_name)

    client.create_pull_request(ENV['REPO_NAME'], 'main', branch_name, filename, '')
  end
  
  private

  attr_reader :client
end
