import Ember from 'ember';
import Route from '@ember/routing/route';
import i18n from '../../utils/i18n';

export default Route.extend({
  model: function(params) {
    return this.modelFor('board');
  },
  setupController: function(controller, model) {
    controller.set('key', model.get('lookup_key'));
    model.set('show_history', true);
    controller.load_results();
  }
});
