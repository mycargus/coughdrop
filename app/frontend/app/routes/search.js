import Ember from 'ember';
import Route from '@ember/routing/route';
import app_state from '../utils/app_state';

export default Route.extend({
  title: "Search",
  model: function(params) {
    var q = params.q;
    if(q == '_') { q = ''; }
    this.set('q', q);
    this.set('queryString', decodeURIComponent(q));
    return {};
  },
  setupController: function(controller) {
    controller.set('model', {});
    controller.load_results(this.get('q'));
    controller.set('searchString', this.get('queryString'));
    app_state.set('hide_search', true);
  },
  actions: {
    searchBoards: function() {
      this.transitionTo('search', encodeURIComponent(this.get('controller').get('searchString') || '_'));
    }
  }
});
