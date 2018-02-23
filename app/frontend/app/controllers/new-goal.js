import Ember from 'ember';
import modal from '../utils/modal';
import CoughDrop from '../app';
import app_state from '../utils/app_state';
import i18n from '../utils/i18n';
import editManager from '../utils/edit_manager';

export default modal.ModalController.extend({
  opening: function() {
    this.set('goal', this.get('model.goal') || this.store.createRecord('goal'));
    this.set('error', false);
    this.set('saving', false);
    this.set('browse_goals', false);
    this.set('selected_goal', null);
    if(this.get('model.browse')) {
      this.send('browse_goals');
    }
  },
  save_disabled: function() {
    return this.get('pending_save') || (this.get('browse_goals') && !this.get('selected_goal')) || this.get('saving');
  }.property('pending_save', 'browse_goals', 'selected_goal', 'saving'),
  pending_save: function() {
    return !!this.get('video_pending');
  }.property('video_pending'),
  load_goals: function() {
    var _this = this;
    _this.set('goals', {loading: true});
    CoughDrop.store.query('goal', {template_header: true}).then(function(data) {
      _this.set('goals', data.map(function(i) { return i; }));
      _this.set('goals.meta', data.meta);
    }, function(err) {
      _this.set('goals', {error: true});
    });
  },
  actions: {
    save_goal: function() {
      var _this = this;
      var goal = this.get('goal');
      if(this.get('selected_goal')) {
        goal = this.store.createRecord('goal');
        goal.set('template_id', this.get('selected_goal.id'));
        goal.set('primary', this.get('selected_goal.user_primary'));
      }
      goal.set('user_id', this.get('model.user.id'));
      goal.set('active', true);
      // TODO: something about attaching the video
      _this.set('saving', true);
      _this.set('error', false);
      goal.save().then(function() {
        _this.set('saving', false);
        modal.close(true);
      }, function() {
        _this.set('saving', false);
        _this.set('error', true);
      });
    },
    video_ready: function(id) {
      this.set('video_pending', false);
      if(this.get('goal')) {
        this.set('goal.video_id', id);
      }
    },
    video_not_ready: function() {
      this.set('video_pending', false);
      if(this.get('goal')) {
        this.set('goal.video_id', null);
      }
    },
    video_pending: function() {
      this.set('video_pending', true);
      if(this.get('goal')) {
        this.set('goal.video_id', null);
      }
    },
    browse_goals: function() {
      this.set('browse_goals', !this.get('browse_goals'));
      this.set('selected_goal', null);
      this.load_goals();
    },
    select_goal: function(goal) {
      this.set('selected_goal', goal);
    },
    clear_selected_goal: function() {
      this.set('selected_goal', null);
    },
    reset_video: function() {
      this.set('model.video', null);
    },
    more_goals: function() {
      if(this.get('goals.meta')) {
        var _this = this;
        _this.set('goals.loading', true);
        _this.set('goals.error', true);
        CoughDrop.store.query('goal', {template_header: true, per_page: this.get('goals.meta.per_page'), offset: this.get('goals.meta.next_offset')}).then(function(list) {
          var goals = _this.get('goals') || [];
          goals = goals.concat(list.map(function(i) { return i; }));
          _this.set('goals', goals);
          _this.set('goals.meta', list.meta);
          _this.set('goals.loading', false);
        }, function(err) {
          _this.set('goals.loading', false);
          _this.set('goals.error', true);
        });
      }
    }
  }
});
