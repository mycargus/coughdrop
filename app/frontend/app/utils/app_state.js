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
import session from './session';
import speecher from './speecher';
import geolocation from './geo';
import i18n from './i18n';
import frame_listener from './frame_listener';
import Button from './button';

// tracks:
// current mode (edit mode, speak mode, default)
// whether the sidebar is enabled
// what the currently-visible board is
// who the currently-logged-in user is
// who we're acting as for speak mode
// whether logging is temporarily disabled
// "back button" history
var app_state = Ember.Object.extend({
  setup: function(application) {
    application.register('cough_drop:app_state', app_state, { instantiate: false, singleton: true });
    Ember.$.each(['model', 'controller', 'view', 'route'], function(i, component) {
      application.inject(component, 'app_state', 'cough_drop:app_state');
    });
    this.set('button_list', []);
    this.set('stashes', stashes);
    this.set('geolocation', geolocation);
    this.set('installed_app', capabilities.installed_app);
    this.set('no_linky', capabilities.installed_app && capabilities.system == 'iOS');
    this.set('licenseOptions', CoughDrop.licenseOptions);
    this.set('device_name', capabilities.readable_device_name);
    this.set('currentBoardState', null);
    var _this = this;
    this.set('version', window.app_version || 'unknown');
    var _this = this;
    capabilities.battery.listen(function(battery) {
      battery.level = Math.round(battery.level * 100);
      if(battery.level != _this.get('battery.level') || battery.charging !== _this.get('battery.charging')) {
        _this.set('battery', battery);
        _this.set('battery.progress_style', new Ember.String.htmlSafe("width: " + parseInt(battery.level) + "%;"));
        _this.set('battery.low', battery.level < 30);
        _this.set('battery.really_low', battery.level < 15);
        if(battery.level <= 15 && !battery.charging) {
          _this.set('battery.progress_class', "progress-bar progress-bar-danger");
        } else if(battery.level <= 30 && !battery.charging) {
          _this.set('battery.progress_class', "progress-bar progress-bar-warning");
        } else {
          _this.set('battery.progress_class', "progress-bar progress-bar-success");
        }
      }
    });
    capabilities.ssid.listen(function(ssid) {
      _this.set('current_ssid', ssid);
    });
    this.refresh_user();
  },
  reset: function() {
    this.set('currentBoardState', null);
    this.set('currentUser', null);
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
    if(!session.get('isAuthenticated') && capabilities.mobile && capabilities.browserless) {
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
    if(session.get('access_token')) {
      var find_user = function(last_try) {
        var find = CoughDrop.store.findRecord('user', 'self');

        find.then(function(user) {
          console.log("user initialization working..");
          if(!user.get('fresh') && stashes.get('online')) {
            user.reload().then(function(user) {
              app_state.set('sessionUser', user);
            }, function() { });
          }
          app_state.set('sessionUser', user);

          if(stashes.get('speak_mode_user_id') || stashes.get('referenced_speak_mode_user_id')) {
            var ref_id = stashes.get('speak_mode_user_id') || stashes.get('referenced_speak_mode_user_id');
            CoughDrop.store.findRecord('user', ref_id).then(function(user) {
              if(stashes.get('speak_mode_user_id')) {
                app_state.set('speakModeUser', user);
              }
              app_state.set('referenced_speak_mode_user', user);
            }, function() {
              console.error('failed trying to speak as ' + ref_id);
            });
          }
        }, function(err) {
          if(stashes.get('current_mode') == 'edit') {
            controller.toggleMode('edit');
          }
          console.log(err);
          console.log(err.status);
          console.log(err.error);
          var do_logout = err.status == 400 && (err.error == 'Not authorized' || err.error == "Invalid token");
          console.log("will log out: " + (do_logout || last_try));
          console.error("user initialization failed");
          if(do_logout || last_try) {
            if(session.get('user_name') && session.get('user_name').match(/wahl/)) {
              alert("Hi! You found the logout error! Please take a screenshot! " + err.status + " " + JSON.stringify(err));
            }
            session.invalidate(true);
          } else {
            Ember.run.later(function() {
              find_user(true);
            }, 1000);
          }
        });
      };
      find_user();
    }
    session.addObserver('access_token', function() {
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
    if(transition.isAborted) { return; }
    app_state.set('from_url', app_state.get('route.router.url'));
    var pieces = this.get('route.router.router.recognizer').recognize(app_state.get('from_url'));
    if(pieces && pieces.length > 0) {
      var args = [pieces[pieces.length - 1].handler];
      var handle_piece = function(name) {
        args.push(piece.params[name]);
      };
      for(var idx = 0; idx < pieces.length; idx++) {
        var piece = pieces[idx];
        if(piece && piece.isDynamic) {
          transition.router.getHandler(piece.handler)._names.forEach(handle_piece);
        }
      }
      if(args[0] != 'board.index') {
        app_state.set('from_route', args);
      }
    }
//     console.log("came from", app_state.get('from_route'));
    app_state.set('latest_board_id', null);
    app_state.set('login_modal', false);
    app_state.set('to_target', transition.targetName);
    if(transition.targetName == 'board.index' && (app_state.get('from_route') || [])[0] == 'setup') {
      app_state.set('set_as_root_board_state', true);
    }

    // On desktop, setting too soon causes a re-render, but on mobile
    // calling it too late does.
    if(capabilities.mobile) {
//       app_state.set('index_view', transition.targetName == 'index');
    }
    if(transition.targetName == 'board.index') {
      boundClasses.setup();
      var delay = app_state.get('currentUser.preferences.board_jump_delay') || window.user_preferences.any_user.board_jump_delay;
      CoughDrop.log.track('global transition handled');
      Ember.run.later(this, this.check_for_board_readiness, delay, 50);
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
    if(!app_state.get('sessionUser') && session.get('isAuthenticated')) {
      app_state.refresh_session_user();
    }
  },
  finish_global_transition: function() {
    app_state.set('already_homed', true);
    Ember.run.next(function() {
      var target = app_state.get('controller.currentRouteName');
//       app_state.set('index_view', target == 'index');
    });
    // footer was showing up too quickly and looking weird when the rest of the page hadn't
    // re-rendered yet.
    if(!this.get('currentBoardState')) {
      try {
        this.controller.set('footer', true);
        if(this.get('to_target') && this.get('to_target') != 'setup') {
          this.controller.set('setup_footer', false);
        }
      } catch(e) { }
    }
    if(CoughDrop.embedded && !this.get('speak_mode')) {
      if(window.top && window.top != window.self) {
        window.top.location.replace(window.location);
      }
    }
  },
  check_for_protected_usage: function() {
    var protect_user = !!this.get('currentUser.preferences.protected_usage');
    if(window._trackJs) {
      window._trackJs.disabled = protect_user;
    }
    CoughDrop.protected_user = protect_user;
    stashes.persist('protected_user', protect_user);
  }.observes('currentUser.preferences.protected_usage'),
  set_root_board_state: function() {
    if(this.get('set_as_root_board_state') && this.get('currentBoardState')) {
      stashes.persist('root_board_state', this.get('currentBoardState'));
      this.set('set_as_root_board_state', false);
    }
  }.observes('set_as_root_board_state', 'currentBoardState'),
  board_url: function() {
    if(this.get('currentBoardState.key')) {
      return Ember.String.htmlSafe((capabilities.api_host || (location.protocol + "//" + location.host)) + "/" + this.get('currentBoardState.key'));
    } else {
      return null;
    }
  }.property('currentBoardState.key'),
  h1_class: function() {
    var res = "";
    if(this.get('currentBoardState.id')) {
      res = res + "with_board " ;
      if(this.get('from_route') && !this.get('edit_mode')) {
        res = res + "sr-only ";
      }
    }
    return new Ember.String.htmlSafe(res);
  }.property('currentBoardState.id', 'from_route', 'edit_mode'),
  nav_header_class: function() {
    var res = "no_beta ";
    if(this.get('currentBoardState.id') && this.get('from_route') && !this.get('edit_mode')) {
      res = res + "board_done ";
    }
    return new Ember.String.htmlSafe(res);
  }.property('currentBoardState.id', 'from_route'),
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
      var $integration = Ember.$("#integration_frame");
      var _this = this;
      if($integration.length || ($board.length && $board.find(".button_row,canvas").length)) {
        Ember.run.later(function() {
          CoughDrop.log.track('done transitioning');
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
    if(new_state && new_state.home_lock) {
      this.set('temporary_root_board_key', new_state.key);
    }
    this.controller.send('hide_temporary_sidebar');
    this.set_history([].concat(history));
    this.controller.transitionToRoute('board', new_state.key);
  },
  check_for_lock_on_board_state: function() {
    var state = this.get('currentBoardState');
    if(state && state.key) {
      if(state.key == this.get('temporary_root_board_key')) {
        this.toggle_home_lock(true);
      }
      this.set('temporary_root_board_key', null);
    }
  }.observes('currentBoardState'),
  toggle_home_lock: function(force) {
    var state = stashes.get('root_board_state');
    var current = app_state.get('currentBoardState');
    if(force === false || (stashes.get('temporary_root_board_state') && force !== true)) {
      stashes.persist('temporary_root_board_state', null);
    } else {
      if(state && current && state.key != current.key) {
        stashes.persist('temporary_root_board_state', app_state.get('currentBoardState'));
        app_state.set_history([]);
      }
    }
  },
  toggle_modeling: function(enable) {
    if(enable === undefined || enable === null) {
      enable = !app_state.get('manual_modeling');
    }
    app_state.set('last_activation', (new Date()).getTime());
    app_state.set('manual_modeling', !!enable);
    if(enable) {
      app_state.set('modeling_started', (new Date()).getTime());
    }
  },
  update_modeling: function() {
    if(this.get('modeling')) {
      stashes.set('modeling', !!this.get('modeling'));
    }
  }.observes('modeling'),
  modeling: function() {
    var res = !!(this.get('manual_modeling') || this.get('modeling_for_user'));
    return res;
  }.property('manual_modeling', 'modeling_for_user', 'modeling_ts'),
  modeling_for_user: function() {
    var res = this.get('speak_mode') && this.get('currentUser') && this.get('referenced_speak_mode_user') && app_state.get('currentUser.id') != this.get('referenced_speak_mode_user.id');
    // this is weird and hacky, but for some reason modeling wasn't reliably updating when modeling_for_user changed
    this.set('modeling_ts', (new Date()).getTime() + "_" + Math.random());
    return !!res;
  }.property('speak_mode', 'currentUser', 'referenced_speak_mode_user'),
  auto_clear_modeling: function() {
    if(this.get('manual_modeling')) {
      var now = (new Date()).getTime();
      if(!app_state.get('last_activation')) {
        app_state.set('last_activation', now);
      }
      // progressively get more aggressive at auto-clearing modeling flag
      var duration = now - app_state.get('modeling_started');
      // by default, clear manual modeling mode after 5 minutes of inactivity
      var cutoff = 5 * 60 * 1000;
      // if you've been modeling for more than 30 minutes, then auto-clear after
      // 5 seconds without modeling
      if(duration > (30 * 60 * 1000)) {
        cutoff = 5 * 1000;
      // if you've been modeling for 10-30 minutes, then auto-clear modeling after
      // 30 seconds of inactivity
      } else if(duration > (10 * 60 * 1000)) {
        cutoff = 30 * 1000;
      // if you've been modeling for 5-10 minutes, then auto-clear after 60 inactive seconds
      } else if(duration > (5 * 60 * 1000)) {
        cutoff = 60 * 1000;
      }
      if(now - app_state.get('last_activation') > cutoff) {
        app_state.toggle_modeling();
      }
    }
  }.observes('short_refresh_stamp', 'modeling'),
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
    var preferred = app_state.get('speakModeUser.preferences.home_board') || app_state.get('currentUser.preferences.home_board');
    if(preferred && current) {
      Ember.set(preferred, 'text_direction', current.text_direction);
    }

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
    } else if(decision == 'goBrowsedHome') {
      this.toggle_mode('speak', {override_state: stashes.get('root_board_state') || preferred});
    } else if(stashes.get('current_mode') == 'speak') {
      if(this.get('embedded')) {
        modal.open('about-coughdrop', {no_exit: true});
      } else if(app_state.get('currentUser.preferences.require_speak_mode_pin') && decision != 'off' && app_state.get('currentUser.preferences.speak_mode_pin')) {
        modal.open('speak-mode-pin', {actual_pin: app_state.get('currentUser.preferences.speak_mode_pin')});
      } else {
        this.toggle_mode('speak');
      }
    } else if(decision == 'currentAsHome' || !preferred || (preferred && current && preferred.key == current.key)) {
      this.toggle_mode('speak', {temporary_home: true, override_state: preferred});
    } else if(decision == 'rememberRealHome') {
      this.toggle_mode('speak', {override_state: preferred});
    } else {
      this.controller.send('pickWhichHome');
    }
  },
  toggle_edit_mode: function(decision) {
    editManager.clear_history();
    var _this = this;
    if(!this.get('controller.board.model.permissions.edit') && this.get('feature_flags.edit_before_copying')) {
      modal.open('confirm-needs-copying', {board: this.controller.get('board.model')}).then(function(res) {
        if(res == 'confirm') {
          _this.toggle_mode('edit', {copy_on_save: true});
        }
      });
      return;
    } else if(decision == null && !app_state.get('edit_mode') && this.controller && this.controller.get('board').get('model').get('could_be_in_use')) {
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
    utterance.clear(null, true);
    var current_mode = stashes.get('current_mode');
    var temporary_root_state = null;
    if(opts && opts.force) { current_mode = null; }
    if(mode == 'speak') {
      var board_state = app_state.get('currentBoardState');
      if(opts && opts.override_state) {
        if(opts.temporary_home && board_state && board_state.id != opts.override_state.id) {
          temporary_root_state = board_state;
        }
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
      stashes.persist('copy_on_save', null);
    } else {
      if(mode == 'edit') {
        stashes.persist('last_mode', stashes.get('current_mode'));
        if(opts.copy_on_save) {
          stashes.persist('copy_on_save', app_state.get('currentBoardState.id'));
        }
      } else if(mode == 'speak') {
        var already_speaking_as_someone_else = app_state.get('speakModeUser.id') && app_state.get('speakModeUser.id') != app_state.get('sessionUser.id');
        if(app_state.get('currentUser') && !opts.reminded && app_state.get('currentUser.expired') && !already_speaking_as_someone_else) {
          return modal.open('premium-required', {user_name: app_state.get('currentUser.user_name'), limited_supervisor: app_state.get('currentUser.subscription.limited_supervisor'), remind_to_upgrade: true, action: 'app_speak_mode'}).then(function() {
            opts.reminded = true;
            app_state.toggle_mode(mode, opts);
          });
        }
        // if scanning mode... has to be here because focus will only reliably work when
        // a user-controlled event has occurred, so can't be on a listener
        if(app_state.get('currentUser.preferences.device.scanning') && capabilities.mobile && capabilities.installed_app) { // scanning mode
          scanner.listen_for_input();
        }
      }
      stashes.persist('current_mode', mode);
    }
    stashes.persist('temporary_root_board_state', temporary_root_state);
    stashes.persist('sticky_board', false);
    var $stash_hover = Ember.$("#stash_hover");
    $stash_hover.removeClass('on_button').data('button_id', null);
    editManager.clear_paint_mode();
  },
  home_in_speak_mode: function(opts) {
    opts = opts || {};
    var speak_mode_user = opts.user || app_state.get('currentUser');
    var preferred = (speak_mode_user && speak_mode_user.get('preferences.home_board')) || opts.fallback_board_state || stashes.get('root_board_state') || {key: 'example/yesno'};
    // TODO: same as above, in .toggle_mode
    if(speak_mode_user && !opts.reminded && speak_mode_user.get('expired')) {
      return modal.open('premium-required', {user_name: speak_mode_user.get('user_name'), remind_to_upgrade: true, action: 'app_speak_mode'}).then(function() {
        opts.reminded = true;
        app_state.home_in_speak_mode(opts);
      });
    }
    // NOTE: text-direction is updated on board load, so it's ok that it's not known here
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
        if(capabilities.system == 'iOS' && !capabilities.installed_app && !buttonTracker.left_screen_action && !buttonTracker.right_screen_action) {
          modal.warning(i18n.t('keyboard_may_jump', "NOTE: if you don't have a bluetooth switch installed, the keyboard may keep popping up while trying to scan."));
        }
        modal.close();
        scanner.start({
          scan_mode: _this.get('currentUser.preferences.device.scanning_mode'),
          interval: _this.get('currentUser.preferences.device.scanning_interval'),
          vertical_chunks: _this.get('currentUser.preferences.device.scanning_region_rows'),
          horizontal_chunks: _this.get('currentUser.preferences.device.scanning_region_columns'),
          scanning_auto_select: _this.get('currentUser.preferences.device.scanning_auto_select'),
          audio: _this.get('currentUser.preferences.device.scanning_prompt')
        });
      } else {
        buttonTracker.scanning_enabled = false;
        // this was breaking the "find button" interface when you get to the second board
        if(scanner.interval) {
          scanner.stop();
        }
      }
      buttonTracker.multi_touch_modeling = _this.get('currentUser.preferences.multi_touch_modeling');
      buttonTracker.dwell_modeling = false;
      buttonTracker.dwell_enabled = false;

      if(app_state.get('speak_mode') && _this.get('currentUser.preferences.device.dwell')) {
        buttonTracker.dwell_enabled = true;
        buttonTracker.dwell_timeout = _this.get('currentUser.preferences.device.dwell_timeout');
        buttonTracker.dwell_delay = _this.get('currentUser.preferences.device.dwell_delay');
        buttonTracker.dwell_type = _this.get('currentUser.preferences.device.dwell_type');
        buttonTracker.dwell_animation = _this.get('currentUser.preferences.device.dwell_targeting');
        buttonTracker.dwell_release_distance = _this.get('currentUser.preferences.device.dwell_release_distance');
        buttonTracker.dwell_no_cutoff = _this.get('currentUser.preferences.device.dwell_no_cutoff');
        buttonTracker.dwell_cursor = _this.get('currentUser.preferences.device.dwell_cursor');
        buttonTracker.dwell_modeling = _this.get('currentUser.preferences.device.dwell_modeling');
        buttonTracker.dwell_gravity = _this.get('currentUser.preferences.device.dwell_gravity');
        if(buttonTracker.dwell_type == 'eyegaze') {
          capabilities.eye_gaze.listen('noisy');
        }
      } else {
        buttonTracker.dwell_enabled = false;
        capabilities.eye_gaze.stop_listening();
      }
    }, 1000);
  },
  refresh_session_user: function() {
    CoughDrop.store.findRecord('user', 'self').then(function(user) {
      if(!user.get('fresh')) {
        user.reload().then(function(user) {
          app_state.set('sessionUser', user);
        }, function() { });
      }
      app_state.set('sessionUser', user);
    }, function() { });
  },
  set_auto_synced: function() {
    var auto_sync = this.get('sessionUser.auto_sync');
    if(auto_sync == null) {
      auto_sync = !!capabilities.installed_app;
    }
    if(window.persistence) {
      window.persistence.set('auto_sync', auto_sync);
    }
  }.observes('sessionUser', 'sessionUser.auto_sync'),
  set_speak_mode_user: function(board_user_id, jump_home, keep_as_self) {
    var session_user_id = this.get('sessionUser.id');
    if(board_user_id == 'self' || (session_user_id && board_user_id == session_user_id)) {
      app_state.set('speakModeUser', null);
      app_state.set('referenced_speak_mode_user', null);
      stashes.persist('speak_mode_user_id', null);
      stashes.persist('referenced_speak_mode_user_id', null);
      if(!app_state.get('speak_mode') && jump_home !== true) {
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
        if(!u.get('fresh') && stashes.get('online')) {
          data = u.reload();
        }
        data.then(function(u) {
          if(keep_as_self) {
            app_state.set('speakModeUser', null);
            stashes.persist('speak_mode_user_id', null);
          } else {
            app_state.set('speakModeUser', u);
            stashes.persist('speak_mode_user_id', (u && u.get('id')));
          }
          app_state.set('referenced_speak_mode_user', u);
          stashes.persist('referenced_speak_mode_user_id', (u && u.get('id')));
          if(jump_home) {
            _this.home_in_speak_mode({
              user: u,
              fallback_board_state: app_state.get('sessionUser.preferences.home_board')
            });
          } else {
            if(!app_state.get('speak_mode')) {
              _this.toggle_speak_mode();
            }
            var current = app_state.get('currentBoardState');
            var user_state = u.get('preferences.home_board');
            if(user_state && user_state.id != current.id) {
              stashes.persist('temporary_root_board_state', current);
              stashes.persist('root_board_state', user_state);
            } else {
              stashes.persist('temporary_root_board_state', null);
              stashes.persist('root_board_state', current);
            }
          }
        }, function() {
          modal.error(i18n.t('user_retrive_failed', "Failed to retrieve user for Speak Mode"));
        });
      }, function() {
        modal.error(i18n.t('user_retrive_failed', "Failed to retrieve user for Speak Mode"));
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
      if(user && user.get && !user.get('preferences.progress.app_added') && (navigator.standalone || (capabilities.installed_app && capabilities.mobile))) {
        user.set('preferences.progress.app_added', true);
        user.save().then(null, function() { });
      }
      app_state.set('currentUser', user);
    }
    if(app_state.get('currentUser')) {
      app_state.set('currentUser.load_all_connections', true);
    }
  }.observes('sessionUser', 'speak_mode', 'speakModeUser'),
  eye_gaze_state: function() {
    if(!this.get('currentUser.preferences.device.dwell') || this.get('currentUser.preferences.device.dwell_type') != 'eyegaze') {
      return null;
    }
    var state = {};
    var statuses = Ember.get(capabilities.eye_gaze, 'statuses') || {};
    var active = null, pending = null, dormant = null;
    for(var idx in statuses) {
      if(statuses[idx]) {
        if(statuses[idx].active) {
          if(!statuses[idx].dormant) {
            if(!active || active.dormant) {
              active = statuses[idx];
            }
          } else {
            dormant = dormant || statuses[idx];
          }
        } else if(!statuses[idx].disabled) {
          pending = pending || statuses[idx];
        }
      }
    }

    if(!active && !pending && !dormant) {
      return null;
    }
    return {
      active: !!active,
      dormant: !!(!active && dormant),
      disabled: !!(!active && !dormant),
      status: (active && active.status) || (dormant && dormant.status) || (pending && pending.status)
    };
  }.property('currentUser.preferences.device.dwell', 'currentUser.preferences.device.dwell_type', 'eye_gaze.statuses'),
  dom_changes_on_board_state_change: function() {
    if(!this.get('currentBoardState')) {
      Ember.$('#speak_mode').popover('destroy');
      Ember.$('html,body').css('overflow', '');
    } else if(!app_state.get('testing')) {
      Ember.$('html,body').css('overflow', 'hidden').scrollTop(0);
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
  align_button_list: function() {
    Ember.run.later(function() {
      Ember.$("#button_list").scrollTop(9999999);
    }, 200);
  }.observes('button_list'),
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
      Ember.set(res, feature, true);
    });
    return res;
  }.property('currentUser.feature_flags'),
  set_filesystem: function() {
    stashes.set('allow_local_filesystem_request', !!(!capabilities.installed_app && this.get('feature_flags.chrome_filesystem')));
  }.observes('feature_flags.chrome_filesystem'),
  empty_header: function() {
    return !!(this.get('default_mode') && !this.get('currentBoardState') && !this.get('hide_search'));
  }.property('default_mode', 'currentBoardState', 'hide_search'),
  header_size: function() {
    var size = this.get('currentUser.preferences.device.vocalization_height') || window.user_preferences.device.vocalization_height;
    if(window.innerHeight < 400) {
      size = 'tiny';
    } else if(window.innerHeight < 600 && size != 'tiny') {
      size = 'small';
    }
    return size;
  }.property('currentUser.preferences.device.vocalization_height', 'window_inner_width'),
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
      return modal.open('premium-required', {user_name: user.get('user_name'), action: action}).then(function() {
        return Ember.RSVP.reject({dialog: true});
      });
    } else {
      return Ember.RSVP.resolve({dialog: false});
    }
  },
  check_for_really_expired: function(user) {
    if(user && user.get('really_expired')) {
      return modal.open('premium-required', {user_name: user.get('user_name'), cancel_on_close: true, remind_to_upgrade: true}).then(function() {
        return Ember.RSVP.reject({dialog: true});
      });
    } else {
      return Ember.RSVP.resolve({dialog: false});
    }
  },
  on_user_change: function() {
    if(this.get('currentUser') && CoughDrop.Board) {
      CoughDrop.Board.clear_fast_html();
    }
  }.observes('currentUser'),
  speak_mode_handlers: function() {
    if(this.get('speak_mode')) {

      stashes.set('logging_enabled', !!(this.get('speak_mode') && this.get('currentUser.preferences.logging')));
      stashes.set('geo_logging_enabled', !!(this.get('speak_mode') && this.get('currentUser.preferences.geo_logging')));
      stashes.set('speaking_user_id', this.get('currentUser.id'));

      var geo_enabled = app_state.get('currentUser.preferences.geo_logging') || app_state.get('sidebar_boards').find(function(b) { return b.highlight_type == 'locations' || b.highlight_type == 'custom'; });
      if(geo_enabled) {
        stashes.geo.poll();
      }
      this.set('speak_mode_started', (new Date()).getTime());

      // this method is getting called again on every board load, even if already in speak mode. This check
      // limits the following block to once per speak-mode-activation.
      if(!this.get('last_speak_mode')) {
        if(this.get('currentUser.preferences.speak_on_speak_mode')) {
          Ember.run.later(function() {
            speecher.speak_text(i18n.t('here_we_go', "here we go"), null, {volume: 0.1});
          }, 200);
        }
        if(this.get('currentUser.preferences.device.wakelock') !== false) {
          capabilities.wakelock('speak!', true);
        }
        this.set_history([]);
        var noticed = false;
        if(stashes.get('logging_enabled')) {
          noticed = true;
          modal.notice(i18n.t('logging_enabled', "Logging is enabled"), true);
        }
        if(!capabilities.mobile && this.get('currentUser.preferences.device.fullscreen')) {
          capabilities.fullscreen(true).then(null, function() {
            if(!noticed) {
              modal.warning(i18n.t('fullscreen_failed', "Full Screen Mode failed to load"), true);
            }
          });
        }
        capabilities.tts.reload().then(function(res) {
          console.log("tts reload status");
          console.log(res);
        });
        capabilities.volume_check().then(function(level) {
          console.log("volume is " + level);
          if(level === 0) {
            noticed = true;
            modal.warning(i18n.t('volume_is_off', "Volume is muted, you will not be able to hear speech"), true);
          } else if(level < 0.2) {
            noticed = true;
            modal.warning(i18n.t('volume_is_low', "Volume is low, you may not be able to hear speech"), true);
          }
        });
        capabilities.silent_mode().then(function(silent) {
          if(silent && capabilities.system == 'iOS') {
            modal.warning(i18n.t('ios_muted', "The app is currently muted, so you will not hear speech. To unmute, check the mute switch, and also swipe up from the bottom of the screen to check for app-level muting"));
          }
        });
        var ref_user = this.get('referenced_speak_mode_user') || this.get('currentUser');
        if(ref_user && ref_user.get('goal.summary')) {
          Ember.run.later(function() {
            noticed = true;
            var str = i18n.t('user_apostrophe', "%{user_name}'s ", {user_name: ref_user.get('user_name')});
            str = str + i18n.t('current_goal', "Current Goal: %{summary}", {summary: ref_user.get('goal.summary')});
            modal.notice(str, true);
          }, 100);
        }
      }
      this.set('eye_gaze', capabilities.eye_gaze);
      this.set('embedded', !!(CoughDrop.embedded));
      this.set('full_screen_capable', capabilities.fullscreen_capable());
    } else if(!this.get('speak_mode') && this.get('last_speak_mode') !== undefined) {
      capabilities.wakelock('speak!', false);
      capabilities.fullscreen(false);
      if(this.get('last_speak_mode') !== false) {
        stashes.persist('temporary_root_board_state', null);
        stashes.persist('sticky_board', false);
        stashes.persist('speak_mode_user_id', null);
        stashes.persist('all_buttons_enabled', null);
        app_state.set('label_locale', null);
        stashes.persist('label_locale', null);
        app_state.set('vocalization_locale', null);
        stashes.persist('vocalization_locale', null);
        app_state.set('manual_modeling', false);
        app_state.set('referenced_speak_mode_user', null);
        stashes.persist('referenced_speak_mode_user_id', null);
        if(CoughDrop.Board) {
          CoughDrop.Board.clear_fast_html();
        }
      }
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
  superProtectedSpeakMode: function() {
    return this.get('speak_mode') && this.get('embedded');
  }.property('speak_mode', 'embedded'),
  auto_exit_speak_mode: function() {
    var now = (new Date()).getTime();
    // if we're speaking as the current user and they're a limited supervisor, or if
    // we're speaking/modeling related to a supervisee and they're expired, limit
    // the session to 15 minutes and notify them of the time limit.
    if(this.get('speak_mode') && this.get('speak_mode_started')) {
      var started = this.get('speak_mode_started');
      var done = false;
      // If running speak mode for themselves, supervisors need to not be paid or working withs omeone
      if(this.get('currentUser.id') == this.get('sessionUser.id') && !this.get('referenced_speak_mode_user') && this.get('currentUser.limited_supervisor')) {
        if(started < now - (15 * 60 * 1000)) {
          done = i18n.t('limited_supervisor_timeout', "Speak mode sessions are limited to 15 minutes for supervisors not working with paid communicators");
        }
      // If running speak mode for a communicator, check the status of the communicator
      } else if(this.get('sessionUser.id') != this.get('referenced_speak_mode_user.id') && this.get('referenced_speak_mode_user.expired')) {
        if(started < now - (15 * 60 * 1000)) {
          done = i18n.t('expired_supervisee_timeout', "Speak mode sessions are limited to 15 minutes when working with communicators that don't have an active account");
        }
      // If running speak mode as a communicator, leave it go until they're really expired
      var subscribe_redirect = false;
      } else if(this.get('currentUser.really_expired')) {
        if(started < now - (30 * 60 * 1000)) {
          subscribe_redirect = true;
          done = i18n.t('really_expired_communicator_timeout', "This account has expired, and sessions are limited to 30 minutes. If you need help with funding we can help, please contact us!");
        }
      }

      if(done) {
        this.toggle_speak_mode();
        modal.notice(done, true, true, {subscribe_redirect: subscribe_redirect});
        this.set('speak_mode_started', null);
      }
    } else {
      this.set('speak_mode_started', null);
    }
  }.observes('speak_mode_started', 'medium_refresh_stamp'),
  current_board_name: function() {
    var state = this.get('currentBoardState');
    if(state && state.key) {
      return state.name || state.key.split(/\//)[1];
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
  root_board_is_home: function() {
    var state = stashes.get('temporary_root_board_state') || stashes.get('root_board_state');
    var user = this.get('currentUser');
    return !!(state && user && user.get('preferences.home_board.id') == state.id);
  }.property('stashes.root_board_state', 'stashes.temporary_root_board_state', 'currentUser.preferences.home_board.id'),
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
  sidebar_relegated: function() {
    return this.get('speak_mode') && this.get('window_inner_width') < 750;
  }.property('speak_mode', 'window_inner_width'),
  time_string: function(timestamp) {
    return window.moment(timestamp).format("HH:mm");
  },
  fenced_sidebar_board: function() {
    var _this = this;
    var loose_tolerance = 1000; // 1000 ft
    var boards = this.get('currentUser.sidebar_boards_with_fallbacks') || [];
    var all_matches = [];
    var now_time_string = _this.time_string((new Date()).getTime());
    var any_places = false;
    boards.forEach(function(b) { if(b.places) { any_places = true; } });
    var current_place_types = {};
    if(_this.get('nearby_places') && any_places) {
      // set current_place_types to the list of places for the closest-retrieved place
      (_this.get('nearby_places') || []).forEach(function(place) {
        var d = geolocation.distance(place.latitude, place.longitude, stashes.get('geo.latest.coords.latitude'), stashes.get('geo.latest.coords.longitude'));
        // anything with 500ft could be a winner
        if(d && d < 500) {
          place.types.forEach(function(type) {
            if(!current_place_types[type] || current_place_types[type].distance > d) {
              current_place_types[type] = {
                distance: d,
                latitude: place.latitude,
                longitude: place.longitude
              };
            }
          });
        }
      });
    }
    boards.forEach(function(brd) {
      var do_add = false;
      // add all sidebar boards that match any of the criteria
      var ssids = brd.ssids || [];
      if(ssids.split) { ssids = ssids.split(/,/); }
      var matches = {};
      if(ssids && ssids.indexOf(_this.get('current_ssid')) != -1) {
        matches['ssid'] = true;
      }
      var geo_set = false;
      if(brd.geos && stashes.get('geo.latest.coords')) {
        var geos = brd.geos || [];
        if(geos.split) { geos = geos.split(/;/).map(function(g) { return g.split(/,/).map(function(n) { return parseFloat(n); }); }); }
        brd.geo_distance = -1;
        geos.forEach(function(geo) {
          var d = geolocation.distance(stashes.get('geo.latest.coords.latitude'), stashes.get('geo.latest.coords.longitude'), geo[0], geo[1]);
          if(d && d < loose_tolerance && (brd.geo_distance == -1 || d < brd.geo_distance)) {
            brd.geo_distance = d;
            geo_set = true;
            matches['geo'] = true;
          }
        });
      }
      if(brd.times) {
        var all_times = brd.times || [];

        all_times.forEach(function(times) {
          if(times[0] > times[1]) {
            if(now_time_string >= times[0] || now_time_string <= times[1]) {
              matches['time'] = true;
            }
          } else {
            if(now_time_string >= times[0] && now_time_string <= times[1]) {
              matches['time'] = true;
            }
          }
        });
      }
      if(brd.places && Object.keys(current_place_types).length > 0) {
        var places = brd.places || [];
        if(places.split) { places = places.split(/,/); }
        var closest = null;
        places.forEach(function(place) {
          if(current_place_types[place]) {
            if(!closest || current_place_types[place].distance < closest) {
              closest = current_place_types[place].distance;
              matches['place'] = true;
              if(!geo_set) {
                brd.geo_distance = closest;
              }
            }
          }
        });
      }

      if(brd.highlight_type == 'locations' && (matches['geo'] || matches['ssid'])) {
        all_matches.push(brd);
      } else if(brd.highlight_type == 'places' && matches['place']) {
        all_matches.push(brd);
      } else if(brd.highlight_type == 'times' && matches['time']) {
        all_matches.push(brd);
      } else if(brd.highlight_type == 'custom') {
        if(!brd.ssids || matches['ssid']) {
          if(!brd.geos || matches['geo']) {
            if(!brd.places || matches['place']) {
              if(!brd.times || matches['time']) {
                all_matches.push(brd);
              }
            }
          }
        }
      }
    });
    var res = all_matches[0];
    if(all_matches.length > 1) {
      if(!all_matches.find(function(m) { return !m.geo_distance; })) {
        // if it's location-based just return the closest one
        res = all_matches.sort(function(a, b) { return a.geo_distance - b.geo_distance; })[0];
      } else {
        // otherwise craft a special button that pops up the list of matches
      }
    }
    if(res) {
      res = Ember.$.extend({}, res);
      res.fenced = true;
      res.shown_at = (new Date()).getTime();
      _this.set('last_fenced_board', res);
    } else if(_this.get('last_fenced_board') && _this.get('last_fenced_board').shown_at && _this.get('last_fenced_board').shown_at > (new Date()).getTime() - (2*60*1000)) {
      // if there is no fenced board but there was one, go ahead and keep that one around
      // for an extra minute or so
      res = _this.get('last_fenced_board');
    }
    return res;
  }.property('last_fenced_board', 'medium_refresh_stamp', 'current_ssid', 'stashes.geo.latest', 'nearby_places', 'currentUser', 'currentUser.sidebar_boards_with_fallbacks'),
  check_locations: function() {
    var boards = this.get('currentUser.sidebar_boards_with_fallbacks') || [];
    if(!boards.find(function(b) { return b.places; })) { return Ember.RSVP.reject(); }
    var res = geolocation.check_locations();
    res.then(null, function() { });
    return res;
  }.observes('persistence.online', 'stashes.geo.latest', 'currentUser.sidebar_boards_with_fallbacks'),
  sidebar_boards: function() {
    var res = this.get('currentUser.sidebar_boards_with_fallbacks');
    if(!res && window.user_preferences && window.user_preferences.any_user && window.user_preferences.any_user.default_sidebar_boards) {
      res = window.user_preferences.any_user.default_sidebar_boards;
    }
    res = res || [];
    var sb = this.get('fenced_sidebar_board');
    if(!sb) { return res; }
    res = res.filter(function(b) { return b.key != sb.key; });
    res.unshift(sb);
    return res;
  }.property('fenced_sidebar_board', 'currentUser', 'currentUser.sidebar_boards_with_fallbacks'),
  sidebar_pinned: function() {
    return this.get('speak_mode') && this.get('currentUser.preferences.quick_sidebar');
  }.property('speak_mode', 'currentUser', 'currentUser.preferences.quick_sidebar'),
  testing: function() {
    return Ember.testing;
  }.property(),
  logging_paused: function() {
    return !!stashes.get('logging_paused_at');
  }.property('stashes.logging_paused_at'),
  current_time: function() {
    return (this.get('short_refresh_stamp') || new Date());
  }.property('short_refresh_stamp'),
  check_for_user_updated: function(obj, changes) {
    if(window.persistence) {
      if(changes == 'sessionUser' || !window.persistence.get('last_sync_stamp')) {
        window.persistence.set('last_sync_stamp', this.get('sessionUser.sync_stamp'));
      }
    }
    if(this.get('sessionUser')) {
      var interval = (this.get('sessionUser.preferences.sync_refresh_interval') || (15 * 60)) * 1000;
      if(window.persistence) {
        if(window.persistence.get('last_sync_stamp_interval') != interval) {
          window.persistence.set('last_sync_stamp_interval', interval);
        }
      } else {
        console.error('persistence needed for checking user status');
      }
    }
  }.observes('short_refresh_stamp', 'sessionUser'),
  activate_button: function(button, obj) {
    CoughDrop.log.start();
    if((button.hidden || button.empty) && !this.get('edit_mode') && this.get('currentUser.preferences.hidden_buttons') == 'grid') {
      return false;
    }
    var now = (new Date()).getTime();
    if(app_state.get('modeling')) {
      obj.modeling = true;
    } else if(stashes.last_selection && stashes.last_selection.modeling && stashes.last_selection.ts > (now - 500)) {
      obj.modeling = true;
    }
    app_state.set('last_activation', now);
    if(button.link_disabled) {
      button.apps = null;
      button.url = null;
      button.video = null;
      button.load_board = null;
      button.user_integration = null;
    }
    if(button.apps) {
      obj.type = 'app';
    } else if(button.url) {
      if(button.video && button.video.popup) {
        obj.type = 'video';
      } else {
        obj.type = 'url';
      }
    } else if(button.load_board) {
      obj.type = 'link';
    }

    var button_to_speak = obj;
    var specialty = utterance.specialty_button(obj);
    var skip_speaking_by_default = !!(button.load_board || specialty || button_to_speak.special || button.url || button.apps || (button.integration && button.integration.action_type == 'render'));
    if(skip_speaking_by_default && !button.add_to_vocalization) {
    } else if(specialty) {
      button_to_speak = Ember.$.extend({}, specialty);
      button_to_speak.special = true;
    } else {
      button_to_speak = utterance.add_button(obj, button);
    }
//     Ember.$(".hover_button").remove();

    if(obj.label) {
      if(app_state.get('speak_mode')) {
        if(!skip_speaking_by_default) {
          obj.for_speaking = true;
        }

        if(app_state.get('currentUser.preferences.vocalize_buttons') || (!app_state.get('currentUser') && window.user_preferences.any_user.vocalize_buttons)) {
          if(skip_speaking_by_default && !app_state.get('currentUser.preferences.vocalize_linked_buttons') && !button.add_to_vocalization) {
            // don't say it...
            if(app_state.get('currentUser.preferences.click_buttons')) {
              speecher.click();
            }
          } else if(button_to_speak.in_progress && app_state.get('currentUser.preferences.silence_spelling_buttons')) {
            // don't say it...
            if(app_state.get('currentUser.preferences.click_buttons')) {
              speecher.click();
            }
          } else {
            obj.spoken = true;
            obj.for_speaking = true;
            utterance.speak_button(button_to_speak);
          }
        } else if(app_state.get('currentUser.preferences.click_buttons')) {
          speecher.click();
        }
      } else {
        utterance.silent_speak_button(button_to_speak);
      }
    }

//     console.log(obj.label);
    if(button_to_speak.modified && !button_to_speak.in_progress) {
      obj.completion = obj.completion || button_to_speak.label;
    }
//    console.log(obj);
    obj.depth = (stashes.get('boardHistory') || []).length;
    stashes.log(obj);
    var _this = this;

    if(button.load_board && button.load_board.key) {
      if(stashes.get('sticky_board') && app_state.get('speak_mode')) {
        modal.warning(i18n.t('sticky_board_notice', "Board lock is enabled, disable to leave this board."), true);
      } else {

//     var $button = Ember.$(".button[data-id='" + button.id + "']").parent();
//     if($button.length) {
//       var $clone = $button.clone().addClass('hover_button').addClass('touched');
//       var width = $button.find(".button").outerWidth();
//       var height = $button.find(".button").outerHeight();
//       var offset = $button.offset();
//       $clone.css({
//         position: 'absolute',
//         top: offset.top,
//         left: offset.left,
//         width: '',
//         height: ''
//       });
//       $clone.find('.button').css({
//         width: width,
//         height: height
//       });
//
//       Ember.$("body").append($clone);
//       $clone.addClass('selecting');
//
//       Ember.run.later(function() {
//         $button.addClass('selecting');
//         var later = Ember.run.later(function() {
//           Ember.$(".hover_button").remove();
//         }, 3000);
//         $button.data('later', later);
//       });
//     }
        Ember.run.later(function() {
          _this.jump_to_board({
            id: button.load_board.id,
            key: button.load_board.key,
            home_lock: button.home_lock
          }, obj.board);
        }, 50);
      }
    } else if(button.url) {
      if(stashes.get('sticky_board') && app_state.get('speak_mode')) {
        modal.warning(i18n.t('sticky_board_notice', "Board lock is enabled, disable to leave this board."), true);
      } else {
        var real_url = button.url;
        var book_integration = app_state.get('sessionUser.global_integrations.tarheel');
        book_integration = book_integration || ((window.user_preferences || {}).global_integrations || []).indexOf('tarheel') != -1;
        if(button.book && button.book.popup && button.book.url) {
          real_url = button.book.url;
        }
        if(button.video && button.video.popup) {
          modal.open('inline-video', button);
        } else if(button.book && button.book.popup && book_integration) {
          var opts = Ember.$.extend({}, button.book || {});
          delete opts['base_url'];
          delete opts['url'];
          delete opts['popup'];
          delete opts['type'];
          Ember.run.later(function() {
            _this.jump_to_board({
              id: "i_tarheel",
              key: "integrations/tarheel:" + encodeURIComponent(btoa(JSON.stringify(opts))),
              home_lock: button.home_lock
            }, obj.board);
          }, 100);
//           modal.open('inline-book', button);
        } else {
          if((!app_state.get('currentUser') && window.user_preferences.any_user.confirm_external_links) || app_state.get('currentUser.preferences.confirm_external_links')) {
            modal.open('confirm-external-link', {url: button.url, real_url: real_url});
          } else {
            capabilities.window_open(real_url, '_blank');
          }
        }
      }
    } else if(button.apps) {
      if(stashes.get('sticky_board') && app_state.get('speak_mode')) {
        modal.warning(i18n.t('sticky_board_notice', "Board lock is enabled, disable to leave this board."), true);
      } else {
        if((!app_state.get('currentUser') && window.user_preferences.any_user.confirm_external_links) || app_state.get('currentUser.preferences.confirm_external_links')) {
          modal.open('confirm-external-app', {apps: button.apps});
        } else {
          if(capabilities.system == 'iOS' && button.apps.ios && button.apps.ios.launch_url) {
            capabilities.window_open(button.apps.ios.launch_url, '_blank');
          } else if(capabilities.system == 'Android' && button.apps.android && button.apps.android.launch_url) {
            capabilities.window_open(button.apps.android.launch_url, '_blank');
          } else if(button.apps.web && button.apps.web.launch_url) {
            capabilities.window_open(button.apps.web.launch_url, '_blank');
          } else {
            // TODO: handle this edge case smartly I guess
          }
        }
      }
    } else if(button_to_speak.special) {
      if(button.vocalization == ':clear') {
        app_state.controller.send('clear');
      } else if(button.vocalization == ':beep') {
        app_state.controller.send('alert');
      } else if(button.vocalization == ':home') {
        app_state.controller.send('home');
      } else if(button.vocalization == ':back') {
        app_state.controller.send('back');
      } else if(button.vocalization == ':speak') {
        app_state.controller.send('vocalize');
      } else if(button.vocalization == ':backspace') {
        app_state.controller.send('backspace');
      }
    } else if(button.integration && button.integration.action_type == 'webhook') {
      Button.extra_actions(button);
    } else if(button.integration && button.integration.action_type == 'render') {
      Ember.run.later(function() {
      _this.jump_to_board({
        id: "i" + button.integration.user_integration_id,
        key: "integrations/" + button.integration.user_integration_id + ":" + button.integration.action,
        home_lock: button.home_lock
      }, obj.board);
      }, 100);
    } else if(obj.prevent_return) {
      // integrations and configured buttons can explicitly prevent navigating away when activated
    } else if(app_state.get('speak_mode') && ((!app_state.get('currentUser') && window.user_preferences.any_user.auto_home_return) || app_state.get('currentUser.preferences.auto_home_return'))) {
      if(stashes.get('sticky_board') && app_state.get('speak_mode')) {
        var state = stashes.get('temporary_root_board_state') || stashes.get('root_board_state');
        var current = app_state.get('currentBoardState');
        if(state && current && state.key == current.key) {
        } else {
          modal.warning(i18n.t('sticky_board_notice', "Board lock is enabled, disable to leave this board."), true);
        }
      } else if(obj && obj.vocalization && obj.vocalization.match(/^\+/)) {
        // don't home-return when spelling out words
      } else {
        app_state.jump_to_root_board({auto_home: true});
      }
    }
    frame_listener.notify_of_button(button, obj);
    return true;
  },
  remember_global_integrations: function() {
    if(this.get('sessionUser.global_integrations')) {
      stashes.persist('global_integrations', this.get('sessionUser.global_integrations'));
    }
  }.observes('sessionUser.global_integrations'),
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
            if(!b.get('empty_or_hidden')) {
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
    app_state.set('refresh_stamp', (new Date()).getTime());
  }, 5*60*1000);
  setInterval(function() {
    app_state.set('medium_refresh_stamp', (new Date()).getTime());
  }, 60*1000);
  setInterval(function() {
    app_state.set('short_refresh_stamp', (new Date()).getTime());
    if(window.persistence) {
      window.persistence.set('refresh_stamp', (new Date()).getTime());
    } else {
      console.error('persistence needed for setting refresh stamp');
    }
  }, 500);
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
window.app_state = app_state;
export default app_state;
