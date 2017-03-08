import Ember from 'ember';
import editManager from '../../utils/edit_manager';
import stashes from '../../utils/_stashes';
import modal from '../../utils/modal';
import app_state from '../../utils/app_state';
import i18n from '../../utils/i18n';
import CoughDrop from '../../app';
import contentGrabbers from '../../utils/content_grabbers';
import persistence from '../../utils/persistence';

export default Ember.Route.extend({
  model: function(params) {
    CoughDrop.log.track('getting model');
    var res = this.modelFor('board');
    if(res.get('should_reload')) {
      res.set('should_reload', false);
      CoughDrop.log.track('reloading');
      res.reload();
    }
    return res;
  },
  setupController: function(controller, model) {
    CoughDrop.log.track('setting up controller');
    var _this = this;
    controller.set('model', model);
    controller.set('ordered_buttons', null);
    model.set('show_history', false);
    model.load_button_set();
    app_state.set('currentBoardState', {
      id: model.get('id'),
      key: model.get('key'),
      name: model.get('name'),
      parent_key: model.get('parent_board_key'),
      text_direction: i18n.text_direction(model.get('locale'))
    });
    if(stashes.get('root_board_state.id') == app_state.get('currentBoardState.id') && !stashes.get('root_board_state.text_direction')) {
      stashes.set('root_board_state.text_direction', app_state.get('currentBoardState.text_direction'));
    }
    if(CoughDrop.embedded && !app_state.get('speak_mode')) {
      var state = app_state.get('currentBoardState');
      app_state.toggle_mode('speak', {override_state: state});
      if(app_state.get('currentUser.preferences.home_board')) {
        app_state.toggle_home_lock(true);
      }
      stashes.persist('root_board_state', state);
    }
    editManager.setup(controller);
    app_state.set('board_virtual_dom.sendAction', function(action, id, extra) {
      controller.send(action, id, extra);
    });
    contentGrabbers.board_controller = controller;
    var prior_revision = model.get('current_revision');
    CoughDrop.log.track('processing buttons without lookups');
    model.without_lookups(function() {
      controller.processButtons();
    });
    model.prefetch_linked_boards();

    // if you have the model.id but not permissions, that means you got it from an /index
    // call and it doesn't actually have all the information you need to render, so you
    // better reload. if ordered_buttons isn't set then that just means we need some
    // additional lookups
    if(model.get('integration')) { return; }
    var insufficient_data = model.get('id') && (!controller.get('ordered_buttons') || (!model.get('pseudo_board') && model.get('permissions') === undefined));
    if(persistence.get('online') || insufficient_data) {
      CoughDrop.log.track('considering reload');
      var reload = Ember.RSVP.resolve();
      // if we're online then we should reload, but do it softly if we're in speak mode
      if(persistence.get('online')) {
        // reload(false) says "hey, reload but you can use the local copy if you need to"
        // reload(true) says "definitely ping the server" (same as reload() )
        // TODO: this is failing when the board is available locally but the image isn't available locally
        // looks like this (usually, handle both cases) happens if it's stored in the local db but not
        // yet loaded into ember-data
        var force_fetch = !app_state.get('speak_mode');
        if(persistence.get('syncing') && !insufficient_data) { force_fetch = false; }
        reload = model.reload(force_fetch);
      // if we're offline, then we should only reload if we absolutely have to (i.e. ordered_buttons isn't set)
      } else if(!controller.get('ordered_buttons')) {
        reload = model.reload(false);
      }

      reload.then(function(updated) {
        if(!controller.get('ordered_buttons') || updated.get('current_revision') != prior_revision) {
          CoughDrop.log.track('processing buttons again');
          controller.processButtons();
        }
      }, function(error) {
        if(!controller.get('ordered_buttons') || !app_state.get('speak_mode')) {
          _this.send('error', error);
        }
      });
    }
  },
  actions: {
    willTransition: function(transition) {
      if(app_state.get('edit_mode')) {
        modal.warning(i18n.t('save_or_cancel_changes_first', "Save or cancel your changes before leaving this board!"));
        transition.abort();
      }
      return true;
    },
    error: function(error, transition) {
      this.get('controller').set('model', CoughDrop.store.createRecord('board', {}));
    },
  }
});
