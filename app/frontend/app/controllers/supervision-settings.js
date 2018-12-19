import Ember from 'ember';
import modal from '../utils/modal';
import app_state from '../utils/app_state';

export default modal.ModalController.extend({
  opening: function() {
    this.set('model', this.get('model.user'));
    this.set('model.load_all_connections', true);
  },
  actions: {
    close: function() {
      modal.close();
    },
    remove_supervisor: function(id) {
      var user = this.get('model');
      user.set('supervisor_key', "remove_supervisor-" + id);
      user.save().then(null, function() {
        alert("sadness!");
      });
    },
    remove_supervision: function(id) {
      var user = this.get('model');
      user.set('supervisor_key', "remove_supervision-" + id);
      user.save().then(null, function() {
        alert("sadness!");
      });
    },
    remove_supervisee: function(id) {
      var user = this.get('model');
      user.set('supervisor_key', "remove_supervisee-" + id);
      user.save().then(null, function() {
        alert("sadness!");
      });
    },
    add_supervisor: function() {
      var _this = this;
      app_state.check_for_full_premium(_this.get('model'), 'add_supervisor').then(function() {
        modal.open('add-supervisor', {user: _this.get('model')});
      }, function() { });
    },
    add_supervisee: function() {
      this.set('add_supervisee_hit', !this.get('add_supervisee_hit'));
    }
  }
});
