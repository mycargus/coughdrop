import Ember from 'ember';
import Route from '@ember/routing/route';

export default Route.extend({
  model: function(params) {
    return this.store.findRecord('organization', 'my_org');
  },
  setupController: function(controller, model) {
    this.transitionTo('organization', model.get('id'));
  }
});
