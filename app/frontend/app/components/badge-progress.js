import Ember from 'ember';
import Component from '@ember/component';
import modal from '../utils/modal';
import i18n from '../utils/i18n';
import { htmlSafe } from '@ember/string';

export default Component.extend({
  didInsertElement: function() {
  },
  badge_container_style: function() {
    var res = '';
    if(this.get('big')) {
      res = 'width: 300px; clear: both; margin-left: 5px;';
    } else {
      res = 'width: 310px; clear: both; margin-left: 39px; margin-top: 5px; margin-bottom: -20px;';
    }
    return htmlSafe(res);
  }.property('big'),
  image_style: function() {
    var res = '';
    if(this.get('big')) {
      res = 'height: 50px; float: left; margin-right: 5px;';
    } else {
      res = 'height: 40px; margin: -5px 5px -5px -5px; float: left;';
    }
    return htmlSafe(res);
  }.property('big'),
  progress_container_style: function() {
    var res = '';
    if(this.get('big')) {
      res = 'height: 50px; font-size: 40px; border-radius: 10px; border: 2px solid rgba(0, 0, 0, 0.5);';
    } else {
      res = 'height: 30px; font-size: 40px; border-radius: 5px; border: 2px solid rgba(0, 0, 0, 0.4);';
    }
    return htmlSafe(res);
  }.property('big'),
  badge_progress: function() {
    return (this.get('badge.progress') || 0) * 100
  }.property('badge.progress'),
  progress_style: function() {
    return htmlSafe('width: ' + this.get('badge_progress') + '%');
  }.property('badge_progress'),
  actions: {
    badge_popup: function(user_id) {
      modal.open('badge-awarded', {badge: {id: this.get('badge.id')}});
    }
  }
});
