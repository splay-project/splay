require File.dirname(__FILE__) + '/../test_helper'
require 'splayd_controller'

# Re-raise errors caught by the controller.
class SplaydController; def rescue_action(e) raise e end; end

class SplaydControllerTest < Test::Unit::TestCase
  fixtures :splayds

  def setup
    @controller = SplaydController.new
    @request    = ActionController::TestRequest.new
    @response   = ActionController::TestResponse.new

    @first_id = splayds(:first).id
  end

  def test_index
    get :index
    assert_response :success
    assert_template 'list'
  end

  def test_list
    get :list

    assert_response :success
    assert_template 'list'

    assert_not_nil assigns(:splayds)
  end

  def test_show
    get :show, :id => @first_id

    assert_response :success
    assert_template 'show'

    assert_not_nil assigns(:splayd)
    assert assigns(:splayd).valid?
  end

  def test_new
    get :new

    assert_response :success
    assert_template 'new'

    assert_not_nil assigns(:splayd)
  end

  def test_create
    num_splayds = Splayd.count

    post :create, :splayd => {}

    assert_response :redirect
    assert_redirected_to :action => 'list'

    assert_equal num_splayds + 1, Splayd.count
  end

  def test_edit
    get :edit, :id => @first_id

    assert_response :success
    assert_template 'edit'

    assert_not_nil assigns(:splayd)
    assert assigns(:splayd).valid?
  end

  def test_update
    post :update, :id => @first_id
    assert_response :redirect
    assert_redirected_to :action => 'show', :id => @first_id
  end

  def test_destroy
    assert_nothing_raised {
      Splayd.find(@first_id)
    }

    post :destroy, :id => @first_id
    assert_response :redirect
    assert_redirected_to :action => 'list'

    assert_raise(ActiveRecord::RecordNotFound) {
      Splayd.find(@first_id)
    }
  end
end
