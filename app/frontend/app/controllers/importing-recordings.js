import Ember from 'ember';
import modal from '../utils/modal';
import { htmlSafe } from '@ember/string';

export default modal.ModalController.extend({
  num_percent: function() {
    return Math.round(100 * (this.get('progress.percent') || 0));
  }.property('progress.percent'),
  num_style: function() {
    return htmlSafe("width: " + this.get('num_percent') + "%;");
  }.property('num_percent')
});
