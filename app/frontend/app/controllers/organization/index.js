import Ember from 'ember';
import persistence from '../../utils/persistence';
import modal from '../../utils/modal';
import i18n from '../../utils/i18n';

export default Ember.Controller.extend({
  refresh_lists: function() {
    var _this = this;
    this.set('orgs', {});
    this.set('users', {});
    this.set('logs', {});
    this.set('managers', {});
    this.set('supervisors', {});
    this.set('selected_view', null);
    this.refresh_users();
    this.refresh_managers();
    this.refresh_supervisors();
    this.refresh_orgs();
    this.refresh_stats();
    var id = this.get('model.id');
    if(this.get('model.permissions.manage')) {
      this.set('logs.loading', true);
      persistence.ajax('/api/v1/organizations/' + id + '/logs', {type: 'GET'}).then(function(data) {
        _this.set('logs.loading', null);
        _this.set('logs.data', data.log);
      }, function() {
        _this.set('logs.loading', null);
        _this.set('logs.data', null);
      });
    }
  },
  shown_view: function() {
    if(this.get('selected_view')) {
      return this.get('selected_view');
    } else if(this.get('model.admin')) {
      return 'organizations';
    } else {
      return 'managers';
    }
  }.property('selected_view', 'model.admin'),
  show_organizations: function() {
    return !!(this.get('shown_view') == 'organizations');
  }.property('shown_view'),
  show_managers: function() {
    return !!(this.get('shown_view') == 'managers');
  }.property('shown_view'),
  show_communicators: function() {
    return !!(this.get('shown_view') == 'communicators');
  }.property('shown_view'),
  show_supervisors: function() {
    return !!(this.get('shown_view') == 'supervisors');
  }.property('shown_view'),
  first_log: function() {
    return (this.get('logs.data') || [])[0];
  }.property('logs.data'),
  recent_users: function() {
    return (this.get('logs.data') || []).map(function(e) { return e.user.id; }).uniq().length;
  }.property('logs.data'),
  recent_sessions: function() {
    return (this.get('logs.data') || []).length;
  }.property('logs.data'),
  no_licenses: function() {
    return !this.get('model.licenses_available');
  }.property('model.licenses_available'),
  refresh_stats: function() {
    var _this = this;
    persistence.ajax('/api/v1/organizations/' + this.get('model.id') + '/stats', {type: 'GET'}).then(function(stats) {
      _this.set('weekly_stats', stats);
    }, function() {
      _this.set('weekly_stats', {error: true});
    });
  },
  refresh_orgs: function() {
    var _this = this;
    if(this.get('model.admin')) {
      this.set('orgs.loading', true);
      this.store.query('organization', {q: 'all'}).then(function(res) {
        _this.set('orgs.loading', null);
        _this.set('orgs.data', res);
      }, function() {
        _this.set('orgs.loading', null);
        _this.set('orgs.data', null);
      });
    }
  },
  refresh_users: function() {
    var _this = this;
    this.set('users.loading', true);
    var id = this.get('model.id');
    persistence.ajax('/api/v1/organizations/' + id + '/users', {type: 'GET', data: {recent: true}}).then(function(data) {
      _this.set('users.loading', null);
      _this.set('users.data', data.user);
      _this.set('more_users', data.meta && data.meta.next_url);
    }, function() {
      _this.set('users.loading', null);
      _this.set('users.data', null);
    });
  },
  refresh_managers: function() {
    var _this = this;
    _this.set('managers.loading', true);
    var id = _this.get('model.id');
    persistence.ajax('/api/v1/organizations/' + id + '/managers', {type: 'GET', data: {recent: true}}).then(function(data) {
      _this.set('managers.loading', null);
      _this.set('managers.data', data.user);
    }, function() {
      _this.set('managers.loading', null);
      _this.set('managers.data', null);
    });
  },
  refresh_supervisors: function() {
    var _this = this;
    _this.set('supervisors.loading', true);
    var id = _this.get('model.id');
    persistence.ajax('/api/v1/organizations/' + id + '/supervisors', {type: 'GET', data: {recent: true}}).then(function(data) {
      _this.set('supervisors.loading', null);
      _this.set('supervisors.data', data.user);
      _this.set('more_supervisors', data.meta && data.meta.next_url);
    }, function() {
      _this.set('supervisors.loading', null);
      _this.set('supervisors.data', null);
    });
  },
  actions: {
    pick: function(view) {
      this.set('selected_view', view);
    },
    management_action: function(action, user_name) {
      var model = this.get('model');
      var _this = this;
      if(action == 'add_manager' || action == 'add_assistant') {
        user_name = this.get('manager_user_name');
      } else if(action == 'add_supervisor') {
        user_name = this.get('supervisor_user_name');
      } else if(action == 'add_user' || action == 'add_unsponsored_user') {
        user_name = this.get('user_user_name');
      }
      model.set('management_action', action + '-' + user_name);
      model.save().then(function() {
        if(action.match(/user/)) {
          _this.refresh_users();
        } else if(action.match(/manager/)) {
          _this.refresh_managers();
        } else if(action.match(/supervisor/)) {
          _this.refresh_supervisors();
        }
      }, function(err) {
        console.log(err);
        modal.error(i18n.t('management_action_failed', "Management action failed unexpectedly"));
      });
    },
    update_org: function() {
      var org = this.get('model');
      org.save().then(null, function(err) {
        console.log(err);
        modal.error(i18n.t('org_update_failed', 'Organization update failed unexpectedly'));
      });
    },
    add_org: function() {
      if(this.get('model.admin') && this.get('model.permissions.manage')) {
        var _this = this;
        var user_name = this.get('org_user_name');
        var org = this.store.createRecord('organization');
        org.set('name', this.get('org_org_name'));
        org.save().then(function() {
          org.set('management_action', 'add_manager-' + user_name);
          org.save().then(function() {
            _this.refresh_orgs();
          }, function(err) {
            console.log(err);
            modal.error(i18n.t('add_org_manager_failed', 'Adding organization manager failed unexpectedly'));
          });
        }, function(err) {
          console.log(err);
          modal.error(i18n.t('add_org_failed', 'Adding organization failed unexpectedly'));
        });
      }
    },
    remove_org: function(org) {
      var _this = this;
      if(this.get('model.admin') && this.get('model.permissions.manage')) {
        org.deleteRecord();
        org.save().then(function() {
          _this.refresh_orgs();
        }, function(err) {
          console.log(err);
          modal.error(i18n.t('remove_org_failed', 'Removing organization failed unexpectedly'));
        });
      }
    }
  }
});
