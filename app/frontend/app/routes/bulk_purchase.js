import Ember from 'ember';
import Route from '@ember/routing/route';
import Subscription from '../utils/subscription';

export default Route.extend({
  model: function(params) {
    this.set('gift_id', params.id);
  },
  setupController: function(controller, model) {
    controller.load_gift(this.get('gift_id'));
    Subscription.init();
  }
});
