import Ember from 'ember';
import Route from '@ember/routing/route';

export default Route.extend({
  model: function(params) {
    return this.store.findRecord('utterance', params.id);
  },
});
