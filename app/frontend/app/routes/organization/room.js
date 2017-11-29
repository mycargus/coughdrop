import Ember from 'ember';
import persistence from '../../utils/persistence';

export default Ember.Route.extend({
  model: function(params) {
    var obj = this.store.findRecord('unit', params.room_id);
    var _this = this;
    return obj.then(function(data) {
      if(!data.get('permissions') && persistence.get('online')) {
        Ember.run.later(function() {data.reload();});
      }
      return data;
    });
  },
  setupController: function(controller, model) {
    controller.set('model', model);
    controller.set('organization', this.modelFor('organization'));
    model.load_data();
    controller.get('organization').load_users();
  }
});
