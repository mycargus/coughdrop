import Ember from 'ember';
import RSVP from 'rsvp';
import CoughDrop from '../app';
import modal from '../utils/modal';
import i18n from '../utils/i18n';
import app_state from '../utils/app_state';

export default modal.ModalController.extend({
  opening: function() {
    this.set('existing_user', true);
    this.set('new_user', false);
    var sup = CoughDrop.store.createRecord('user', {
      preferences: {
        registration_type: 'manually-added-supervisor'
      }
    });
    this.set('linking', false);
    this.set('error', null);
    sup.set('watch_user_name', true);
    this.set('model.supervisor', sup);
  },
  actions: {
    close: function() {
      modal.close();
    },
    set_user_type: function(type) {
      if(type == 'new') {
        this.set('existing_user', false);
        this.set('new_user', true);
      } else {
        this.set('existing_user', true);
        this.set('new_user', false);
      }
    },
    add: function() {
      var controller = this;
      controller.set('linking', true);
      var get_user_name = RSVP.resolve(this.get('supervisor_key'));
      if(this.get('new_user')) {
        var supervisor = this.get('model.supervisor');
        supervisor.set('watch_user_name', false);
        get_user_name = supervisor.save().then(function(user) {
          return user.get('user_name');
        }, function() {
          return RSVP.reject(i18n.t('creating_supervisor_failed', "Failed to create a new user with the given settings"));
        });
      }
      get_user_name.then(function(user_name) {
        var user = controller.get('model.user');
        var type = controller.get('edit_permission') ? 'add_edit' : 'add';
        user.set('supervisor_key', type + "-" + user_name);
        return user.save().then(function(user) {
          controller.set('linking', false);
          if(app_state.get('currentUser') && app_state.get('currentUser.id') != user.get('id')) {
            app_state.get('currentUser').reload();
          }
          modal.close();
        }, function() {
          controller.set('linking', false);
          controller.set('error', i18n.t('adding_supervisor_failed_explanation', "The user name provided was not valid, or can't be added to this account."));
        });
      }, function(err) {
          controller.set('linking', false);
          controller.set('error', err);
      });
    }
  }
});
