import Ember from 'ember';
import Subscription from '../utils/subscription';

export default Ember.Route.extend({
  model: function(params) {
    this.set('gift_id', params.id);
  },
  setupController: function(controller, model) {
    controller.load_gift(this.get('gift_id'));
    Subscription.init();
  }
});
