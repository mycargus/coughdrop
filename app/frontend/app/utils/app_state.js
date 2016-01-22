import Ember from 'ember';
import stashes from './_stashes';
import boundClasses from './bound_classes';
import utterance from './utterance';
import modal from './modal';
import CoughDrop from '../app';
import contentGrabbers from './content_grabbers';
import editManager from './edit_manager';
import buttonTracker from './raw_events';
import capabilities from './capabilities';
import scanner from './scanner';
import i18n from './i18n';


// tracks:
// current mode (edit mode, speak mode, default)
// whether the sidebar is enabled
// what the currently-visible board is
// who the currently-logged-in user is
// who we're acting as for speak mode
// whether logging is temporarily disabled
// "back button" history
var app_state = Ember.Object.extend({
  setup: function(container, application) {
    application.register('cough_drop:app_state', app_state, { instantiate: false, singleton: true });
    Ember.$.each(['model', 'controller', 'view', 'route'], function(i, component) {
      application.inject(component, 'app_state', 'cough_drop:app_state');
    });
    this.set('button_list', []);
    this.set('stashes', stashes);
    this.set('installed_app', capabilities.installed_app);
    this.set('no_linky', capabilities.installed_app && capabilities.system == 'iOS');
    this.set('licenseOptions', CoughDrop.licenseOptions);
    this.set('device_name', capabilities.readable_device_name);
    var _this = this;
    if(capabilities.installed_app) {
      Ember.$.ajax({
        url: 'manifest.json',
        type: 'GET',
        dataType: 'json'
      }).then(function(data) {
        _this.set('version', data.version || window.app_version || 'unknown');
      });
    } else {
      this.set('version', window.app_version || 'unknown');
    }
    this.refresh_user();
  },
  reset: function() {
    this.set('currentBoardState', null);
    this.set('sessionUser', null);
    this.set('speakModeUser', null);
    stashes.set('current_mode', 'default');
    stashes.set('root_board_state', null);
    stashes.set('boardHistory', []);
    stashes.set('browse_history', []);
    this.controller = null;
    this.route = null;
    modal.reset();
    boundClasses.clear();
  },
  setup_controller: function(route, controller) {
    this.route = route;
    this.controller = controller;
    if(!controller.get('session.isAuthenticated') && capabilities.mobile && capabilities.browserless) {
      this.set('login_modal', true);
    }
    modal.setup(route);
    contentGrabbers.boardGrabber.transitioner = route;
    CoughDrop.controller = controller;
    stashes.controller = controller;
    boundClasses.setup();
//    controller.set('model', Ember.Object.create());
    utterance.setup(controller);
    this.speak_mode_handlers();
    this.dom_changes_on_board_state_change();
    CoughDrop.session = route.get('session');
    modal.close();
    if(route.get('session.access_token')) {
      var find = CoughDrop.store.findRecord('user', 'self');
      
      find.then(function(user) {
        console.log("user initialization working..");
        if(user.get('local_result') && stashes.get('online')) {
          user.reload().then(function(user) {
            app_state.set('sessionUser', user);
          }, function() { });
        }
        app_state.set('sessionUser', user);
        
        if(stashes.get('speak_mode_user_id')) {
          CoughDrop.store.findRecord('user', stashes.get('speak_mode_user_id')).then(function(user) {
            app_state.set('speakModeUser', user);
          }, function() { 
            console.error('failed trying to speak as ' + stashes.get('speak_mode_user_id'));
          });
        }
      }, function(err) {
        if(stashes.get('current_mode') == 'edit') {
          controller.toggleMode('edit');
        }
        console.log(err);
        console.error("user initialization failed");
        if(err.status == 400 && err.error == 'Not authorized') {
          CoughDrop.session.invalidate(true);
        }
      });
    }
    CoughDrop.session.addObserver('access_token', function() {
      Ember.run.later(function() {
        app_state.refresh_session_user();
      }, 10);
    });
    // TODO: this is a dumb way to do this (remove the "loading..." message)...
    Ember.$('#loading_box').remove();
    Ember.$("body").removeClass('pretty_loader');
  },
  refresh_user: function() {
    var _this = this;
    Ember.run.cancel(_this.refreshing_user);

    function refresh() {
      Ember.run.cancel(_this.refreshing_user);
      _this.refreshing_user = Ember.run.later(function() {
        _this.refresh_user();
      }, 60000 * 15);
    }
    if(_this.get('currentUser') && _this.get('currentUser').reload) {
      _this.get('currentUser').reload().then(function() {
        refresh();
      }, function() {
        refresh();
      });
    } else {  
      refresh();
    }
  },
  global_transition: function(transition) {
    app_state.set('latest_board_id', null);
    app_state.set('login_modal', false);
    // On desktop, setting too soon causes a re-render, but on mobile
    // calling it too late does.
    if(capabilities.mobile) {
      app_state.set('index_view', transition.targetName == 'index');
    }
    if(transition.targetName == 'board.index') {
      boundClasses.setup();
      var delay = app_state.get('currentUser.preferences.board_jump_delay') || window.user_preferences.any_user.board_jump_delay;
      Ember.run.later(this, this.check_for_board_readiness, delay, 100);
    }
    var controller = this.controller;
    controller.updateTitle();
    modal.close();
    if(app_state.get('edit_mode')) {
      // TODO: confirm leaving exit mode before continuing
      app_state.toggle_edit_mode();
    }
//           Ember.$(".hover_button").remove();
    this.set('hide_search', transition.targetName == 'search');
    if(transition.targetName != 'board.index') {
      app_state.set('currentBoardState', null);
    }
    if(!app_state.get('sessionUser') && this.route.get('session.isAuthenticated')) {
      app_state.refresh_session_user();
    }
  },
  finish_global_transition: function() {
    app_state.set('already_homed', true);
    Ember.run.next(function() {
      var target = app_state.get('controller.currentRouteName');
      app_state.set('index_view', target == 'index');
    });
    // footer was showing up too quickly and looking weird when the rest of the page hadn't
    // re-rendered yet.
    if(!this.get('currentBoardState')) {
      try {
       this.controller.set('footer', true);
      } catch(e) { }
    }
  },
  set_latest_board_id: function() {
    this.set('latest_board_id', this.get('currentBoardState.id'));
  }.observes('currentBoardState.id'),
  check_for_board_readiness: function(delay) {
    if(this.check_for_board_readiness.timer) {
      Ember.run.cancel(this.check_for_board_readiness.timer);
    }
    var id = app_state.get('latest_board_id');
    if(id) {
      var $board = Ember.$(".board[data-id='" + id + "']");
      var _this = this;
      if($board.length && $board.find(".button_row,canvas").length) {
        Ember.run.later(function() {
          buttonTracker.transitioning = false;
        }, delay);
        return;
      }
    }
    this.check_for_board_readiness.timer = Ember.run.later(this, this.check_for_board_readiness, delay, 100);
  },
  jump_to_board: function(new_state, old_state) {
    buttonTracker.transitioning = true;
    var history = this.get_history();
    old_state = old_state || this.get('currentBoardState');
    history.push(old_state);
    stashes.log({
      action: 'open_board',
      previous_key: old_state,
      new_id: new_state
    });
    this.controller.send('hide_temporary_sidebar');
    this.set_history([].concat(history));
    this.controller.transitionToRoute('board', new_state.key);
  },
  back_one_board: function() {
    buttonTracker.transitioning = true;
    var history = this.get_history();
    var state = history.pop();
    stashes.log({
      action: 'back'
    });
    this.set_history([].concat(history));
    this.controller.transitionToRoute('board', state.key);
  },
  jump_to_root_board: function(options) {
    options = options || {};
    var index_as_fallback = options.index_as_fallback;
    var auto_home = options.auto_home;

    this.set_history([]);
    var current = this.get('currentBoardState');
    var state = stashes.get('temporary_root_board_state') || stashes.get('root_board_state');
    state = state || this.get('currentUser.preferences.home_board');
    
    var do_log = false;
    if(state && state.key) {
      if(app_state.get('currentBoardState.key') != state.key) {
        buttonTracker.transitioning = true;
        this.controller.transitionToRoute('board', state.key);
        do_log = current && current.key && state.key != current.key;
      }
    } else if(index_as_fallback) {
      this.controller.transitionToRoute('index');
      do_log = current && current.key;
    }
    if(do_log) {
      stashes.log({
        action: (auto_home ? 'auto_home' : 'home')
      });
    }
  },
  toggle_speak_mode: function(decision) {
    if(decision) {
      modal.close(true);
    }
    var current = app_state.get('currentBoardState');
    var preferred = app_state.get('currentUser.preferences.home_board');
    
    if(!app_state.get('speak_mode')) {
      // if it's in the speak-mode-user's board set, keep the original home board,
      // otherwise set the current board to home for now
      var user = app_state.get('speakModeUser') || app_state.get('currentUser');
      if(user && (user.get('stats.board_set_ids') || []).indexOf(app_state.get('currentBoardState.id')) >= 0) {
        decision = decision || 'rememberRealHome';
      } else {
        decision = decision || 'currentAsHome';
      }
    }
    
    if(!current || decision == 'goHome') {
      this.home_in_speak_mode();
    } else if(stashes.get('current_mode') == 'speak') {
      if(app_state.get('currentUser.preferences.require_speak_mode_pin') && decision != 'off' && app_state.get('currentUser.preferences.speak_mode_pin')) {
        modal.open('speak-mode-pin', {actual_pin: app_state.get('currentUser.preferences.speak_mode_pin')});
      } else {
        this.toggle_mode('speak');
      }
    } else if(decision == 'currentAsHome' || !preferred || (preferred && current && preferred.key == current.key)) {
      this.toggle_mode('speak');
    } else if(decision == 'rememberRealHome') {
      this.toggle_mode('speak', {override_state: preferred});
    } else {
      this.controller.send('pickWhichHome');
    }
  },
  toggle_edit_mode: function(decision) {
    editManager.clear_history();
    if(decision == null && !app_state.get('edit_mode') && this.controller && this.controller.get('board').get('model').get('could_be_in_use')) {
      var _this = this;
      modal.open('confirm-edit-board', {board: this.controller.get('board').get('model')}).then(function(res) {
        if(res == 'tweak') {
          _this.controller.send('tweakBoard');
        }
      });
      return;
    }
    this.toggle_mode('edit');
  },
  clear_mode: function() {
    stashes.persist('current_mode', 'default');
    stashes.persist('last_mode', null);
    editManager.clear_paint_mode();
  },
  toggle_mode: function(mode, opts) {
    opts = opts || {};
    utterance.clear();
    var current_mode = stashes.get('current_mode');
    if(opts && opts.force) { current_mode = null; }
    if(mode == 'speak') {
      var board_state = app_state.get('currentBoardState');
      if(opts && opts.override_state) {
        board_state = opts.override_state;
      }
      stashes.persist('root_board_state', board_state);
    }
    if(current_mode == mode) {
      if(mode == 'edit' && stashes.get('last_mode')) {
        stashes.persist('current_mode', stashes.get('last_mode'));
      } else {
        stashes.persist('current_mode', 'default');
      }
      stashes.persist('last_mode', null);
    } else {
      if(mode == 'edit') {
        stashes.persist('last_mode', stashes.get('current_mode'));
      } else if(mode == 'speak') {
        var speaking_as_someone_else = app_state.get('speakModeUser.id') && app_state.get('speakModeUser.id') != app_state.get('sessionUser.id');
        // TODO: consider some kind of reminder for free subscription accounts, if you 
        // think they shouldn't be using as a speak mode user
        if(app_state.get('currentUser') && !opts.reminded && app_state.get('currentUser.expired') && !speaking_as_someone_else) {
          return modal.open('premium-required', {remind_to_upgrade: true, action: 'app_speak_mode'}).then(function() {
            opts.reminded = true;
            app_state.toggle_mode(mode, opts);
          });
        }
        var geo_enabled = app_state.get('currentUser.preferences.geo_logging');
        if(geo_enabled) {
          stashes.geo.poll();
        }
      }
      stashes.persist('current_mode', mode);
    }
    stashes.persist('temporary_root_board_state', null);
    stashes.persist('sticky_board', false);
    editManager.clear_paint_mode();
  },
  home_in_speak_mode: function(opts) {
    opts = opts || {};
    var speak_mode_user = opts.user || app_state.get('currentUser');
    var preferred = (speak_mode_user && speak_mode_user.get('preferences.home_board')) || opts.fallback_board_state || stashes.get('root_board_state') || {key: 'example/yesno'};
    // TODO: same as above, in .toggle_mode
    if(speak_mode_user && !opts.reminded && speak_mode_user.get('expired')) {
      return modal.open('premium-required', {remind_to_upgrade: true, action: 'app_speak_mode'}).then(function() {
        opts.reminded = true;
        app_state.home_in_speak_mode(opts);
      });
    }
    this.toggle_mode('speak', {force: true, override_state: preferred});
    this.controller.transitionToRoute('board', preferred.key);
  },
  check_scanning: function() {
    var _this = this;
    Ember.run.later(function() {
      if(app_state.get('speak_mode') && _this.get('currentUser.preferences.device.scanning')) { // scanning mode
        buttonTracker.scanning_enabled = true;
        buttonTracker.any_select = _this.get('currentUser.preferences.device.scanning_select_on_any_event');
        buttonTracker.select_keycode = _this.get('currentUser.preferences.device.scanning_select_keycode');
        buttonTracker.next_keycode = _this.get('currentUser.preferences.device.scanning_next_keycode');
        buttonTracker.left_screen_action = _this.get('currentUser.preferences.device.scanning_left_screen_action');
        buttonTracker.right_screen_action = _this.get('currentUser.preferences.device.scanning_right_screen_action');
        scanner.start({
          scan_mode: _this.get('currentUser.preferences.device.scanning_mode'),
          interval: _this.get('currentUser.preferences.device.scanning_interval'),
          vertical_chunks: _this.get('currentUser.preferences.device.scanning_region_rows'),
          horizontal_chunks: _this.get('currentUser.preferences.device.scanning_region_columns')
        });
      } else {
        buttonTracker.scanning_enabled = false;
        // this was breaking the "find button" interface when you get to the second board
        if(scanner.interval) {
          scanner.stop();
        }
      }
    }, 1000);
  },
  refresh_session_user: function() {
    CoughDrop.store.findRecord('user', 'self').then(function(user) {
      if(user.get('local_result')) {
        user.reload().then(function(user) {
          app_state.set('sessionUser', user);
        }, function() { });
      }
      app_state.set('sessionUser', user);
    }, function() { });
  },
  set_speak_mode_user: function(board_user_id, jump_home, keep_as_self) {
    var session_user_id = this.get('sessionUser.id');
    if(board_user_id == 'self' || (session_user_id && board_user_id == session_user_id)) {
      app_state.set('speakModeUser', null);
      stashes.persist('speak_mode_user_id', null);
      if(!app_state.get('speak_mode')) {
        this.toggle_speak_mode();
      } else {
        this.home_in_speak_mode();
      }
    } else {
      // TODO: this won't get the device-specific settings correctly unless
      // device_key matches across the users
      var _this = this;

      CoughDrop.store.findRecord('user', board_user_id).then(function(u) {
        var data = Ember.RSVP.resolve(u);
        if(u.get('local_result') && stashes.get('online')) {
          data = u.reload();
        }
        data.then(function(u) {
          if(keep_as_self) {
            app_state.set('speakModeUser', null);
          } else {
            app_state.set('speakModeUser', u);
          }
          stashes.persist('speak_mode_user_id', (u && u.get('id')));
          if(jump_home) {
            _this.home_in_speak_mode({
              user: u,
              fallback_board_state: app_state.get('sessionUser.preferences.home_board')
            });
          } else {
            if(!app_state.get('speak_mode')) {
              _this.toggle_speak_mode();
            }
          }
        }, function() {
          modal.danger(i18n.t('user_retrive_failed', "Failed to retrieve user for Speak Mode"));
        });
      }, function() {
        modal.danger(i18n.t('user_retrive_failed', "Failed to retrieve user for Speak Mode"));
      });
    }
  },
  say_louder: function() {
    this.controller.sayLouder();
  },
  set_and_say_buttons(vocalizations) {
    this.controller.set_and_say_buttons(vocalizations);
  },
  set_current_user: function() {
    this.did_set_current_user = true;
    if(app_state.get('speak_mode') && app_state.get('speakModeUser')) {
      app_state.set('currentUser', app_state.get('speakModeUser'));
    } else {
      var user = app_state.get('sessionUser');
      if(user && !user.get('preferences.progress.app_added') && (navigator.standalone || (capabilities.installed_app && capabilities.mobile))) {
        user.set('preferences.progress.app_added', true);
        user.save().then(null, function() { });
      }
      app_state.set('currentUser', user);
    }
  }.observes('sessionUser', 'speak_mode', 'speakModeUser'),
  dom_changes_on_board_state_change: function() {
    if(!this.get('currentBoardState')) {
      Ember.$('#speak_mode').popover('destroy');
      Ember.$('body').css('overflow', '');
    } else if(!app_state.get('testing')) {
      Ember.$('body').css('overflow', 'hidden').scrollTop(0);
      try {
        this.controller.set('footer', false);
      } catch(e) { }
    }
  }.observes('currentBoardState'),
  update_button_tracker: function() {
    buttonTracker.minimum_press = this.get('currentUser.preferences.activation_minimum');
    buttonTracker.activation_location = this.get('currentUser.preferences.activation_location');
    buttonTracker.short_press_delay = this.get('currentUser.preferences.activation_cutoff');
    if(this.get('currentUser.preferences.activation_on_start')) {
      buttonTracker.short_press_delay = 50;
    }
  }.observes('currentUser.preferences.activation_location', 'currentUser.preferences.activation_minimum', 'currentUser.preferences.activation_cutoff', 'currentUser.preferences.activation_on_start'),
  monitor_scanning: function() {
    this.check_scanning();
  }.observes('speak_mode', 'currentBoardState'),
  get_history: function() {
    if(app_state.get('speak_mode')) {
      return stashes.get('boardHistory');
    } else {
      return stashes.get('browse_history');
    }
  },
  set_history: function(hist) {
    if(app_state.get('speak_mode')) {
      stashes.persist('boardHistory', hist);
    } else {
      stashes.persist('browse_history', hist);
    }
  },
  feature_flags: function() {
    var res = this.get('currentUser.feature_flags') || {};
    (window.enabled_frontend_features || []).forEach(function(feature) {
      res[feature] = true;
    });
    return res;
  }.property('currentUser.feature_flags'),
  empty_header: function() {
    return !!(this.get('default_mode') && !this.get('currentBoardState') && !this.get('hide_search'));
  }.property('default_mode', 'currentBoardState', 'hide_search'),
  header_size: function() {
    var size = this.get('currentUser.preferences.device.vocalization_height') || window.user_preferences.device.vocalization_height;
    return size;
  }.property('currentUser.preferences.device.vocalization_height'),
  header_height: function() {
    if(this.get('speak_mode')) {
      var size = this.get('header_size');
      if(size == 'tiny') {
        return 50;
      } else if(size == 'small') {
        return 70;
      } else if(size == 'medium') {
        return 100;
      } else if(size == 'large') {
        return 150;
      } else if(size == 'huge') {
        return 200;
      }
    } else {
      return 70;
    }
  }.property('header_size', 'speak_mode'), 
  check_for_full_premium: function(user, action) {
    if(user && user.get('expired')) {
      return modal.open('premium-required', {action: action});
    } else {
      return Ember.RSVP.resolve();
    }
  },
  check_for_really_expired: function(user) {
    if(user && user.get('really_expired')) {
      return modal.open('premium-required', {cancel_on_close: true, remind_to_upgrade: true});
    } else {
      return Ember.RSVP.resolve();
    }
  },
  speak_mode_handlers: function() {
    if(this.get('speak_mode')) {
      stashes.set('logging_enabled', !!(this.get('speak_mode') && this.get('currentUser.preferences.logging')));
      stashes.set('speaking_user_id', this.get('currentUser.id'));
      // this method is getting called again on every board load, even if already in speak mode. This check
      // limits the following block to once per speak-mode-activation.
      if(!this.get('last_speak_mode')) {
        capabilities.wakelock('speak', true);
        this.set_history([]);
        if(stashes.get('logging_enabled')) {
          modal.notice(i18n.t('logging_enabled', "Logging is enabled"), true);
        }
        if(!capabilities.installed_app && !capabilities.mobile && this.get('currentUser.preferences.device.fullscreen')) {
          capabilities.fullscreen(true).then(null, function() {
            modal.warning(i18n.t('fullscreen_failed', "Full Screen Mode failed to load"), true);
          });
        }
        capabilities.volume_check().then(function(level) {
          console.log("volume is " + level);
          if(level === 0) {
            modal.warning(i18n.t('volume_is_off', "Volume is muted, you will not be able to hear speech"), true);
          } else if(level < 0.2) {
            modal.warning(i18n.t('volume_is_low', "Volume is low, you may not be able to hear speech"), true);
          }
        });

      }
    } else if(!this.get('speak_mode') && this.get('last_speak_mode') !== undefined) {
      capabilities.wakelock('speak', false);
      stashes.persist('temporary_root_board_state', null);
      stashes.persist('sticky_board', false);
      stashes.persist('speak_mode_user_id', null);
      capabilities.fullscreen(false);
    }
    this.set('last_speak_mode', !!this.get('speak_mode'));
  }.observes('speak_mode', 'currentUser.id', 'currentUser.preferences.logging'),
  speak_mode: function() {
    return !!(stashes.get('current_mode') == 'speak' && this.get('currentBoardState'));
  }.property('stashes.current_mode', 'currentBoardState'),
  edit_mode: function() {
    return !!(stashes.get('current_mode') == 'edit' && this.get('currentBoardState'));
  }.property('stashes.current_mode', 'currentBoardState'),
  default_mode: function() {
    return !!(stashes.get('current_mode') == 'default' || !this.get('currentBoardState'));
  }.property('stashes.current_mode', 'currentBoardState'),
  limited_speak_mode_options: function() {
    return this.get('speak_mode');
    // TODO: decide if this should be an option at all
    //return this.get('speak_mode') && this.get('currentUser.preferences.require_speak_mode_pin');
  }.property('speak_mode', 'currentUser.preferences.require_speak_mode_pin'),
  current_board_name: function() {
    var state = this.get('currentBoardState');
    if(state && state.key) {
      return state.key.split(/\//)[1];
    }
    return null;
  }.property('currentBoardState'),
  current_board_user_name: function() {
    var state = this.get('currentBoardState');
    if(state && state.key) {
      return state.key.split(/\//)[0];
    }
    return null;
  }.property('currentBoardState'),
  current_board_is_home: function() {
    var board = this.get('currentBoardState');
    var user = this.get('currentUser');
    return !!(board && user && user.get('preferences.home_board.id') == board.id);
  }.property('currentBoardState', 'currentUser', 'currentUser.preferences.home_board.id'),
  current_board_is_speak_mode_home: function() {
    var state = stashes.get('temporary_root_board_state') || stashes.get('root_board_state');
    var current = this.get('currentBoardState');
    return this.get('speak_mode') && state && current && state.key == current.key;
  }.property('speak_mode', 'currentBoardState', 'stashes.root_board_state', 'stashes.temporary_root_board_state'),
  current_board_not_home_or_supervising: function() {
    return !this.get('current_board_is_home') || (this.get('currentUser.supervisees') || []).length > 0;
  }.property('current_board_is_home', 'currentUser.supervisees'),
  current_board_in_board_set: function() {
    return (this.get('currentUser.stats.board_set_ids') || []).indexOf(this.get('currentBoardState.id')) >= 0;
  }.property('currentUser.stats.board_set_ids', 'currentBoardState'),
  current_board_in_extended_board_set: function() {
    return (this.get('currentUser.stats.board_set_ids_including_supervisees') || []).indexOf(this.get('currentBoardState.id')) >= 0;
  }.property('currentUser.stats.board_set_ids_including_supervisees', 'currentBoardState'),
  speak_mode_possible: function() {
    return !!(this.get('currentBoardState') || this.get('currentUser.preferences.home_board.key'));
  }.property('currentBoardState', 'currentUser', 'currentUser.preferences.home_board.key'),
  board_in_current_user_set: function() {
    return (this.get('currentUser.stats.board_set_ids') || []).indexOf(this.get('currentBoardState.id')) >= 0;
  }.property('currentUser.stats.board_set_ids', 'currentBoardState.id'),
  empty_board_history: function() {
    // TODO: this is borken
    return this.get_history().length === 0;
  }.property('stashes.boardHistory', 'stashes.browse_history', 'speak_mode'),
  sidebar_visible: function() {
    // TODO: does this need to trigger board resize event? maybe...
    return this.get('speak_mode') && (stashes.get('sidebarEnabled') || this.get('currentUser.preferences.quick_sidebar'));
  }.property('speak_mode', 'stashes.sidebarEnabled', 'currentUser', 'currentUser.preferences.quick_sidebar'),
  sidebar_pinned: function() {
    return this.get('speak_mode') && this.get('currentUser.preferences.quick_sidebar');
  }.property('speak_mode', 'currentUser', 'currentUser.preferences.quick_sidebar'),
  testing: function() {
    return Ember.testing;
  }.property(),
  logging_paused: function() {
    return !!stashes.get('logging_paused_at');
  }.property('stashes.logging_paused_at'),
  board_virtual_dom: function() {
    var _this = this;
    var dom = {
      sendAction: function() {
      },
      trigger: function(event, id, args) {
        if(CoughDrop.customEvents[event]) {
          dom.sendAction(CoughDrop.customEvents[event], id, {event: args});
        }
      },
      each_button: function(callback) {
        var rows =_this.get('board_virtual_dom.ordered_buttons') || [];
        var idx = 0;
        rows.forEach(function(row) {
          row.forEach(function(b) {
            if(!b.hidden) {
              b.idx = idx;
              idx++;
              callback(b);
            }
          });
        });
      },
      add_state: function(state, id) {
        if(state == 'touched' || state == 'hover') {
          dom.clear_state(state, id);
          dom.each_button(function(b) {
            if(b.id == id && !Ember.get(b, state)) {
              Ember.set(b, state, true);
              dom.sendAction('redraw', b.id);
            }
          });
        }
      },
      clear_state: function(state, except_id) {
        dom.each_button(function(b) {
          if(b.id != except_id && Ember.get(b, state)) {
            Ember.set(b, state, false);
            dom.sendAction('redraw', b.id);
          }
        });
      },
      clear_touched: function() {
        dom.clear_state('touched');
//        dom.sendAction('redraw');
      },
      clear_hover: function() {
        dom.clear_state('hover');
//        dom.sendAction('redraw');
      },
      button_result: function(b) {
        var pos = b.positioning;
        return {
          id: b.id,
          left: pos.left,
          top: pos.top,
          width: pos.width,
          height: pos.height,
          button: true,
          index: b.idx
        };
      },
      button_from_point: function(x, y) {
        var res = null;
        dom.each_button(function(b) {
          var pos = b.positioning;
          if(!b.hidden) {
            if(x > pos.left - 2 && x < pos.left + pos.width + 2) {
              if(y > pos.top - 2 && y < pos.top + pos.height + 2) {
                res = dom.button_result(b);
              }
            }
          }
        });
        return res;
      },
      button_from_index: function(idx) {
        var res = null;
        dom.each_button(function(b) {
          if(b.idx == idx || (idx == -2)) {
            res = dom.button_result(b);
          }
        });
        return res;
      },
      button_from_id: function(id) {
        var res = null;
        dom.each_button(function(b) {
          var pos = b.positioning;
          if(b.id == id) {
            res = dom.button_result(b);
          }
        });
        return res;
      }
    };
    return dom;
  }.property()
}).create({
});

if(!app_state.get('testing')) {
  setInterval(function() {
    app_state.set('refresh_stamp', new Date());
  }, 5*60*1000);
}

app_state.ScrollTopRoute = Ember.Route.extend({
  activate: function() {
    this._super();
    if(!this.get('already_scrolled')) {
      this.set('already_scrolled', true);
      Ember.$('body').scrollTop(0);
    }
  }
});
export default app_state;