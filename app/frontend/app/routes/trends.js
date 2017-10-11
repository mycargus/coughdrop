import Ember from 'ember';
import persistence from '../utils/persistence';

export default Ember.Route.extend({
  setupController: function(controller, model) {
    controller.load_trends();
  }
});
