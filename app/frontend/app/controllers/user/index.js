import Ember from 'ember';
import Controller from '@ember/controller';
import EmberObject from '@ember/object';
import {set as emberSet, get as emberGet} from '@ember/object';
import { later as runLater } from '@ember/runloop';
import persistence from '../../utils/persistence';
import CoughDrop from '../../app';
import modal from '../../utils/modal';
import app_state from '../../utils/app_state';
import i18n from '../../utils/i18n';
import progress_tracker from '../../utils/progress_tracker';
import Subscription from '../../utils/subscription';

export default Controller.extend({
  title: function() {
    return "Profile for " + this.get('model.user_name');
  }.property('model.user_name'),
  sync_able: function() {
    return this.get('extras.ready');
  }.property('extras.ready'),
  needs_sync: function() {
    var now = (new Date()).getTime();
    return (now - persistence.get('last_sync_at')) > (7 * 24 * 60 * 60 * 1000);
  }.property('persistence.last_sync_at'),
  check_daily_use: function() {
    var current_user_name = this.get('daily_use.user_name');
    if((this.get('model.user_name') && current_user_name != this.get('model.user_name') && this.get('model.permissions.admin_support_actions')) || !this.get('daily_use')) {
      var _this = this;
      _this.set('daily_use', {loading: true});
      persistence.ajax('/api/v1/users/' + this.get('model.user_name') + '/daily_use', {type: 'GET'}).then(function(data) {
        var log = CoughDrop.store.push({ data: {
          id: data.log.id,
          type: 'log',
          attributes: data.log
        }});
        _this.set('daily_use', log);
      }, function(err) {
        if(err && err.result && err.result.error == 'no data available') {
          _this.set('daily_use', null);
        } else {
          _this.set('daily_use', {error: true});
        }
      });
    }
  }.observes('model.user_name', 'model.permissions.admin_support_actions'),
  blank_slate: function() {
    return !this.get('model.preferences.home_board.key') &&
      (this.get('public_boards_shortened') || []).length === 0 &&
      (this.get('private_boards_shortened') || []).length === 0 &&
      (this.get('starred_boards_shortened') || []).length === 0 &&
      (this.get('shared_boards_shortened') || []).length === 0;
  }.property('model.preferences.home_board.key', 'public_boards_shortened', 'private_boards_shortened', 'starred_boards_shortened', 'shared_boards_shortened'),
  board_list: function() {
    var list = [];
    var res = {remove_type: 'delete', remove_label: i18n.t('delete', "delete")};
    if(this.get('selected') == 'mine' || !this.get('selected')) {
      list = this.get('model.my_boards');
    } else if(this.get('selected') == 'public') {
      list = this.get('model.public_boards');
    } else if(this.get('selected') == 'private') {
      list = this.get('model.private_boards');
    } else if(this.get('selected') == 'starred') {
      list = this.get('model.starred_boards');
      res.remove_type = 'unstar';
      res.remove_label = i18n.t('unstar', "unstar");
    } else if(this.get('selected') == 'shared') {
      list = this.get('model.shared_boards');
      res.remove_type = 'unlink';
      res.remove_label = i18n.t('unlink', "unlink");
    } else if(this.get('selected') == 'prior_home') {
      list = this.get('model.prior_home_boards');
    }
    list = list || [];
    if(list.loading || list.error) { return list; }

    if(this.get('parent_object')) {
      list = [];
      list.push({board: this.get('parent_object.board')});
      (this.get('parent_object.children') || []).forEach(function(b) {
        list.push({board: b.board});
      });
      list.done = true;
      res.sub_result = true;
    }

    res.results = list;
    var board_ids = {};
    var new_list = [];
    if(this.get('parent_object')) {
      new_list = list;
    } else {
      list.forEach(function(b) {
        var obj = {board: b, children: []};
        board_ids[emberGet(b, 'id')] = obj;
        if(emberGet(b, 'copy_id') && board_ids[b.get('copy_id')]) {
          board_ids[b.get('copy_id')].children.push({board: b});
        } else {
          new_list.push(obj);
        }
      });
    }
    if(this.get('filterString')) {
      var re = new RegExp(this.get('filterString'), 'i');
      new_list = new_list.filter(function(i) { return i.board.get('search_string').match(re); });
      res.filtered_results = new_list.slice(0, 18);
    } else if(this.get('show_all_boards')) {
      res.filtered_results = new_list.slice(0, 300);
    } else {
      if(list.done && new_list && new_list.length <= 18) {
        this.set('show_all_boards', true);
      }
      res.filtered_results = new_list.slice(0, 18);
    }
    return res;
  }.property('selected', 'parent_object', 'show_all_boards', 'filterString', 'model.my_boards', 'model.prior_home_boards', 'model.public_boards', 'model.private_boards', 'model.starred_boards', 'model.shared_boards'),
  reload_logs: function() {
    var _this = this;
    if(!persistence.get('online')) { return; }
    if(!(_this.get('model.logs') || {}).length) {
      this.set('model.logs', {loading: true});
    }
    this.store.query('log', {user_id: this.get('model.id'), per_page: 4}).then(function(logs) {
      _this.set('model.logs', logs.slice(0,4));
    }, function() {
      if(!(_this.get('model.logs') || {}).length) {
        _this.set('model.logs', {error: true});
      }
    });
  }.observes('persistence.online'),
  load_badges: function() {
    if(this.get('model.permissions')) {
      var _this = this;
      if(!(_this.get('model.badges') || {}).length) {
        _this.set('model.badges', {loading: true});
      }
      this.store.query('badge', {user_id: this.get('model.id'), earned: true, per_page: 4}).then(function(badges) {
        _this.set('model.badges', badges);
      }, function(err) {
        if(!(_this.get('model.badges') || {}).length) {
          _this.set('model.badges', {error: true});
        }
      });
    }
  }.observes('model.permissions'),
  load_goals: function() {
    if(this.get('model.permissions')) {
      var _this = this;
      if(!(_this.get('model.goals') || {}).length) {
        _this.set('model.goals', {loading: true});
      }
      this.store.query('goal', {user_id: this.get('model.id'), per_page: 3}).then(function(goals) {
        _this.set('model.goals', goals.map(function(i) { return i; }).filter(function(g) { return g.get('active'); }));
      }, function(err) {
        if(!(_this.get('model.goals') || {}).length) {
          _this.set('model.goals', {error: true});
        }
      });
    }
  }.observes('model.permissions'),
  subscription: function() {
    if(this.get('model.permissions.admin_support_actions') && this.get('model.subscription')) {
      var sub = Subscription.create({user: this.get('model')});
      sub.reset();
      return sub;
    }
  }.property('model.permissions.admin_support_actions', 'model.subscription'),
  generate_or_append_to_list: function(args, list_name, list_id, append) {
    var _this = this;
    if(list_id != _this.get('list_id')) { return; }
    var prior = _this.get(list_name) || [];
    if(prior.error || prior.loading) { prior = []; }
    if(!append && !prior.length) {
      _this.set(list_name, {loading: true});
    }
    _this.store.query('board', args).then(function(boards) {
      if(_this.get('list_id') == list_id) {
        if(!append && prior.length) {
          prior = [];
        }
        var result = prior.concat(boards.map(function(i) { return i; }));
        result.user_id = _this.get('model.id');
        _this.set(list_name, result);
        var meta = persistence.meta('board', boards); //_this.store.metadataFor('board');
        if(meta && meta.more) {
          args.per_page = meta.per_page;
          args.offset = meta.next_offset;
          _this.generate_or_append_to_list(args, list_name, list_id, true);
        } else {
          _this.set(list_name + '.done', true);
        }
      }
    }, function() {
      if(_this.get('list_id') == list_id && !prior.length) {
        _this.set(list_name, {error: true});
      }
    });
  },
  update_selected: function() {
    var _this = this;
    var list_id = Math.random().toString();
    this.set('list_id', list_id);
    var model = this.get('model');
    if(!persistence.get('online')) { return; }
    var default_key = null;
    if(!_this.get('selected') && model) {
      default_key = model.get('permissions.supervise') ? 'mine' : 'public';
    }
    ['mine', 'public', 'private', 'starred', 'shared', 'prior_home'].forEach(function(key, idx) {
      if(_this.get('selected') == key || key == default_key) {
        _this.set(key + '_selected', true);
        if(key == 'mine') {
          _this.generate_or_append_to_list({user_id: model.get('id')}, 'model.my_boards', list_id);
        } else if(key == 'public') {
          _this.generate_or_append_to_list({user_id: model.get('id'), public: true}, 'model.public_boards', list_id);
        } else if(key == 'private') {
          _this.generate_or_append_to_list({user_id: model.get('id'), private: true}, 'model.private_boards', list_id);
        } else if(key == 'starred') {
          if(model.get('permissions.supervise')) {
            _this.generate_or_append_to_list({user_id: model.get('id'), starred: true}, 'model.starred_boards', list_id);
          } else {
            _this.generate_or_append_to_list({user_id: model.get('id'), public: true, starred: true}, 'model.starred_boards', list_id);
          }
        } else if(key == 'shared') {
          _this.generate_or_append_to_list({user_id: model.get('id'), shared: true}, 'model.shared_boards', list_id);
        }
      } else {
        _this.set(key + '_selected', false);
      }
    });

    if(model && model.get('permissions.edit')) {
      if(!model.get('preferences.home_board.key')) {
        _this.generate_or_append_to_list({user_id: 'example', starred: true, public: true}, 'model.starting_boards', list_id);
      }
    }
  }.observes('selected', 'persistence.online'),
  actions: {
    sync: function() {
      console.debug('syncing because manually triggered');
      persistence.sync(this.get('model.id'), 'all_reload').then(null, function() { });
    },
    quick_assessment: function() {
      var _this = this;
      app_state.check_for_full_premium(_this.get('model', 'quick_assessment')).then(function() {
        modal.open('quick-assessment', {user: _this.get('model')}).then(function() {
          _this.reload_logs();
        });
      }, function() { });
    },
    stats: function() {
      this.transitionToRoute('user.stats', this.get('model.user_name'));
    },
    approve_or_reject_org: function(approve) {
      var user = this.get('model');
      var type = this.get('edit_permission') ? 'add_edit' : 'add';
      if(approve == 'user_approve') {
        user.set('supervisor_key', "approve-org");
      } else if(approve == 'user_reject') {
        user.set('supervisor_key', "remove_supervisor-org");
      } else if(approve == 'supervisor_approve') {
        var org_id = this.get('model.pending_supervision_org.id');
        user.set('supervisor_key', "approve_supervision-" + org_id);
      } else if(approve == 'supervisor_reject') {
        var org_id = this.get('model.pending_supervision_org.id');
        user.set('supervisor_key', "remove_supervision-" + org_id);
      }
      user.save().then(function() {

      }, function() { });
    },
    add_supervisor: function() {
      var _this = this;
      app_state.check_for_full_premium(this.get('model'), 'add_supervisor').then(function() {
        modal.open('add-supervisor', {user: _this.get('model')});
      }, function() { });
    },
    view_devices: function() {
      modal.open('device-settings', this.get('model'));
    },
    supervision_settings: function() {
      modal.open('supervision-settings', {user: this.get('model')});
    },
    show_more_boards: function() {
      this.set('show_all_boards', true);
    },
    set_selected: function(selected) {
      this.set('selected', selected);
      this.set('show_all_boards', false);
      this.set('parent_object', null);
//       this.set('filterString', '');
    },
    load_children: function(obj) {
      this.set('show_all_boards', false);
      this.set('parent_object', obj);
    },
    nothing: function() {
    },
    badge_popup: function(badge) {
      modal.open('badge-awarded', {badge: badge});
    },
    remove_board: function(action, board) {
      var _this = this;
      if(action == 'delete') {
        modal.open('confirm-delete-board', {board: board, redirect: false}).then(function() {
          _this.update_selected();
        });
      } else {
        modal.open('confirm-remove-board', {action: action, board: board, user: this.get('model')}).then(function() {
          _this.update_selected();
        });
      }
    },
    resendConfirmation: function() {
      persistence.ajax('/api/v1/users/' + this.get('model.user_name') + '/confirm_registration', {
        type: 'POST',
        data: {
          resend: true
        }
      }).then(function(res) {
        modal.success(i18n.t('confirmation_resent', "Confirmation email sent, please check your spam box if you can't find it!"));
      }, function() {
        modal.error(i18n.t('confirmation_resend_failed', "There was an unexpected error requesting a confirmation email."));
      });
    },
    set_subscription: function(action) {
      if(action == 'cancel') {
        this.set('subscription_settings', null);
      } else if(action == 'confirm' && this.get('subscription_settings')) {
        this.set('subscription_settings.loading', true);
        var _this = this;
        persistence.ajax('/api/v1/users/' + this.get('model.user_name') + '/subscription', {
          type: 'POST',
          data: {
            type: this.get('subscription_settings.action')
          }
        }).then(function(data) {
          progress_tracker.track(data.progress, function(event) {
            if(event.status == 'errored') {
              _this.set('subscription_settings.loading', false);
              _this.set('subscription_settings.error', i18n.t('subscription_error', "There was an error checking status on the users's subscription"));
            } else if(event.status == 'finished') {
              _this.get('model').reload().then(function() {
                _this.get('subscription').reset();
              });
              _this.set('subscription_settings', null);
              modal.success(i18n.t('subscription_updated', "User purchase information updated!"));
            }
          });
        }, function() {
          _this.set('subscription_settings.loading', false);
          _this.set('subscription_settings.error', i18n.t('subscription_error', "There was an error updating the users's account information"));
        });
      } else if(action == 'eval') {
        this.set('subscription_settings', {action: action, type: i18n.t('eval_device', "Evaluation Device")});
      } else if(action == 'never_expires') {
        this.set('subscription_settings', {action: action, type: i18n.t('never_expires', "Never Expiring Subscription")});
      } else if(action == 'manual_supporter') {
        this.set('subscription_settings', {action: action, type: i18n.t('manual_supporter', "Manually Set as Supporter")});
      } else if(action == 'add_1') {
        this.set('subscription_settings', {action: action, type: i18n.t('add_one_month', "Add 1 Month to Expiration")});
      } else if(action == 'communicator_trial') {
        this.set('subscription_settings', {action: action, type: i18n.t('communicator_trial', "Manually Set as Communicator Free Trial")});
      } else if(action == 'add_voice') {
        this.set('subscription_settings', {action: action, type: i18n.t('add_premium_voice', "Add 1 Premium Voice")});
      } else if(action == 'force_logout') {
        this.set('subscription_settings', {action: action, type: i18n.t('force_device_logout', "Force Logout on all Devices (this may cause the user to lose some logs)")});
      }
    },
    rename_user: function(confirm) {
      if(confirm === undefined) {
        this.set('new_user_name', {});
      } else if(confirm === false) {
        this.set('new_user_name', null);
      } else {
        if(!this.get('new_user_name')) {
          this.set('new_user_name', {});
        }
        if(!this.get('new_user_name.value')) { return; }

        var _this = this;
        var new_key = _this.get('new_user_name.value');
        var old_key = _this.get('new_user_name.old_value');
        if(old_key != _this.get('model.user_name')) { return; }

        _this.set('new_user_name', {renaming: true});
        persistence.ajax('/api/v1/users/' + this.get('model.user_name') + '/rename', {
          type: 'POST',
          data: {
            old_key: _this.get('model.user_name'),
            new_key: new_key
          }
        }).then(function(res) {
          _this.set('new_user_name', null);
          _this.transitionToRoute('user.index', res.key);
          runLater(function() {
            modal.success(i18n.t('user_renamed_to', "User successfully renamed to %{k}. The full renaming process can take a little while to complete.", {k: res.key}));
          }, 200);
        }, function(err) {
          _this.set('new_user_name', {error: true});
        });
      }
    },
    reset_password: function(confirm) {
      if(confirm === undefined) {
        this.set('password', {});
      } else if(confirm === false) {
        this.set('password', null);
      } else {
        if(!this.get('password')) {
          this.set('password', {});
        }
        var keys = "23456789abcdef";
        var pw = "";
        for(var idx = 0; idx < 8; idx++) {
          var hit = Math.round(Math.random() * keys.length);
          var key = keys.substring(hit, hit + 1);
          pw = pw + key;
        }
        this.set('password.pw', pw);
        this.set('password.loading', true);
        var _this = this;

        persistence.ajax('/api/v1/users/' + this.get('model.user_name'), {
          type: 'POST',
          data: {
            '_method': 'PUT',
            'reset_token': 'admin',
            'user': {
              'password': pw
            }
          }
        }).then(function(data) {
          _this.set('password.loading', false);
        }, function() {
          _this.set('password.error', true);
        });
      }
    }
  }
});
