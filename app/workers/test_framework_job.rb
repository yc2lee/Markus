require 'libxml'
require 'open3'

class TestFrameworkJob
  include Resque::Plugins::Status
  include LibXML

  def self.queue
    :test_waiting_list
  end

  def perform
    # Pick a server, launch the Test Runner and wait for the result
    # Then store the result into the database

    submission_id = options['submission_id']
    call_on = options['call_on']

    puts "------------------------------------------------------------------"    
    puts
    puts submission_id.inspect
    puts call_on.inspect
    puts
    puts "------------------------------------------------------------------"    

  
    @submission = Submission.find(submission_id)
    @grouping = @submission.grouping
    @assignment = @grouping.assignment
    @group = @grouping.group
    @repo_dir = File.join(MarkusConfigurator.markus_config_automated_tests_repository, @group.repo_name)

    @list_of_servers = MarkusConfigurator.markus_ate_test_server_hosts.split(' ')
    
    while true
      @test_server_id = choose_test_server()
      if @test_server_id >= 0 
        break
      else
        sleep 5               # if no server is available, sleep for 5 second before it checks again
      end  
    end

    result, status = launch_test(@test_server_id, @assignment, @repo_dir, call_on)
    puts "Result is..."
    puts result
    
    if !status
      # TODO: handle this error better
      raise "error"
    else
      process_result(result, submission_id, @assignment.id)
    end
    
  end

  # From a list of test servers, choose the next available server
  # using round-robin. Return the id of the server, and return -1
  # if no server is available.
  # TODO: keep track of the max num of tests running on a server
  def choose_test_server()

    if (defined? @last_server) && MarkusConfigurator.automated_testing_engine_on?
      # find the index of the last server, and return the next index
      @last_server = (@last_server + 1) % MarkusConfigurator.markus_ate_num_test_servers
    else
      @last_server = 0
    end

    return @last_server

  end

  # Launch the test on the test server by scp files to the server
  # and run the script.
  # This function returns two values: first one is the output from
  # stdout or stderr, depending on whether the execution passed or
  # had error; the second one is a boolean variable, true => execution
  # passeed, false => error occurred.
  def launch_test(server_id, assignment, repo_dir, call_on)
    # Get src_dir
    src_dir = File.join(repo_dir, assignment.repository_folder)

    # Get test_dir
    test_dir = File.join(MarkusConfigurator.markus_config_automated_tests_repository, assignment.repository_folder)

    # Get the name of the test server
    server = @list_of_servers[server_id]

    # Get the directory and name of the test runner script
    test_runner = MarkusConfigurator.markus_ate_test_runner_script_name

    # Get the test run directory of the files
    run_dir = MarkusConfigurator.markus_ate_test_run_directory

    # Delete the test run directory to remove files from previous test
    ssh = "ssh -i /home/nick/.ssh/id_rsa_blank "
    scp = "scp -i /home/nick/.ssh/id_rsa_blank "
  puts "#{ssh} #{server} rm -rf #{run_dir}"
    stdout, stderr, status = Open3.capture3("#{ssh} #{server} rm -rf #{run_dir}")
    if !(status.success?)
      return [stderr, false]
    end

    # Recreate the test run directory
  puts "#{ssh} #{server} mkdir #{run_dir}"
    stdout, stderr, status = Open3.capture3("#{ssh} #{server} mkdir #{run_dir}")
    if !(status.success?)
      return [stderr, false]
    end

    # Securely copy source files, test files and test runner script to run_dir
  puts "#{scp} -p -r #{src_dir}/* #{server}:#{run_dir}"
    stdout, stderr, status = Open3.capture3("#{scp} -p -r #{src_dir}/* #{server}:#{run_dir}")
    if !(status.success?)
      return [stderr, false]
    end

  puts "#{scp} -p -r #{test_dir}/* #{server}:#{run_dir}"
    stdout, stderr, status = Open3.capture3("#{scp} -p -r #{test_dir}/* #{server}:#{run_dir}")
    if !(status.success?)
      return [stderr, false]
    end

  puts "#{ssh} #{server} cp #{test_runner} #{run_dir}"
    stdout, stderr, status = Open3.capture3("#{ssh} #{server} cp #{test_runner} #{run_dir}")
    if !(status.success?)
      return [stderr, false]
    end

    # Find the test scripts for this test run, and parse the argument list
    list_run_scripts = scripts_to_run(assignment, call_on)
  puts "list_run_scripts = #{list_run_scripts}"
    arg_list = ""
    list_run_scripts.each do |script|
      arg_list = arg_list + "#{script.script_name} #{script.halts_testing} "
    end
    
    # Run script
    test_runner_name = File.basename(test_runner)
  puts "#{ssh} #{server} \"cd #{run_dir}; ruby #{test_runner_name} #{arg_list}\"" 
    stdout, stderr, status = Open3.capture3("#{ssh} #{server} \"cd #{run_dir}; ruby #{test_runner_name} #{arg_list}\"")
    if !(status.success?)
      return [stderr, false]
    else
      return [stdout, true]
    end
    
  end

  def process_result(result, submission_id, assignment_id)
    puts "processing"
    puts result
    parser = XML::Parser.string(result)

    # parse the xml doc
    doc = parser.parse

    # find all the test_script nodes and loop over them
    test_scripts = doc.find('/testrun/test_script')
    puts "#{test_scripts.length}"
    test_scripts.each do |s_node|
      script_result = TestScriptResult.new
      script_result.submission_id = submission_id
      script_marks_earned = 0    # cumulate the marks_earn in this script
      
      # find the script name and save it
      script_name_nodes = s_node.find('./script_name')
      if script_name_nodes.length != 1
        # FIXME: better error message is required (use locale)
        raise "None or more than one test script name is found in one test_script tag."
      else
        script_name = script_name_nodes[0].content
      end
      
      # Find all the test scripts with this script_name.
      # There should be one and only one record - raise exception if not
      test_script_array = TestScript.find_all_by_assignment_id_and_script_name(assignment_id, script_name)
      if test_script_array.length != 1
        # FIXME: better error message is required (use locale)
        raise "None or more than one test script is found for script name " + script_name
      else
        test_script = test_script_array[0]
      end

      script_result.test_script_id = test_script.id

      # find all the test nodes and loop over them
      tests = s_node.find('./test')
      tests.each do |t_node|
        test_result = TestResult.new
        test_result.submission_id = submission_id
        test_result.test_script_id = test_script.id
        # give default values
        test_result.name = 'no name is given'
        test_result.completion_status = 'error'
        test_result.input_description = ''
        test_result.expected_output = ''
        test_result.actual_output = ''
        test_result.marks_earned = 0
        
        t_node.each_element do |child|
          if child.name == 'name'
            test_result.name = child.content
          elsif child.name == 'status'
            test_result.completion_status = child.content.downcase
          elsif child.name == 'input'
            test_result.input_description = child.content
          elsif child.name == 'expected'
            test_result.expected_output = child.content
          elsif child.name == 'actual'
            test_result.actual_output = child.content
          elsif child.name == 'marks_earned'
            test_result.marks_earned = child.content
            script_marks_earned += child.content.to_i
          else
            # FIXME: better error message is required (use locale)
            raise "Error: malformed xml from test runner. Unclaimed tag: " + child.name
          end
        end
        
        # save to database
        test_result.save
      end
      
      # if a marks_earned tag exists under test_script tag, get the value;
      # otherwise, use the cumulative marks earned from all unit tests
      script_marks_earned_nodes = s_node.find('./marks_earned')
      if script_marks_earned_nodes.length == 1
        script_result.marks_earned = script_marks_earned_nodes[0].content.to_i
      else
        script_result.marks_earned = script_marks_earned
      end
      
      # save to database
      puts "saving result to db: #{script_result.inspect}"
      script_result.save
      
    end
  end

  # Find the list of test scripts to run the test. Return the list of
  # test scripts in the order specified by seq_num (running order)
  def scripts_to_run(assignment, call_on)
    # Find all the test scripts of the current assignment
    all_scripts = TestScript.find_all_by_assignment_id(assignment.id)

    list_run_scripts = Array.new

    # If the test run is requested at collection (by Admin or TA),
    # All of the test scripts should be run.
    if call_on == "collection"
      list_run_scripts = all_scripts
    else
      # If the test run is requested at submission or upon request,
      # verify the script is allowed to run.
      all_scripts.each do |script|
        if (call_on == "submission") && script.run_on_submission
          list_run_scripts.insert(list_run_scripts.length, script)
        elsif (call_on == "request") && script.run_on_request
          list_run_scripts.insert(list_run_scripts.length, script)
        end
      end
    end

    # sort list_run_scripts using ruby's in place sorting method
    list_run_scripts.sort_by! {|script| script.seq_num}
    
    # list_run_scripts should be sorted now. Perform a check here.
    # Take this out if it causes performance issue.
    ctr = 0
    while ctr < list_run_scripts.length - 1
      if (list_run_scripts[ctr].seq_num) > (list_run_scripts[ctr+1].seq_num)
        raise "list_run_scripts is not sorted"
      end
      ctr = ctr + 1
    end

    return list_run_scripts
  end
end
