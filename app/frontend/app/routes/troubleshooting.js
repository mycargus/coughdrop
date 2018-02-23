import Ember from 'ember';
import Route from '@ember/routing/route';

export default Route.extend({
  setupController: function(controller) {
    controller.set('results', null);
  }
});
