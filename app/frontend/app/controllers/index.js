import Ember from 'ember';
import Controller from '@ember/controller';
import EmberObject from '@ember/object';
import {set as emberSet, get as emberGet} from '@ember/object';
import { later as runLater } from '@ember/runloop';
import $ from 'jquery';
import CoughDrop from '../app';
import persistence from '../utils/persistence';
import capabilities from '../utils/capabilities';
import app_state from '../utils/app_state';
import Badge from '../models/badge';
import session from '../utils/session';
import modal from '../utils/modal';
import stashes from '../utils/_stashes';
import i18n from '../utils/i18n';
import { htmlSafe } from '@ember/string';

export default Controller.extend({
  registration_types: CoughDrop.registrationTypes,
  sync_able: function() {
    return this.get('extras.ready');
  }.property('extras.ready'),
  home_board_or_supporter: function() {
      return this.get('app_state.currentUser.preferences.home_board.key') || this.get('app_state.currentUser.supporter_role');
  }.property('app_state.currentUser.preferences.home_board.key', 'app_state.currentUser.supporter_role'),
  needs_sync: function() {
    var now = (new Date()).getTime() / 1000;
    return (now - persistence.get('last_sync_at')) > (7 * 24 * 60 * 60);
  }.property('persistence.last_sync_at'),
  triedToSave: false,
  badEmail: function() {
    var email = this.get('user.email');
    return (this.get('triedToSave') && !email);
  }.property('user.email', 'triedToSave'),
  shortPassword: function() {
    var password = this.get('user.password') || '';
    return this.get('triedToSave') && password.length < 6;
  }.property('user.password', 'triedToSave'),
  noName: function() {
    var name = this.get('user.name');
    var user_name = this.get('user.user_name');
    return this.get('triedToSave') && !name && !user_name;
  }.property('user.name', 'user.user_name', 'triedToSave'),
  noSpacesName: function() {
    return !!(this.get('user.user_name') || '').match(/[\s\.'"]/);
  }.property('user.user_name'),
  blank_slate: function() {
    var progress = this.get('app_state.currentUser.preferences.progress');
    // TODO: eventually this should go away, maybe after a few weeks of active use or something
    if(progress && progress.setup_done) {
      return null;
    } else if(this.get('app_state.currentUser.using_for_a_while')) {
      return null;
    } else {
      return progress;
    }
  }.property('app_state.currentUser.preferences.progress', 'app_state.currentUser.using_for_a_while'),
  no_intro: function() {
    return this.get('blank_slate') && !this.get('app_state.currentUser.preferences.progress.intro_watched');
  }.property('blank_slate', 'app_state.currentUser.preferences.progress.intro_watched'),
  blank_slate_percent: function() {
    var options = ['intro_watched', 'profile_edited', 'preferences_edited', 'home_board_set', 'app_added'];

    var total = options.length;
    if(total === 0) { return 0; }
    var done = 0;
    var progress = this.get('app_state.currentUser.preferences.progress') || {};
    if(progress.setup_done) { return 100; }
    options.forEach(function(opt) {
      if(progress[opt]) {
        done++;
      }
    });
    return Math.round(done / total * 100);
  }.property('app_state.currentUser.preferences.progress'),
  blank_slate_percent_style: function() {
    return htmlSafe("width: " + this.get('blank_slate_percent') + "%;");
  }.property('blank_slate_percent'),
  checkForBlankSlate: function() {
    var _this = this;
    if(Ember.testing) { return; }
    persistence.find_recent('board').then(function(boards) {
      if(boards && boards.slice) {
        boards = boards.slice(0, 12);
      }
      _this.set('recentOfflineBoards', boards);
      if(_this.get('homeBoards') == [] && _this.get('popularBoards') == []) {
        _this.set('showOffline', true);
      } else if(!_this.get('persistence.online')) {
        _this.set('showOffline', true);
      } else {
        _this.set('showOffline', false);
      }
    }, function() {
      _this.set('showOffline', false);
    });
  }.observes('persistence.online'),
  device: function() {
    var res = {
      added_somewhere: !!this.get('app_state.currentUser.preferences.progress.app_added'),
      standalone: capabilities.browserless,
      android: capabilities.system == "Android",
      ios: capabilities.system == "iOS"
    };

    res.needs_install_reminder = !res.added_somewhere || ((res.android || res.ios) && !res.standalone);
    if(res.standalone && (res.android || res.ios)) {
      res.needs_install_reminder = false;
    } else if(this.get('app_state.currentUser.using_for_a_while')) {
      res.needs_install_reminder = false;
    }
    return res;
  }.property(),
  small_needs_sync_class: function() {
    var res = "half_size list-group-item ";
    if(!this.get('needs_sync')) {
      res = res + "subtle ";
    }
    return res;
  }.property('needs_sync'),
  refreshing_class: function() {
    var res = "glyphicon glyphicon-refresh ";
    if(this.get('persistence.syncing')) {
      res = res + "spinning ";
    }
    return res;
  }.property('persistence.syncing'),
  needs_sync_class: function() {
    var res = "list-group-item ";
    if(!this.get('needs_sync')) {
      res = res + "subtle ";
    }
    return res;
  }.property('needs_sync'),
  current_boards: function() {
    var res = {};
    if(this.get('popular_selected')) {
      res = this.get('popularBoards');
    } else if(this.get('personal_selected')) {
      res = this.get('personalBoards');
    } else if(this.get('suggested_selected')) {
      res = this.get('homeBoards');
    } else if(this.get('recent_selected')) {
      res = this.get('recentOfflineBoards');
    }
    return res;
  }.property('popular_selected', 'personal_selected', 'suggested_selected', 'recent_selected', 'popularBoards', 'personalBoards', 'homeBoards', 'recentOfflineBoards'),
  pending_updates: function() {
    var important = this.get('app_state.currentUser.pending_org') ||
                this.get('app_state.currentUser.pending_supervision_org') ||
                (this.get('app_state.currentUser.pending_board_shares') || []).length > 0 ||
                this.get('app_state.currentUser.unread_messages');
    var normal_new = app_state.get('currentUser.unread_messages.length') || 0;
    var unread_notifications = (app_state.get('currentUser.parsed_notifications') || []).filter(function(n) { return n.unread; }).length;
    normal_new = normal_new + (unread_notifications || 0);

    if(normal_new && !app_state.get('currentUser.read_notifications')) {
      return {count: normal_new};
    } else if(important) {
      return true;
    } else {
      return null;
    }
  }.property('app_state.currentUser.pending_org', 'app_state.currentUser.pending_supervision_org', 'app_state.currentUser.pending_board_shares', 'app_state.currentUser.unread_messages'),
  update_selected: function() {
    var _this = this;
    if(!persistence.get('online')) { return; }
    var last_browse = stashes.get('last_index_browse');
    var default_index = 2;
    // If a user already has a home board they're not going to care about popular boards,
    // they want to see something more useful like all the boards they own, or maybe
    // the home boards of all their supervisees, or maybe all their starred boards
    if(app_state.get('currentUser.preferences.home_board.key')) {
      if(app_state.get('currentUser.stats.user_boards') > 0) {
        default_index = 1;
      } else {
        default_index = 3;
      }
    }
    ['popular', 'personal', 'suggested', 'recent'].forEach(function(key, idx) {
      if(_this.get('selected') == key || (!_this.get('selected') && idx === default_index && !last_browse) || (!_this.get('selected') && last_browse == key)) {
        _this.set(key + '_selected', true);
        if(_this.get('selected')) {
          stashes.persist('last_index_browse', key);
        }
        if(key == 'recent') {
          persistence.find_recent('board').then(function(boards) {
            if(boards && boards.slice) {
              boards = boards.slice(0, 12);
            }
            _this.set('recentOfflineBoards', boards);
          });
        } else {
          var list = 'homeBoards';
          var opts = {public: true, starred: true, user_id: 'example', sort: 'custom_order', per_page: 12};
          if(key == 'personal') {
            list = 'personalBoards';
            opts = {user_id: 'self', copies: false, per_page: 12};
          } else if(key == 'popular') {
            list = 'popularBoards';
            opts = {sort: 'home_popularity', per_page: 12, exclude_starred: 'example'};
          }
          if(!(_this.get(list) || {}).length) {
            _this.set(list, {loading: true});
          }
          _this.store.query('board', opts).then(function(data) {
            _this.set(list, data);
            _this.checkForBlankSlate();
          }, function() {
            _this.set(list, {error: true});
          });
          _this.checkForBlankSlate();
        }
      } else {
        _this.set(key + '_selected', false);
      }
    });
  }.observes('selected', 'persistence.online'),
  reload_logs: function() {
    var model = this.get('model');
    var _this = this;
    if(model && model.get('id') && persistence.get('online')) {
      var controller = this;
      var find_args = {user_id: model.get('id'), type: 'session'};
      if(model.get('supporter_role')) {
        find_args.supervisees = true;
      }
      if(!(controller.get('logs') || {}).length) {
        controller.set('logs', {loading: true});
      }
      this.store.query('log', find_args).then(function(list) {
        controller.set('logs', list.map(function(i) { return i; }));
      }, function() {
        if(!(controller.get('logs') || {}).length) {
          controller.set('logs', {error: true});
        }
      });
      if(app_state.get('feature_flags.badge_progress') || model.get('feature_flags.badge_progress')) {
        this.store.query('badge', {user_id: model.get('id'), recent: 1}).then(function(badges) {
          var for_users = {};
          badges.forEach(function(badge) {
            for_users[badge.get('user_id')] = for_users[badge.get('user_id')] || []
            for_users[badge.get('user_id')].push(badge);
          });
          _this.set('current_user_badges', for_users);
        }, function(err) { });
        model.load_word_activities();
      }
    }
  }.observes('model.id', 'persistence.online'),
  best_badge: function(badges, goal_id) {
    return Badge.best_next_badge(badges, goal_id);
  },
  earned_badge: function(badges) {
    return Badge.best_earned_badge(badges);
  },
  update_current_badges: function() {
    var _this = this;
    var model = _this.get('model');
    var for_users = _this.get('current_user_badges') || {};
    if(model && for_users[model.get('id')]) {
      var b = _this.best_badge(for_users[model.get('id')], model.get('goal.id'));
      var eb = _this.earned_badge(for_users[model.get('id')]);
      if(!app_state.get('sessionUser.full_premium') || app_state.get('sessionUser.supporter_role')) {
        b = null;
      }
      // If no badge for the current user use the supervisee if there's only one
      if(!b && (app_state.get('sessionUser.supervisees') || []).length == 1) {
        var sup = app_state.get('sessionUser.supervisees')[0];
        if(sup.premium) {
          b = _this.best_badge(for_users[emberGet(sup, 'id')], (sup.goal || {}).id)
        }
      }
      emberSet(model, 'current_badge', b);
      emberSet(model, 'earned_badge', eb);
    }
    var sups = [];
    (app_state.get('sessionUser.supervisees') || []).forEach(function(sup) {
      if(for_users[emberGet(sup, 'id')] && emberGet(sup, 'premium')) {
        var b = _this.best_badge(for_users[emberGet(sup, 'id')], (sup.goal || {}).id);
        emberSet(sup, 'current_badge', b);
        var eb = _this.earned_badge(for_users[emberGet(sup, 'id')]);
        emberSet(sup, 'earned_badge', eb);
      }
      sups.push(sup);
    });
    _this.set('supervisees_with_badges', sups);
  }.observes('app_state.sessionUser', 'app_state.sessionUser.supervisees', 'current_user_badges'),
  modeling_ideas_available: function() {
    if(app_state.get('feature_flags.badge_progress')) {
      if(app_state.get('sessionUser.supporter_role')) {
        var any_premium_supervisees = false;
        (app_state.get('sessionUser.supervisees') || []).forEach(function(sup) {
          if(emberGet(sup, 'premium')) {
            any_premium_supervisees = true;
          }
        });
        if(any_premium_supervisees) {
          return true;
        }
      } else if(app_state.get('sessionUser.full_premium')) {
        return true;
      }
    }
    return false;
  }.property('app_state.feature_flags.badge_progress', 'app_state.sessionUser.supporter_role', 'app_state.sessionUser.full_premium'),
  many_supervisees: function() {
    return (app_state.get('currentUser.supervisees') || []).length > 5;
  }.property('app_state.currentUser.supervisees'),
  some_supervisees: function() {
    return (app_state.get('currentUser.supervisees') || []).length > 3;
  }.property('app_state.currentUser.supervisees'),
  save_user_pref_change: function() {
    var mode = app_state.get('currentUser.preferences.auto_open_speak_mode');
    if(mode !== undefined) {
      var last_mode = this.get('last_auto_open_speak_mode');
      if(last_mode !== undefined && mode !== null && last_mode != mode) {
        app_state.get('currentUser').save().then(null, function() { });
      }
      this.set('last_auto_open_speak_mode', mode);
    }
  }.observes('app_state.currentUser.preferences.auto_open_speak_mode'),
  index_nav: function() {
    var res = {};
    if(this.get('index_nav_state')) {
      res[this.get('index_nav_state')] = true;
    } else if(app_state.get('currentUser.preferences.device.last_index_nav')) {
      res[app_state.get('currentUser.preferences.device.last_index_nav')] = true;
    } else {
      if(this.get('model.supporter_role')) {
//        res.supervisees = true;
        res.main = true;
      } else {
        res.main = true;
      }
    }
    return res;
  }.property('index_nav_state', 'model.supporter_role', 'app_state.currentUser.preference.device.last_index_nav'),
  subscription_check: function() {
    // if the user is in the free trial or is really expired, they need the subscription
    // modal to pop up
    if(this.get('app_state.sessionUser') && !this.get('app_state.installed_app')) {
      var progress = this.get('app_state.sessionUser.preferences.progress');
      var user = this.get('app_state.sessionUser');
      var needs_subscribe_modal = false;
      if(!progress || (!progress.skipped_subscribe_modal && !progress.setup_done)) {
        if(user.get('grace_period')) {
          if(modal.route) {
            needs_subscribe_modal = true;
          }
        }
      } else if(this.get('app_state.sessionUser.really_expired')) {
        needs_subscribe_modal = true;
      }
      if(needs_subscribe_modal) {
        if(!this.get('app_state.installed_app')) {
          modal.open('subscribe');
        } else {
          // TODO: ...
        }
      }
    }
  }.observes('app_state.sessionUser'),
  actions: {
    invalidateSession: function() {
      session.invalidate(true);
    },
    reload: function() {
      location.reload();
    },
    quick_assessment: function(user) {
      if(user.premium) {
        var _this = this;
        modal.open('quick-assessment', {user: user});
      } else {
        modal.open('premium-required', {user_name: user.user_name, action: 'quick_assessment'});
      }
    },
    getting_started: function() {
//      this.transitionToRoute('setup');
       modal.open('getting-started', {progress: app_state.get('currentUser.preferences.progress')});
    },
    record_note: function(user) {
      user = user || app_state.get('currentUser');
      emberSet(user, 'avatar_url_with_fallback', emberGet(user, 'avatar_url'));
      modal.open('record-note', {note_type: 'text', user: user}).then(function() {
        runLater(function() {
          app_state.get('currentUser').reload().then(null, function() { });
        }, 5000);
      });
    },
    sync: function() {
      if(!persistence.get('syncing')) {
        console.debug('syncing because manually triggered');
        persistence.sync('self', true).then(null, function() { });
      }
    },
    load_reports: function() {
      var user = app_state.get('currentUser');
      this.transitionToRoute('user.stats', user.get('user_name'));
    },
    hide_login: function() {
      app_state.set('login_modal', false);
      $("html,body").css('overflow', '');
      $("#login_overlay").remove();
    },
    show_explanation: function(exp) {
      this.set('show_' + exp + '_explanation', true);
    },
    set_selected: function(selected) {
      this.set('selected', selected);
    },
    set_index_nav: function(nav) {
      if(nav == 'main' || nav == 'supervisees') {
        var u = app_state.get('currentUser');
        u.set('preferences.device.last_index_nav', nav);
        u.save().then(null, function() { });
      } else if(nav == 'updates') {
        if(app_state.get('currentUser')) {
          app_state.set('currentUser.read_notifications', true);
          app_state.get('currentUser').save().then(null, function() { });
        }
      }
      this.set('index_nav_state', nav);
    },
    toggle_extras: function() {
      this.set('show_main_extras', !this.get('show_main_extras'));
    },
    expand_left_nav: function() {
      this.set('left_nav_expanded', !this.get('left_nav_expanded'));
    },
    intro_video: function(id) {
      if(window.ga) {
        window.ga('send', 'event', 'Setup', 'video', 'Intro video opened');
      }
      modal.open('inline-video', {video: {type: 'youtube', id: id}, hide_overlay: true});
    },
    intro: function() {
      if(window.ga) {
        window.ga('send', 'event', 'Setup', 'start', 'Setup started');
      }
      this.transitionToRoute('setup');
    },
    opening_index: function() {
      app_state.set('index_view', true);
    },
    closing_index: function() {
      app_state.set('index_view', false);
    },
    manage_supervisors: function() {
      modal.open('supervision-settings', {user: app_state.get('currentUser')});
    },
    session_select: function() {
      if(!app_state.get('currentUser.preferences.logging')) {
        this.send('load_reports');
      } else {
        this.send('set_index_nav', 'updates');
      }
    },
    sync_details: function() {
      var list = ([].concat(persistence.get('sync_log') || [])).reverse();
      modal.open('sync-details', {details: list});
    },
    stats: function(user_name) {
      if(!user_name) {
        if((app_state.get('currentUser.supervisees') || []).length > 0) {
          var prompt = i18n.t('select_user_for_reports', "Select User for Reports");
          app_state.controller.send('switch_communicators', {stay: true, modeling: true, skip_me: true, route: 'user.stats', header: prompt});
          return;
        } else {
          user_name = app_state.get('currentUser.user_name');
        }
      }
      this.transitionToRoute('user.stats', user_name, {queryParams: {start: null, end: null, device_id: null, location_id: null, split: null, start2: null, end2: null, devicde_id2: null, location_id2: null}});
    },
    goals: function() {
      if((app_state.get('currentUser.supervisees') || []).length > 0) {
        var prompt = i18n.t('select_user_for_goals', "Select User for Goals");
        app_state.controller.send('switch_communicators', {stay: true, modeling: true, skip_me: true, route: 'user.goals', header: prompt});
        return;
      } else {
        var user_name = app_state.get('currentUser.user_name');
        this.transitionToRoute('user.stats', user_name, {queryParams: {start: null, end: null, device_id: null, location_id: null, split: null, start2: null, end2: null, devicde_id2: null, location_id2: null}});
      }
    },
    new_dashboard: function() {
      var user = app_state.get('currentUser');
      user.set('preferences.new_index', true);
      user.save().then(null, function() { });
      modal.success(i18n.t('revert_new_dashboard', "Welcome to the new, cleaner dashboard! If you're not a fan you can switch back on your Preferences page."));
    },
    set_goal: function(user) {
      var _this = this;
      CoughDrop.store.findRecord('user', user.id).then(function(user_model) {
        modal.open('new-goal', {user: user_model }).then(function(res) {
          if(res && res.get('id') && res.get('set_badges')) {
            _this.transitionToRoute('user.goal', user_model.get('user_name'), res.get('id'));
          } else if(res) {
            // update the matching currentUser.supervisees goal attribute 
            // with the new value if not already set
            (app_state.get('currentUser.supervisees') || []).forEach(function(sup) {
              if(emberGet(sup, 'id') == user_model.get('id')) {
                emberSet(sup, 'goal', {
                  id: res.get('id'),
                  summary: res.get('summary')
                });
              }
            });
          }
        }, function() { });
      }, function(err) {
        modal.error(i18n.t('error_loading_user', "There was an unexpected error trying to load the user"));
      });
    },
    modeling_ideas: function(user_name) {
      var users = [];
      if(!user_name) {
        if((app_state.get('currentUser.supervisees') || []).length > 0) {
          (app_state.get('currentUser.supervisees') || []).forEach(function(u) {
            if(emberGet(u, 'premium')) {
              users.push(u);
            }
          });
          // add all supervisees as users
        } else {
          users.push(app_state.get('currentUser'));
        }
      } else {
        (app_state.get('currentUser.supervisees') || []).forEach(function(u) {
          if(u.user_name == user_name) {
            users.push(u);
          }
        });
      }
      if(users.length > 0) {
        modal.open('modals/modeling-ideas', {users: users});
      }
    }
  }
});

