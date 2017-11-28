class Api::UnitsController < ApplicationController
  before_action :require_api_token

  def index
    org = Organization.find_by_global_id(params['organization_id'])
    return unless exists?(org, params['organization_id'])
    return unless allowed?(org, 'edit')
    
    # TODO: sharding
    @units = OrganizationUnit.where(:organization_id => org.id).order('position, id ASC')
    @units = @units.to_a.sort_by{|u| (u.settings['name'] || 'Unnamed Room').downcase }
    render json: JsonApi::Unit.paginate(params, @units)
  end
  
  def create
    org = Organization.find_by_global_id(params['unit']['organization_id'])
    return unless exists?(org, params['unit']['organization_id'])
    return unless allowed?(org, 'edit')
    @unit = OrganizationUnit.process_new(params['unit'], {:organization => org})
    if @unit.errored?
      api_error(400, {error: "unit creation failed", errors: @unit && @unit.processing_errors})
    else
      render json: JsonApi::Unit.as_json(@unit, :wrapper => true, :permissions => @api_user).to_json
    end
  end

  def stats
    unit = OrganizationUnit.find_by_global_id(params['unit_id'])
    return unless exists?(unit, params['unit_id'])
    return unless allowed?(unit, 'view_stats')

    user_ids = UserLink.links_for(unit).select{|l| l['type'] == 'org_unit_communicator' }.map{|l| l['user_id'] }
    approved_users = User.find_all_by_global_id(user_ids)
    res = Organization.usage_stats(approved_users, false)

    res['user_weeks'] = {}
    sessions = LogSession.where(['started_at > ?', 12.weeks.ago]).where(:user_id => approved_users.map(&:id))
    sessions.group("date_trunc('week', started_at), user_id").select("count(*), date_trunc('week', started_at), user_id, count(goal_id) AS goals").each do |obj|
      if obj.attributes['user_id']
        user_id = unit.related_global_id(obj.attributes['user_id'])
        res['user_weeks'][user_id] ||= {}
        if obj.attributes['date_trunc']
          ts = obj.attributes['date_trunc'].to_time.to_i
          res['user_weeks'][user_id][ts] ||= {
            'count' => obj.attributes['count'] || 0,
            'goals' => obj.attributes['goals'] || 0
          }
        end
      end
    end

    render json: res.to_json
  end

  def logs
    unit = OrganizationUnit.find_by_global_id(params['unit_id'])
    return unless exists?(unit, params['unit_id'])
    return unless allowed?(unit, 'view_stats')
    user_ids = UserLink.links_for(unit).select{|l| l['type'] == 'org_unit_communicator' }.map{|l| l['user_id'] }
    approved_users = User.find_all_by_global_id(user_ids)
    # TODO: sharding
    logs = LogSession.where(:user_id => approved_users.map(&:id)).order(id: :desc)
    prefix = "/units/#{unit.global_id}/logs"
    render json: JsonApi::Log.paginate(params, logs, {:prefix => prefix})
  end
    
  def show
    @unit = OrganizationUnit.find_by_global_id(params['id'])
    return unless exists?(@unit, params['id'])
    return unless allowed?(@unit, 'view')
    render json: JsonApi::Unit.as_json(@unit, :wrapper => true, :permissions => @api_user).to_json
  end

  def update
    @unit = OrganizationUnit.find_by_global_id(params['id'])
    return unless exists?(@unit, params['id'])
    return unless allowed?(@unit, 'edit')
    if @unit.process(params['unit'])
      render json: JsonApi::Unit.as_json(@unit, :wrapper => true, :permissions => @api_user).to_json
    else
      api_error(400, {error: "unit update failed", errors: @unit.processing_errors})
    end
  end
  
  def destroy
    @unit = OrganizationUnit.find_by_global_id(params['id'])
    return unless exists?(@unit, params['id'])
    return unless allowed?(@unit, 'delete')
    @unit.destroy
    render json: JsonApi::Unit.as_json(@unit, :wrapper => true, :permissions => @api_user).to_json
  end
end
