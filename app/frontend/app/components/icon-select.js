import Ember from 'ember';
import Component from '@ember/component';
import CoughDrop from '../app';
import { reads } from '@ember/object/computed';

export default Component.extend({
  tagName: 'div',
  content: null,
  action: function() { return this; },
  _selection: reads('selection'),
  init: function() {
    this._super(...arguments);
  },
  iconUrls: CoughDrop.iconUrls,
  set_extra_urls: function() {
    if(this.get('selection')) {
      var _this = this;
      var i = new Image();
      i.onload = function() {
        var url = _this.get('selection');
        var urls = [].concat(_this.get('extra_urls') || []);
        urls.push(url);
        urls = urls.uniq();
        _this.set('extra_urls', urls);
        _this.set('selection_preview', url);
      };
      i.onerror = function() {
        _this.set('selection_preview', null);
      };
      i.src = this.get('selection');
    }
  }.observes('selection'),
  included_icon_urls: function() {
    var urls = this.get('extra_urls') || [];
    var icons = this.iconUrls;
    var res = [];
    urls.forEach(function(url) {
      if(url && !icons.find(function(i) { return i.url == url; })) {
        res.push(url);
      }
    });
    return res;
  }.property('extra_urls', 'iconUrls'),
  actions: {
    pick: function(url) {
      this.set('selection_picked', true);
      this.set('_selection', url);
      var callback = this.get('action');
      callback(url);
    }
  }
});
