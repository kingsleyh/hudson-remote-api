module Hudson
  # This class provides an interface to Hudson jobs
  class Job < HudsonObject

    attr_accessor :name, :config, :repository_url, :repository_urls, :repository_browser_location, :description
    attr_reader :color, :last_build, :last_completed_build, :last_failed_build, :last_stable_build, :last_successful_build, :last_unsuccessful_build, :next_build_number,
                :string_parameters

    # List all Hudson jobs
    def self.list()
      xml = get_xml(@@hudson_xml_api_path)

      jobs = []
      jobs_doc = REXML::Document.new(xml)
      jobs_doc.each_element("hudson/job") do |job|
        jobs << job.elements["name"].text
      end
      jobs
    end

    # List all jobs in active execution
    def self.list_active
      xml = get_xml(@@hudson_xml_api_path)

      active_jobs = []
      jobs_doc = REXML::Document.new(xml)
      jobs_doc.each_element("hudson/job") do |job|
        if job.elements["color"].text.include?("anime")
          active_jobs << job.elements["name"].text
        end
      end
      active_jobs
    end

    def initialize(name)
      @name = name
      load_xml_api
      load_config
      load_info
    end

    def load_xml_api
      @xml_api_path = File.join(Hudson[:url], "job/#{@name}/api/xml")
      @xml_api_config_path = File.join(Hudson[:url], "job/#{@name}/config.xml")
      @xml_api_build_path = File.join(Hudson[:url], "job/#{@name}/build")
      @xml_api_build_with_parameters_path = File.join(Hudson[:url], "job/#{@name}/buildWithParameters")
      @xml_api_disable_path = File.join(Hudson[:url], "job/#{@name}/disable")
      @xml_api_enable_path = File.join(Hudson[:url], "job/#{@name}/enable")
      @xml_api_delete_path = File.join(Hudson[:url], "job/#{@name}/doDelete")
      @xml_api_wipe_out_workspace_path = File.join(Hudson[:url], "job/#{@name}/doWipeOutWorkspace")
    end

    # Load data from Hudson's Job configuration settings into class variables
    def load_config()
      @config = get_xml(@xml_api_config_path)
      @config_doc = REXML::Document.new(@config)

      @config_doc = REXML::Document.new(@config)
      if !@config_doc.elements["/project/scm/locations/hudson.scm.SubversionSCM_-ModuleLocation/remote"].nil?
        @repository_url = @config_doc.elements["/project/scm/locations/hudson.scm.SubversionSCM_-ModuleLocation/remote"].text || ""
      end
      @repository_urls = []
      if !@config_doc.elements["/project/scm/locations"].nil?
        @config_doc.elements.each("/project/scm/locations/hudson.scm.SubversionSCM_-ModuleLocation") { |e| @repository_urls << e.elements["remote"].text }
      end
      if !@config_doc.elements["/project/scm/browser/location"].nil?
        @repository_browser_location = @config_doc.elements["/project/scm/browser/location"].text
      end
      if !@config_doc.elements["/project/description"].nil?
        @description = @config_doc.elements["/project/description"].text || ""
      end
    end

    def load_info()
      @info = get_xml(@xml_api_path)
      @info_doc = REXML::Document.new(@info)

      if is_freestyle_project?
        @color = @info_doc.elements["/freeStyleProject/color"].text if @info_doc.elements["/freeStyleProject/color"]
        @last_build = @info_doc.elements["/freeStyleProject/lastBuild/number"].text if @info_doc.elements["/freeStyleProject/lastBuild/number"]
        @last_completed_build = @info_doc.elements["/freeStyleProject/lastCompletedBuild/number"].text if @info_doc.elements["/freeStyleProject/lastCompletedBuild/number"]
        @last_failed_build = @info_doc.elements["/freeStyleProject/lastFailedBuild/number"].text if @info_doc.elements["/freeStyleProject/lastFailedBuild/number"]
        @last_stable_build = @info_doc.elements["/freeStyleProject/lastStableBuild/number"].text if @info_doc.elements["/freeStyleProject/lastStableBuild/number"]
        @last_successful_build = @info_doc.elements["/freeStyleProject/lastSuccessfulBuild/number"].text if @info_doc.elements["/freeStyleProject/lastSuccessfulBuild/number"]
        @last_unsuccessful_build = @info_doc.elements["/freeStyleProject/lastUnsuccessfulBuild/number"].text if @info_doc.elements["/freeStyleProject/lastUnsuccessfulBuild/number"]
        @next_build_number = @info_doc.elements["/freeStyleProject/nextBuildNumber"].text if @info_doc.elements["/freeStyleProject/nextBuildNumber"]
        @string_parameters = get_string_parameters("freeStyleProject")
      elsif is_maven_project?
        @string_parameters = get_string_parameters("mavenModuleSet")
        @last_build = @info_doc.elements["/mavenModuleSet/lastBuild/number"].text if @info_doc.elements["/mavenModuleSet/lastBuild/number"]
      end
    end

    def active?
      Job.list_active.include?(@name)
    end

    def wait_for_build_to_finish(poll_freq=10)
      loop do
        puts "waiting for all #{@name} builds to finish"
        sleep poll_freq # wait
        BuildQueue.load_xml_api
        break if !active? and !BuildQueue.list.include?(@name)
      end
    end

    # Create a new job on Hudson server based on the current job object
    def copy(new_job=nil)
      new_job = "copy_of_#{@name}" if new_job.nil?

      response = send_post_request(@@xml_api_create_item_path, {:name=>new_job, :mode=>"copy", :from=>@name})
      raise(APIError, "Error copying job #{@name}: #{response.body}") if response.class != Net::HTTPFound
      Job.new(new_job)
    end

    # Update the job configuration on Hudson server
    def update(config=nil)
      @config = config if !config.nil?
      response = send_xml_post_request(@xml_api_config_path, @config)
      response.is_a?(Net::HTTPSuccess) or response.is_a?(Net::HTTPRedirection)
    end

    # Set the repository url and update on Hudson server
    def repository_url=(repository_url)
      return false if @repository_url.nil?
      @repository_url = repository_url
      @config_doc.elements["/project/scm/locations/hudson.scm.SubversionSCM_-ModuleLocation/remote"].text = repository_url
      @config = @config_doc.to_s
      update
    end

    def repository_urls=(repository_urls)
      return false if !repository_urls.class == Array
      @repository_urls = repository_urls

      i = 0
      @config_doc.elements.each("/project/scm/locations/hudson.scm.SubversionSCM_-ModuleLocation") do |location|
        location.elements["remote"].text = @repository_urls[i]
        i += 1
      end

      @config = @config_doc.to_s
      update
    end

    # Set the repository browser location and update on Hudson server
    def repository_browser_location=(repository_browser_location)
      @repository_browser_location = repository_browser_location
      @config_doc.elements["/project/scm/browser/location"].text = repository_browser_location
      @config = @config_doc.to_s
      update
    end

    # Set the job description and update on Hudson server
    def description=(description)
      @description = description
      @config_doc.elements["/project/description"].text = description
      @config = @config_doc.to_s
      update
    end

    def build_with_no_params()
      response = send_post_request(@xml_api_build_path, {:delay => '0sec'})
      response.is_a?(Net::HTTPSuccess) or response.is_a?(Net::HTTPRedirection)
    end

    def build_with_string_params(params={})
      build_params = {:delay => '0sec'}.merge(convert_string_params_to_hash).merge(params)
      puts "parameters:"
      build_params.each { |p| p p }
      response = send_post_request(@xml_api_build_with_parameters_path, build_params)
      response.is_a?(Net::HTTPSuccess) or response.is_a?(Net::HTTPRedirection)
    end

    def has_string_params?
      !@string_parameters.empty?
    end

    def build(params={})
      if has_string_params?
        build_with_string_params(params)
      else
        build_with_no_params
      end
    end

    def disable()
      response = send_post_request(@xml_api_disable_path)
      puts response.class
      response.is_a?(Net::HTTPSuccess) or response.is_a?(Net::HTTPRedirection)
    end

    def enable()
      response = send_post_request(@xml_api_enable_path)
      puts response.class
      response.is_a?(Net::HTTPSuccess) or response.is_a?(Net::HTTPRedirection)
    end

    # Delete this job from Hudson server
    def delete()
      response = send_post_request(@xml_api_delete_path)
      response.is_a?(Net::HTTPSuccess) or response.is_a?(Net::HTTPRedirection)
    end

    def wipe_out_workspace()
      wait_for_build_to_finish

      if !active?
        response = send_post_request(@xml_api_wipe_out_workspace_path)
      else
        response = false
      end
      response.is_a?(Net::HTTPSuccess) or response.is_a?(Net::HTTPRedirection)
    end

    private
    def get_string_parameters(project_type)
      parameter_list = []
      @info_doc.elements.each("/#{project_type}/action/parameterDefinition") do |i|
        begin
          elem = i.elements.to_a
          value = elem.first.elements.to_a.first.text
          description = elem[1].to_a.first
          name = elem[2].to_a.first
          param_type = elem[3].to_a.first
          parameter_list << OpenStruct.new(:name => name, :description => description, :param_type => param_type, :value => value) if param_type == "StringParameterDefinition"
        rescue => e
          puts "ERROR: could not process a parameter: #{i} with exception: #{e}"
        end
      end
      return parameter_list
    end

    def convert_string_params_to_hash
      params = {}
      @string_parameters.each { |param| params[param.name] = param.value }
      params
    end

    def is_freestyle_project?
      !@info_doc.elements["/freeStyleProject"].nil?
    end

    def is_maven_project?
      !@info_doc.elements["/mavenModuleSet"].nil?
    end

  end

end