import Ember from 'ember';
import Controller from '@ember/controller';
import i18n from '../../utils/i18n';
import Utils from '../../utils/misc';
import persistence from '../../utils/persistence';
import modal from '../../utils/modal';

export default Controller.extend({
  first_log: function() {
    return (this.get('model.logs.data') || [])[0];
  }.property('model.logs.data'),
  actions: {
    edit_unit: function() {
      var _this = this;
      modal.open('edit-unit', {unit: _this.get('model')}).then(function(res) {
        if(res && res.updated) {
//          _this.refresh_units();
        }
      });
    },
    delete_unit: function() {
      var _this = this;
      modal.open('confirm-delete-unit', {unit: _this.get('model')}).then(function(res) {
        if(res && res.deleted) {
          _this.transitionToRoute('organization.rooms', _this.get('organization.id'));
        }
      });
    },
    add_users: function() {
      var unit = this.get('model');
      unit.set('adding_users', !unit.get('adding_users'));
    },
    add_unit_user: function(user_type) {
      var unit = this.get('model');
      var action = 'add_' + user_type;
      var user_name = null;
      if(user_type.match('communicator')) {
        user_name = unit.get('communicator_user_name');
      } else {
        user_name = unit.get('supervisor_user_name');
      }
      if(!user_name) { return; }
      action = action + "-" + user_name;
      unit.set('management_action', action);
      unit.save().then(function() {
        unit.set('communicator_user_name', null);
        unit.set('supervisor_user_name', null);
      }, function() {
        modal.error(i18n.t('error_adding_user', "There was an unexpected error while trying to add the user"));
      });
    },
    delete_unit_user: function(unit, user_type, user_id, decision) {
      if(!decision) {
        var _this = this;
        modal.open('modals/confirm-org-action', {action: 'remove_unit_user', unit_user_name: user_id}).then(function(res) {
          if(res.confirmed) {
            _this.send('delete_unit_user', unit, user_type, user_id, true);
          }
        });
        return;
      }
      var unit = this.get('model');
      var action = 'remove_' + user_type + '-' + user_id;
      unit.set('management_action', action);
      unit.save().then(function() {
      }, function() {
        modal.error(i18n.t('error_adding_user', "There was an unexpected error while trying to remove the user"));
      });
    },
  }
});
