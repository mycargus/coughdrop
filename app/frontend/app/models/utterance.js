import Ember from 'ember';
import { later as runLater } from '@ember/runloop';
import DS from 'ember-data';
import CoughDrop from '../app';

CoughDrop.Utterance = DS.Model.extend({
  button_list: DS.attr('raw'),
  sentence: DS.attr('string'),
  link: DS.attr('string'),
  reply_code: DS.attr('string'),
  user_id: DS.attr('string'),
  image_url: DS.attr('string'),
  large_image_url: DS.attr('string'),
  private_only: DS.attr('boolean'),
  permissions: DS.attr('raw'),
  user: DS.attr('raw'),
  show_user: DS.attr('boolean'),
  best_image_url: function() {
    return this.get('large_image_url') || this.get('image_url');
  }.property('image_url', 'large_image_url'),
  check_for_large_image_url: function() {
    var attempt = this.get('large_image_attempt') || 1;
    var _this = this;
    if(_this.get('permissions.edit') && !_this.get('large_image_url') && attempt < 15) {
      runLater(function() {
        _this.set('large_image_attempt', attempt + 1);
        _this.reload().then(function(u) {
          _this.check_for_large_image_url();
        });
      }, attempt * 500);
      return true;
    } else {
      return false;
    }
  },
});

export default CoughDrop.Utterance;
