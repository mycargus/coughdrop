import Ember from 'ember';
import Route from '@ember/routing/route';
import Subscription from '../utils/subscription';

export default Route.extend({
  setupController: function(controller, model) {
    Subscription.init();
  }
});
