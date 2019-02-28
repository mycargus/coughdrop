import Ember from 'ember';
import Route from '@ember/routing/route';

export default Route.extend({
  model: function(params) {
    if(params.id == 'not_found') {
      return {error: true, not_found: true};
    } else if(params.id == 'expired') {
      return {error: true, expired: true};
    }
    return this.store.findRecord('utterance', params.id);
  },
});
