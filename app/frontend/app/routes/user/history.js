import Ember from 'ember';
import Route from '@ember/routing/route';
import i18n from '../../utils/i18n';

export default Route.extend({
  model: function(params) {
    return this.modelFor('user');
  },
  setupController: function(controller, model) {
    model.set('show_history', true);
    controller.set('model', model);
    controller.load_results();
  }
});
