import Ember from 'ember';
import Controller from '@ember/controller';
import { later as runLater } from '@ember/runloop';
import persistence from '../../utils/persistence';
import modal from '../../utils/modal';
import Utils from '../../utils/misc';
import i18n from '../../utils/i18n';
import {set as emberSet, get as emberGet} from '@ember/object';

export default Controller.extend({
  refresh_lists: function() {
    var _this = this;
    this.set('orgs', {});
    this.set('users', {});
    this.set('evals', {});
    this.set('logs', {});
    this.set('managers', {});
    this.set('supervisors', {});
    this.set('selected_view', null);
    this.refresh_users();
    this.refresh_evals();
    this.refresh_managers();
    this.refresh_supervisors();
    this.refresh_orgs();
    this.refresh_stats();
    var id = this.get('model.id');
    if(this.get('model.permissions.manage')) {
      this.refresh_logs();
    }
  },
  refresh_logs: function() {
    var _this = this;
    var id = this.get('model.id');
    if(!id) { return; }
    this.set('logs', {loading: true});
    persistence.ajax('/api/v1/organizations/' + id + '/logs', {type: 'GET'}).then(function(data) {
      if(_this.get('model.id') == id) {
        _this.set('logs.loading', null);
        _this.set('logs.data', data.log);
      }
    }, function() {
      if(_this.get('model.id') == id) {
        _this.set('logs.loading', null);
        _this.set('logs.data', null);
      }
    });
  },
  refresh_logs_on_reload: function() {
    if(this.get('model.permissions.manage') && !this.get('logs.loading') && !this.get('logs.data')) {
      this.refresh_logs();
    }
  }.observes('model.permissions.manage', 'logs.loading', 'logs.data'),
  loading_org: function() {
    return !this.get('model.permissions');
  }.property('model.permissions'),
  shown_view: function() {
    if(this.get('selected_view')) {
      return this.get('selected_view');
    } else if(this.get('model.admin')) {
      return 'organizations';
    } else if(!this.get('managers.length') && this.get('model.children_orgs.length')) {
      return 'organizations';
    } else {
      return 'managers';
    }
  }.property('selected_view', 'model.admin', 'managers', 'model.children_orgs'),
  show_organizations: function() {
    return this.get('shown_view') == 'organizations';
  }.property('shown_view'),
  show_managers: function() {
    return this.get('shown_view') == 'managers';
  }.property('shown_view'),
  show_communicators: function() {
    return this.get('shown_view') == 'communicators';
  }.property('shown_view'),
  show_evals: function() {
    return this.get('shown_view') == 'evals';
  }.property('shown_view'),
  show_supervisors: function() {
    return this.get('shown_view') == 'supervisors';
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
  no_eval_licenses: function() {
    return !this.get('model.eval_licenses_available');
  }.property('model.eval_licenses_available'),
  refresh_stats: function() {
    var _this = this;
    _this.set('weekly_stats', null);
    _this.set('user_counts', null);
    persistence.ajax('/api/v1/organizations/' + this.get('model.id') + '/stats', {type: 'GET'}).then(function(stats) {
      _this.set('weekly_stats', stats.weeks);
      _this.set('user_counts', stats.user_counts);
    }, function() {
      _this.set('weekly_stats', {error: true});
    });
  },
  refresh_orgs: function() {
    var _this = this;
    if(this.get('model.admin')) {
      this.set('orgs.loading', true);
      Utils.all_pages('organization', {q: 'all'}).then(function(res) {
        _this.set('orgs.loading', null);
        _this.set('orgs.data', res);
      }, function() {
        _this.set('orgs.loading', null);
        _this.set('orgs.data', null);
      });
    }
  },
  sorted_orgs: function() {
    return this.get('orgs.data').map(function(o) { return o; }).sort(function(a, b) {
        if(a.get('name').toLowerCase() < b.get('name').toLowerCase()) {
          return -1;
        } else if(a.get('name').toLowerCase() > b.get('name').toLowerCase()) {
          return 1;
        } else {
          return 0;
        }
    });
  }.property('orgs.data'),
  alphabetized_orgs: function() {
    var orgs = this.get('sorted_orgs') || [];
    var letters = [];
    orgs.forEach(function(org) {
      var letter_string = org.get('name').substring(0, 1).toUpperCase();
      var letter = letters[letters.length - 1];
      if((letter || {}).letter != letter_string) {
        letter = {letter: letter_string, orgs: []};
        letters.push(letter);
      }
      letter.orgs.push(org);
      letter.expanded = (letter.orgs.length > 5);
    });
    return letters;
  }.property('sorted_orgs'),
  filtered_orgs: function() {
    var filter = this.get('org_filter');
    if(!filter || filter == '') { return null; }
    var res = [];
    try {
      var re = new RegExp(filter, 'i');
      (this.get('sorted_orgs') || []).forEach(function(org) {
        if(org.get('name').match(re)) {
          res.push(org);
        }
      });
    } catch(e) { }
    return res.slice(0, 10);
  }.property('sorted_orgs', 'org_filter'),
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
  refresh_evals: function() {
    var _this = this;
    this.set('evals.loading', true);
    var id = this.get('model.id');
    persistence.ajax('/api/v1/organizations/' + id + '/evals', {type: 'GET', data: {recent: true}}).then(function(data) {
      _this.set('evals.loading', null);
      _this.set('evals.data', data.user);
      _this.set('more_evals', data.meta && data.meta.next_url);
    }, function() {
      _this.set('evals.loading', null);
      _this.set('evals.data', null);
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
  suggest_creating_manager: function() {
    return this.get('missing_user_name') && this.get('missing_user_name') == this.get('manager_user_name');
  }.property('manager_user_name', 'missing_user_name'),
  suggest_creating_supervisor: function() {
    return this.get('missing_user_name') && this.get('missing_user_name') == this.get('supervisor_user_name');
  }.property('supervisor_user_name', 'missing_user_name'),
  suggest_creating_communicator: function() {
    return this.get('missing_user_name') && this.get('missing_user_name') == this.get('user_user_name');
  }.property('user_user_name', 'missing_user_name'),
  suggest_creating_eval: function() {
    return this.get('missing_user_name') && this.get('missing_user_name') == this.get('eval_user_name');
  }.property('eval_user_name', 'missing_user_name'),
  actions: {
    pick: function(view) {
      this.set('selected_view', view);
    },
    new_user: function(attr) {
      var _this = this;

      modal.open('new-user', {default_org_management_action: attr, organization_id: this.get('model.id'), no_licenses: this.get('no_licenses')}).then(function(res) {
        if(res && res.created) {
          if(res.user && res.user.get('org_management_action')) {
            // because of the way we hash all user/org settings, this doesn't always get
            // updated reliably, so we repeat ourselves rather than risk losing the result.
            _this.send('management_action', res.user.get('org_management_action'), res.user.get('user_name'));
//             runLater(function() {
//               _this.send('management_action', res.user.get('org_management_action'), res.user.get('user_name'));
//             }, 1000);
//             runLater(function() {
//               _this.send('management_action', res.user.get('org_management_action'), res.user.get('user_name'));
//             }, 5000);
          }
        }
      });
    },
    management_action: function(action, user_name) {
      var model = this.get('model');
      var _this = this;
      _this.set('missing_user_name', null);
      var cleanup = function() { };
      if(!user_name) {
        if(action == 'add_manager' || action == 'add_assistant') {
          user_name = this.get('manager_user_name');
          cleanup = function() { _this.set('manager_user_name', ''); };
        } else if(action == 'add_supervisor') {
          user_name = this.get('supervisor_user_name');
          cleanup = function() { _this.set('supervisor_user_name', ''); };
        } else if(action == 'add_user' || action == 'add_unsponsored_user') {
          user_name = this.get('user_user_name');
          cleanup = function() { _this.set('user_user_name', ''); };
        } else if(action == 'add_eval') {
          user_name = this.get('eval_user_name');
          cleanup = function() { _this.set('eval_user_name', ''); };
        }
      }
      if(!user_name) { return; }
      model.set('management_action', action + '-' + user_name);
      model.save().then(function() {
        if(action.match(/user/)) {
          _this.refresh_users();
        } else if(action.match(/eval/)) {
          _this.refresh_evals();
        } else if(action.match(/manager/) || action.match(/assistant/)) {
          _this.refresh_managers();
        } else if(action.match(/supervisor/)) {
          _this.refresh_supervisors();
        }
        cleanup();
      }, function(err) {
        console.log(err);
        if(err && err.errors && err.errors.length === 1 && err.errors[0].match(/invalid user/)) {
          _this.set('missing_user_name', user_name);
        } else {
          modal.error(i18n.t('management_action_failed', "Management action failed unexpectedly"));
        }
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
          if(user_name) {
            org.set('management_action', 'add_manager-' + user_name);
          }
          org.save().then(function() {
            _this.refresh_orgs();
            _this.transitionToRoute('organization', org.get('id'));
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
    },
    edit_org: function() {
      modal.open('edit-org', {org: this.get('model')});
    },
    toggle_letter: function(letter) {
      emberSet(letter, 'expanded', !emberGet(letter, 'expanded'));
    }
  }
});
