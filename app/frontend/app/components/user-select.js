import Ember from 'ember';
import Component from '@ember/component';
import EmberObject from '@ember/object';
import app_state from '../utils/app_state';
import i18n from '../utils/i18n';
import {set as emberSet, get as emberGet} from '@ember/object';

export default Component.extend({
  tagName: 'span',
  action: function() { return this; },
  didInsertElement: function() {
    var supervisees = [];
    var _this = this;
    if(!this.get('users') && app_state.get('sessionUser.supervisees')) {
      app_state.get('sessionUser.supervisees').forEach(function(supervisee) {
        supervisees.push({
          name: supervisee.user_name,
          image: supervisee.avatar_url,
          disabled: !_this.get('allow_all') && !supervisee.edit_permission,
          id: supervisee.id
        });
      });
      if(supervisees.length > 0) {
        supervisees.unshift({
          name: i18n.t('me', "me"),
          id: 'self',
          disabled: this.get('skip_me'),
          self: true,
          image: app_state.get('sessionUser.avatar_url_with_fallback')
        });
      }
      if(!this.get('buttons')) {
        this.sendAction('action', 'self');
      }
    }
    if(!app_state.get('sessionUser.supervisees') || supervisees.length === 0) {
      this.sendAction('action', 'self');
    }
    this.set('users', this.get('users') || supervisees);
  },
  include_me: function() {
    var self = (this.get('users') || []).find(function(u) { return u.id == 'self'; });
    if(self) {
      emberSet(self, 'disabled', !!this.get('skip_me'));
    }
  }.observes('skip_me'),
  for_user_image: function() {
    var res = null;
    var user_id = this.get('selection');
    (this.get('users') || []).forEach(function(sup) {
      if(sup.id == user_id) {
        res = sup.image;
      }
    });
    return res;
  }.property('users', 'selection'),
  actions: {
    select: function(id) {
      var found = false;
      (this.get('users') || []).forEach(function(sup) {
        if(sup.id == id) {
          emberSet(sup, 'currently_selected', true);
          found = true;
        } else {
          emberSet(sup, 'currently_selected', false);
        }
      });
      if(found) {
        this.sendAction('action', id);
      }
    }
  }
});
