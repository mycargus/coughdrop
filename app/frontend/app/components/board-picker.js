import Ember from 'ember';
import contentGrabbers from '../utils/content_grabbers';
import app_state from '../utils/app_state';
import word_suggestions from '../utils/word_suggestions';
import Utils from '../utils/misc';
import CoughDrop from '../app';

export default Ember.Component.extend({
  willInsertElement: function() {
    this.send('set_category', 'robust');
    this.set('show_category_explainer', false);
  },
  categories: function() {
    var res = [];
    var _this = this;
    CoughDrop.board_categories.forEach(function(c) {
      var cat = Ember.$.extend({}, c);
      if(_this.get('current_category') == c.id) {
        cat.selected = true;
      }
      res.push(cat);
    });
    return res;
  }.property('current_category'),
  actions: {
    set_category: function(str) {
      var res = {};
      res[str] = true;
      this.set('current_category', str);
      this.set('category', res);
      this.set('show_category_explainer', false);
      this.set('category_boards', {loading: true});
      var _this = this;
      CoughDrop.store.query('board', {public: true, starred: true, user_id: 'example', sort: 'custom_order', per_page: 6, category: str}).then(function(data) {
        _this.set('category_boards', data);
      }, function(err) {
        _this.set('category_boards', {error: true});
      });
    },
    more_for_category: function() {
      var _this = this;
      _this.set('more_category_boards', {loading: true});
      _this.store.query('board', {public: true, sort: 'home_popularity', per_page: 9, category: this.get('current_category')}).then(function(data) {
        _this.set('more_category_boards', data);
      }, function(err) {
        _this.set('more_category_boards', {error: true});
      });
    },
    show_explainer: function() {
      this.set('show_category_explainer', true);
    },
  }
});
