#Unit tests for the controller-api class
require "minitest/autorun"
require File.expand_path(File.join(File.dirname(__FILE__), '../cli-server/controller-api'))

class TestControllerApi < Minitest::Test
  
  def setup
    @api = Ctrl_api.new
    refute_nil(@api)    
    ret = @api.start_session("admin","d033e22ae348aeb5660fc2140aec35850c4da997")
    refute_nil ret
    assert(ret['ok']==true)
    @admin_session_id = ret['session_id']
    refute_nil(@admin_session_id," session_id was nil")
  end
  
  def test_start_session
    ret = @api.start_session("admin","d033e22ae348aeb5660fc2140aec35850c4da997")
    assert(ret['ok']==true)
    assert ret['session_id']
  end
  
  def test_submit_job_simple
    
    nb_jobs_before_submit = @api.list_jobs(@admin_session_id)['job_list'].size
    assert nb_jobs_before_submit
    print("Jobs before submit: #{nb_jobs_before_submit}")
    #	def submit_job(name, description, code, lib_filename, lib_version, nb_splayds, churn_trace, options, session_id, scheduled_at, strict, trace_alt, queue_timeout, multiple_code_files, designated_splayds_string, splayds_as_job,  topology)
    code="require\"splay.base\""
    lib_filename=""
    lib_version=nil
    nb_splayds=1
    churn_trace=""
    options=Array.new #mimic json request
    scheduled_at=nil
    strict=false
    trace_alt=false
    queue_timeout=nil
    multiple_code_files=false
    designated_splayds_string="" #TODO make test with these 
    splayds_as_job="" #TODO make test with these
    topology=nil
    
    #the call to submit_job blocks for <=30 sec, this should be changed
    
    ret = @api.submit_job(
      "the_name",
      "the_description",
       code,
       lib_filename,
       lib_version,
       nb_splayds,
       churn_trace,
       options,
       @admin_session_id,
       scheduled_at,
       strict,
       trace_alt,
       queue_timeout,
       multiple_code_files,
       designated_splayds_string,
       splayds_as_job,
       topology)
       
    refute_nil ret
    #assert(ret['ok'], msg="expected ok but was: #{ret['ok']}" )
   
    nb_jobs_after_submit = @api.list_jobs(@admin_session_id)['job_list'].size
    assert(nb_jobs_after_submit == nb_jobs_before_submit+1)
  end
  
  def test_list_splayds
    nb_jobs = @api.list_jobs(@admin_session_id)['job_list']
    assert nb_jobs
  end
  
end