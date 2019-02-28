import Ember from 'ember';
import EmberObject from '@ember/object';
import {set as emberSet, get as emberGet} from '@ember/object';
import modal from '../utils/modal';
import persistence from '../utils/persistence';
import stashes from '../utils/_stashes';
import i18n from '../utils/i18n';
import { htmlSafe } from '@ember/string';

export default modal.ModalController.extend({
  text_note: function() {
    return this.get('note_type') == 'text';
  }.property('note_type'),
  video_note: function() {
    return this.get('note_type') == 'video';
  }.property('note_type'),
  opening: function() {
    var type = this.get('model.type');
    var user = this.get('model.user');
    var _this = this;
    if(user && user.load_active_goals) {
      user.load_active_goals();
    } else if(user) {
      this.store.findRecord('user', user.id).then(function(u) {
        u.load_active_goals();
        _this.set('model', u);
      });
    }
    this.set('goal', this.get('model.goal'));
    this.set('prior', this.get('model.prior'));
    this.set('goal_id', this.get('model.goal.id'));
    if(this.get('model.note_type')) {
      this.set('note_type', this.get('model.note_type'));
    }
    this.set('model', user);
    if(this.get('note_type') === undefined) { this.set('note_type', 'text'); }
    if(this.get('notify') === undefined) { this.set('notify', true); }
  },
  goal_options: function() {
    var res = [];
    if((this.get('model.active_goals') || []).length > 0) {
      res.push({id: '', name: i18n.t('select_goal', "[ Select to Link this Note to a Goal ]")});
      this.get('model.active_goals').forEach(function(goal) {
        res.push({id: goal.get('id'), name: goal.get('summary')});
      });
      res.push({id: '', name: i18n.t('no_goal', "Don't Link this Note to a Goal")});
    }
    return res;
  }.property('model.active_goals'),
  goal_statuses: function() {
    var res = [];
    res.push({
      id: '1',
      text: htmlSafe(i18n.t('we_didnt_do_it', "We didn't<br/>do it")),
      display_class: 'face sad',
      button_display_class: 'btn btn-default face_button'
    });
    res.push({
      id: '2',
      text: htmlSafe(i18n.t('we_did_it', "We barely<br/>did it")),
      display_class: 'face neutral',
      button_display_class: 'btn btn-default face_button'
    });
    res.push({
      id: '3',
      text: htmlSafe(i18n.t('we_did_good', "We did<br/>good!")),
      display_class: 'face happy',
      button_display_class: 'btn btn-default face_button'
    });
    res.push({
      id: '4',
      text: htmlSafe(i18n.t('we_did_awesome', "We did<br/>awesome!")),
      display_class: 'face laugh',
      button_display_class: 'btn btn-default face_button'
    });
    return res;
  }.property(),
  no_video_ready: function() {
    return !this.get('video_id');
  }.property('video_id'),
  text_class: function() {
    var res = "btn ";
    if(this.get('text_note')) {
      res = res + "btn-primary";
    } else {
      res = res + "btn-default";
    }
    return res;
  }.property('text_note'),
  video_class: function() {
    var res = "btn ";
    if(this.get('text_note')) {
      res = res + "btn-default";
    } else {
      res = res + "btn-primary";
    }
    return res;
  }.property('text_note'),
  actions: {
    set_type: function(type) {
      this.set('note_type', type);
    },
    video_ready: function(id) {
      this.set('video_id', id);
    },
    video_not_ready: function() {
      this.set('video_id', false);
    },
    video_pending: function() {
      this.set('video_id', false);
    },
    set_status: function(id) {
      if(this.get('goal_status') == id) { id = null; }
      this.set('goal_status', id);
      this.get('goal_statuses').forEach(function(status) {
        if(status.id == id) {
          emberSet(status, 'button_display_class', 'btn btn-primary face_button');
        } else {
          emberSet(status, 'button_display_class', 'btn btn-default face_button');
        }
      });
    },
    saveNote: function(type) {
      if(type == 'video' && !this.get('video_id')) { return; }
      var _this = this;
      var note = {
        text: _this.get('note')
      };
      if(_this.get('prior')) {
        note.prior = _this.get('prior.note.text');
        note.prior_contact = _this.get('prior.contact');
        note.prior_record_code = "LogSession:" + _this.get('prior.id');
      }
      var notify = this.get('notify') ? 'true' : null;
      if(this.get('notify_user')) {
        if(notify == 'true') {
          notify = 'include_user';
        } else {
          notify = 'user_only';
        }
      }
      var fallback = function() {
        stashes.log_event({
          note: note,
          notify: notify
        }, this.get('model.id'));
        stashes.push_log(true);
      };
      if(persistence.get('online')) {
        var log = _this.store.createRecord('log', {
          user_id: _this.get('model.id'),
          note: note,
          timestamp: Date.now() / 1000,
          notify: notify,
          goal_id: _this.get('goal_id'),
          goal_status: _this.get('goal_status')
        });
        if(type == 'video') {
          log.set('video_id', _this.get('video_id'));
        }
        log.save().then(function() {
          modal.close(true);
        }, function() { 
          fallback();
        });
      } else {
        fallback();
      }
    }
  }
});
