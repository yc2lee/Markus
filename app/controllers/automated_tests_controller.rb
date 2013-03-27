# The actions necessary for managing the Testing Framework form
require 'helpers/ensure_config_helper.rb'

class AutomatedTestsController < ApplicationController
  include AutomatedTestsHelper

  before_filter      :authorize_only_for_admin,
                     :only => [:manage, :update, :download]
  before_filter      :authorize_for_user,
                     :only => [:index]
                     
  # This is not being used right now. It was the calling interface to 
  # request a test run, however, now you can just call
  # AutomatedTestsHelper.request_a_test_run to send a test request.
  def index                               
    submission_id = params[:submission_id]
    
    # TODO: call_on should be passed to index as a parameter. 
    list_call_on = %w(submission request collection)
    call_on = list_call_on[0]
    
    AutomatedTestsHelper.request_a_test_run(submission_id, call_on, @current_user)
    
    # TODO: render a new partial page
    #render :test_replace,
    #       :locals => {:test_result_files => @test_result_files,
    #                   :result => @result}
  end
  
  # Update is called when files are added to the assigment
  def update
    @assignment = Assignment.find(params[:assignment_id])

    create_test_repo(@assignment)
    
    # Perform transaction, if errors, none of new config saved
    @assignment.transaction do

      begin
        # Process testing framework form for validation
        @assignment = process_test_form(@assignment, params)
      rescue Exception, RuntimeError => e
        @assignment.errors.add(:base, I18n.t("assignment.error",
                                             :message => e.message))
        render :manage
        return        
      end

      # Save assignment and associated test files
      if @assignment.save
        flash[:success] = I18n.t("assignment.update_success")
        redirect_to :action => 'manage',
                    :assignment_id => params[:assignment_id]
      else
        render :manage
      end
        
    end
  end

  # Manage is called when the Automated Test UI is loaded
  def manage
    @assignment = Assignment.find(params[:assignment_id])
  end

  # Download is called when an admin wants to download a test script
  # or test support file
  # Check three things:
  #  1. filename is in DB
  #  2. file is in the directory it's supposed to be
  #  3. file exists and is readable
  def download
    filedb = nil
    if params[:type] == 'script'
      filedb = TestScript.find_by_assignment_id_and_script_name(params[:assignment_id], params[:filename])
    elsif params[:type] == 'support'
      filedb = TestSupportFile.find_by_assignment_id_and_file_name(params[:assignment_id], params[:filename])
    end

    if filedb
      if params[:type] == 'script'
        filename = filedb.script_name
      elsif params[:type] == 'support'
        filename = filedb.file_name
      end
      assn_short_id = Assignment.find(params[:assignment_id]).short_identifier

      # the given file should be in this directory
      should_be_in = File.join(MarkusConfigurator.markus_config_automated_tests_repository, assn_short_id)
      should_be_in = File.expand_path(should_be_in)
      filename = File.expand_path(File.join(should_be_in, filename))

      if should_be_in == File.dirname(filename) and File.readable?(filename)
        # Everything looks OK. Send the file over to the client.
        file_contents = IO.read(filename)
        send_file filename,
                  :type => ( SubmissionFile.is_binary?(file_contents) ? 'application/octet-stream':'text/plain' ),
                  :x_sendfile => true

     # print flash error messages
      else
        flash[:error] = I18n.t('automated_tests.download_wrong_place_or_unreadable');
        redirect_to :action => 'manage'
      end
    else
      flash[:error] = I18n.t('automated_tests.download_not_in_db');
      redirect_to :action => 'manage'
    end
  end

  def username
    params['username'] || 'demostudent'
  end

  def myrequest
    # Normally, without resque-status, we do this
    # Resque.enqueue(ResqueClass, 9999)

    # But with the resque-status, we have to do this instead
    #job_id = ResqueClass.create(:message => ' I like bananas. ')
    #render :text=>"job_id = #{job_id}<br>Resque.redis: #{Resque.info}"

    redis = Redis.new
    x = redis.incr "markus:test_run_ticketing:ticket"

    key = "markus:test_run_ticketing:#{username}"
    redis.set key, x
    redis.expire key, 3600
    redis.rpush "markus:queue_demo", username
    render :text => "DB now has key <b>#{key}</b> with value <b>#{redis.get key}</b>"

  end


  def myview
    redis = Redis.new
    key = "markus:test_run_ticketing:#{username}"
    s = "You have key <b>#{key}</b> with value <b>#{redis.get key}</b>"  
    render :text => s
  end

  def mydequeue
    redis.rpush "markus:queue_demo", username
    redis = Redis.new
    x = redis.incr "markus:test_run_ticketing:serving"
    render :text => "Now serving ticket #{redis.get "markus:test_run_ticketing:serving"}"
  end

  def dumpkeys
    i = 1
    s = ''
    redis = Redis.new
    redis.keys("*").each do |key|
      type = redis.type key
      if type == 'string'
        s += "#{i}) #{key} =====> #{redis.get key}<br>\n"
        i += 1
      end
    end
    render :text => s
  end

  def resqueclass
    j = ResqueClass.create(:length => 32)
    render :text => "job id is #{j}"
  end
end
