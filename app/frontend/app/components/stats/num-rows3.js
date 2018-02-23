import Ember from 'ember';
import Component from '@ember/component';
import CoughDrop from '../../app';
import i18n from '../../utils/i18n';
import { htmlSafe } from '@ember/string';

export default Component.extend({
  elem_style: function() {
    if(this.get('right_side')) {
      return htmlSafe('border-left: 1px solid #eee;');
    } else {
      return htmlSafe('');
    }
  }.property('right_side'),
});
