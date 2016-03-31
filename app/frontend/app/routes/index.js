import Ember from 'ember';
import Subscription from '../utils/subscription';
import stashes from '../utils/_stashes';
import app_state from '../utils/app_state';
import modal from '../utils/modal';
import persistence from '../utils/persistence';
import capabilities from '../utils/capabilities';
import CoughDrop from '../app';
import coughDropExtras from '../utils/extras';

export default Ember.Route.extend({
  model: function() {
    if(this.get('session.access_token')) {
      return CoughDrop.store.findRecord('user', 'self').then(function(user) {
        return Ember.RSVP.resolve(user);
      }, function() {
        return Ember.RSVP.resolve(null);
      });
    } else {
      return Ember.RSVP.resolve(null);
    }
  },
  setupController: function(controller, model) {
    controller.set('user', this.get('store').createRecord('user', {preferences: {}}));
    controller.set('user.watch_user_name', true);
    controller.set('subscription', Subscription.create());
    controller.set('model', model);
    // TODO: this seems messy. got to be a cleaner way...
    controller.set('extras', coughDropExtras);
    var jump_to_speak = !!((stashes.get('current_mode') == 'speak' && !document.referrer) || (model && model.get('full_premium') && model.get('preferences.auto_open_speak_mode')));
    if(model && model.get('id') && !model.get('terms_agree')) {
      modal.open('terms-agree');
    } else {
      if(stashes.get('current_mode') == 'edit') {
        stashes.persist('current_mode', 'default');
      } else if(jump_to_speak && model && model.get('id') && !model.get('supporter_role') && !app_state.get('already_homed') && model.get('preferences.home_board.key')) {
        var homey = function() {
          app_state.home_in_speak_mode({user: model});
          app_state.set('already_homed', true);
        };
        // for some reason, iOS doesn't like being auto-launched into speak mode too quickly..
        // android installed app is taking like 5 times as long to load with auto-speak, maybe this will help there too?
        if(capabilities.system == 'iOS' || true) {
          Ember.run.later(homey);
        } else {
          homey();
        }
        return;
      }
    }

    app_state.clear_mode();
    if(!app_state.get('currentUser.preferences.home_board.id')) {
      this.store.query('board', {user_id: 'example', starred: true, public: true}).then(function(boards) {
        controller.set('starting_boards', boards);
      }, function() { });
    }
    if(!this.get('session.isAuthenticated')) {
      controller.set('homeBoards', {loading: true});
      controller.store.query('board', {sort: 'home_popularity', per_page: 9}).then(function(data) {
        controller.set('homeBoards', data);
        controller.checkForBlankSlate();
      }, function() {
        controller.set('homeBoards', {error: true});
        controller.checkForBlankSlate();
      });

      controller.set('popularBoards', {loading: true});
      controller.store.query('board', {sort: 'popularity', per_page: 9}).then(function(data) {
        controller.set('popularBoards', data);
        controller.checkForBlankSlate();
      }, function() {
        controller.set('popularBoards', {error: true});
        controller.checkForBlankSlate();
      });
    }
    controller.update_selected();
    controller.checkForBlankSlate();
  },
  actions: {
    homeInSpeakMode: function(board_for_user_id, keep_as_self) {
      if(board_for_user_id) {
        app_state.set_speak_mode_user(board_for_user_id, true, keep_as_self);
      } else {
        app_state.home_in_speak_mode();
      }
    },
    saveProfile: function() {
      // TODO: add a "save pending..." status somewhere
      var controller = this.get('controller');
      var user = controller.get('user');
      controller.set('triedToSave', true);
      if(!user.get('terms_agree')) { return; }
      if(controller.get('badEmail') || controller.get('shortPassword') || controller.get('noName') || controller.get('noSpacesName')) {
        return;
      }
      var _this = this;
      user.save().then(function(user) {
        var meta = persistence.meta('user', null);
        user.set('password', null);
        _this.transitionTo('index');
        if(meta && meta.access_token) {
          _this.get('session').override(meta);
        }
      }, function() { });
    }
  }
});
