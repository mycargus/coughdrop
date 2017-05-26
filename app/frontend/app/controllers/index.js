import Ember from 'ember';
import CoughDrop from '../app';
import persistence from '../utils/persistence';
import capabilities from '../utils/capabilities';
import app_state from '../utils/app_state';
import session from '../utils/session';
import modal from '../utils/modal';
import stashes from '../utils/_stashes';

export default Ember.Controller.extend({
  registration_types: CoughDrop.registrationTypes,
  sync_able: function() {
    return this.get('extras.ready');
  }.property('extras.ready'),
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
    return new Ember.String.htmlSafe("width: " + this.get('blank_slate_percent') + "%;");
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
              boards = boards.slice(0, 9);
            }
            _this.set('recentOfflineBoards', boards);
          });
        } else if(key == 'suggested') {
          if(!(_this.get('homeBoards') || {}).length) {
            _this.set('homeBoards', {loading: true});
          }
          _this.store.query('board', {public: true, starred: true, user_id: 'example', sort: 'custom_order', per_page: 9}).then(function(data) {
            _this.set('homeBoards', data);
            _this.checkForBlankSlate();
          }, function() {
            if(!(_this.get('homeBoards') || {}).length) {
              _this.set('homeBoards', {error: true});
            }
            _this.checkForBlankSlate();
          });
        } else if(key == 'personal') {
          if(!(_this.get('personalBoards') || {}).length) {
            _this.set('personalBoards', {loading: true});
          }
          _this.store.query('board', {user_id: 'self', per_page: 9}).then(function(boards) {
            _this.set('personalBoards', boards);
          }, function() {
            if(!(_this.get('personalBoards') || {}).length) {
              _this.set('personalBoards', {error: true});
            }
          });
        } else if(key == 'popular') {
          if(!(_this.get('popularBoards') || {}).length) {
            _this.set('popularBoards', {loading: true});
          }
          _this.store.query('board', {sort: 'home_popularity', per_page: 12}).then(function(data) {
            _this.set('popularBoards', data);
            _this.checkForBlankSlate();
          }, function() {
            if(!(_this.get('popularBoards') || {}).length) {
              _this.set('popularBoards', {error: true});
            }
            _this.checkForBlankSlate();
          });
        }
      } else {
        _this.set(key + '_selected', false);
      }
    });
  }.observes('selected', 'persistence.online'),
  reload_logs: function() {
    var model = this.get('model');
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
        controller.set('logs', list.get('content').slice(0, 6).mapBy('record'));
      }, function() {
        if(!(controller.get('logs') || {}).length) {
          controller.set('logs', {error: true});
        }
      });
    }
  }.observes('model.id', 'persistence.online'),
  many_supervisees: function() {
    return (app_state.get('currentUser.supervisees') || []).length > 5;
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
      Ember.set(user, 'avatar_url_with_fallback', Ember.get(user, 'avatar_url'));
      modal.open('record-note', {note_type: 'text', user: user}).then(function() {
        Ember.run.later(function() {
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
      Ember.$("html,body").css('overflow', '');
      Ember.$("#login_overlay").remove();
    },
    show_explanation: function(exp) {
      this.set('show_' + exp + '_explanation', true);
    },
    set_selected: function(selected) {
      this.set('selected', selected);
    },
    intro_video: function(url) {
      if(window.ga) {
        window.ga('send', 'event', 'Intro', 'video', 'Intro video opened');
      }
      modal.open('inline-video', {video: {url: url}, hide_overlay: true});
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
    sync_details: function() {
      var list = ([].concat(persistence.get('sync_log') || [])).reverse();
      modal.open('sync-details', {details: list});
    }
  }
});

