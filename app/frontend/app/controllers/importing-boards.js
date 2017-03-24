import Ember from 'ember';
import modal from '../utils/modal';

export default modal.ModalController.extend({
  num_percent: function() {
    return Math.round(100 * (this.get('progress.percent') || 0));
  }.property('progress.percent'),
  num_style: function() {
    return new Ember.String.htmlSafe("width: " + this.get('num_percent') + "%;");
  }.property('num_percent')
});
